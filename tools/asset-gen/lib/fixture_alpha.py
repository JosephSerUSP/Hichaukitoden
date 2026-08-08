"""Alpha authoring rules for localized surface fixtures.

Three failures showed up in the owner's 2026-08-07 review, all of them about
alpha rather than about art:

1. **Too thin to survive.** `mask_alpha` makes alpha exactly the feature mask, so
   a hairline fissure authored at 512 became sub-pixel at the 64px runtime tile.
   Measured: 52 of 4096 runtime texels above half alpha. In engine that is not a
   subtle crack, it is nothing.

2. **No backing.** The bronze inlay's alpha traced only its rings and spokes, so
   the engine received disconnected thin raised lines floating on bare floor
   with no plate behind them. A metal inlay is a disc THAT HAS a pattern, not a
   pattern that happens to be metal.

3. **Alpha wider than the feature.** The collapsed socket's mask reached r=0.45
   while its pit only occupied r<0.30. With `replace`, the fixture overwrote the
   base floor across the whole mask and flattened the surrounding flagstone
   relief to neutral -- which reads, correctly, as the floor collapsing AROUND
   the socket rather than at it.

Alpha is geometric influence, not decoration: at 0 the base surface is untouched,
at 1 the fixture owns the texel. Every rule here is about making the influenced
region match the region the fixture actually has something to say about.
"""
from __future__ import annotations

import numpy as np
from scipy.ndimage import binary_dilation, distance_transform_edt, gaussian_filter

# One runtime texel, in source pixels, for a 512px authored map on a 64px tile.
SOURCE_PER_RUNTIME_TEXEL = 8


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - edge0) / max(1e-6, edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def runtime_texel_coverage(alpha: np.ndarray, tile: int = 64) -> int:
    """How many runtime texels this alpha actually reaches at half strength.

    The honest measure of whether a fixture survives downsampling. A feature can
    look emphatic at authoring resolution and still land on nothing.
    """
    size = alpha.shape[0]
    if size % tile != 0:
        raise ValueError(f"alpha size {size} is not a multiple of tile {tile}")
    block = size // tile
    reduced = alpha.reshape(tile, block, tile, block).mean(axis=(1, 3))
    return int((reduced > 0.5).sum())


def enforce_min_thickness(mask: np.ndarray, runtime_texels: float = 2.0) -> np.ndarray:
    """Widen a mask until its thinnest part spans `runtime_texels` at runtime.

    Dilation, not a redraw: the feature's authored path is the art direction and
    must not move. Only its width is negotiable, because width below one runtime
    texel is not a thinner feature -- it is an absent one.
    """
    if not mask.any():
        return mask
    target = runtime_texels * SOURCE_PER_RUNTIME_TEXEL
    # Half-width, since dilation grows from both sides of the centreline.
    radius = max(0, int(np.ceil(target / 2.0)))
    if radius == 0:
        return mask
    yy, xx = np.mgrid[-radius:radius + 1, -radius:radius + 1]
    disc = (xx * xx + yy * yy) <= radius * radius
    return binary_dilation(mask, structure=disc)


def backing_alpha(feature_mask: np.ndarray, backing_mask: np.ndarray,
                  feather: float = 10.0) -> np.ndarray:
    """Alpha over a solid backing region that CONTAINS the detail.

    The fixture then owns a continuous patch of surface -- a plate, a slab, a
    basin floor -- and its height is free to describe a pattern within that
    patch. Without this the engine gets a stencil of floating fragments.
    """
    combined = feature_mask | backing_mask
    inside = distance_transform_edt(combined)
    alpha = smoothstep(0.0, feather, inside)
    alpha[~combined] = 0.0
    return alpha


def hug_alpha(signed: np.ndarray, feather: float = 10.0,
              deviation: float = 0.02) -> np.ndarray:
    """Alpha that reaches only where the field actually deviates from neutral.

    For `replace` fixtures this is the difference between cutting a pit and
    bulldozing a disc: any texel the fixture claims but has nothing to say about
    gets the base surface's relief erased to neutral for free.
    """
    active = np.abs(signed) > deviation
    if not active.any():
        return np.zeros(signed.shape, dtype=np.float64)
    inside = distance_transform_edt(active)
    alpha = smoothstep(0.0, feather, inside)
    alpha[~active] = 0.0
    # Feathering inward leaves the deepest part opaque and the lip soft, which is
    # what merges a cavity into its surround without a visible alpha rim.
    return gaussian_filter(alpha, 1.0)


def conditioning_image(signed: np.ndarray, alpha: np.ndarray,
                       base_signed: np.ndarray, operation: str) -> np.ndarray:
    """The fixture merged over its real base surface, as SD should see it.

    Conditioning on the fixture over TRANSPARENCY gives the depth preprocessor a
    hard blob boundary with nothing beyond it, and the model paints the object
    that boundary implies -- which is how a broken socket came back as a machined
    porthole and a votive mass came back as a portrait medallion. Showing the
    fixture embedded in the material it will actually sit in removes the cliff
    edge and leaves only the feature as a feature.

    Returns a signed field, opaque everywhere, ready to encode as grey.
    """
    if operation not in ("add", "replace"):
        raise ValueError(f"unknown height operation {operation!r}")
    if operation == "add":
        merged = base_signed + signed * alpha
    else:
        merged = base_signed * (1.0 - alpha) + signed * alpha
    return np.clip(merged, -1.0, 1.0)
