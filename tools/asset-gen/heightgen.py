#!/usr/bin/env python3
"""Generate height maps from intended geometry rather than by hand.

PRE-PRESS, like authorgeom.py: this produces the height PNG that
engine/geometry/ compiles. It never emits meshes.

Two ways in, one shared core:

  1. From a SILHOUETTE IMAGE -- draw a shape, get a rounded solid.
         python tools/asset-gen/heightgen.py from-mask in.png out.png

  2. From a SCRIPT -- compose primitives and let this bake the field.
     Import `solid`, `thickness`, and the shape helpers.

The core is a Euclidean distance transform of the silhouette. Depth at a pixel
is a function of its distance to the nearest EDGE, which is why this is worth
having: it is globally continuous, so shapes that meet -- a head on a neck --
join smoothly with no authoring effort.

Computing depth per-shape instead is the trap. Each region tapers to zero at
its OWN boundary regardless of what it touches, so a sphere meeting a cylinder
drops to nothing exactly where the cylinder is thickest. Measured down the
centre of a hand-authored idol that produced 153, 112, 72, 37, 12, then 247 --
a cliff where the neck jumped a quarter of a cell in front of the head.
"""

import argparse
import math

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt

# Cross-section profiles, as a function of normalized distance from the edge
# (0 at the contour, 1 at the deepest point of the form).
PROFILES = {
    # Circular cross-section: the shape a cylinder of stone would take if you
    # rounded its edges. sqrt(t(2-t)) is the unit circle re-parameterized by
    # distance from the edge rather than from the centre.
    "round": lambda t: np.sqrt(np.clip(t * (2.0 - t), 0.0, 1.0)),
    # Tangent at both ends: meets the central plane with zero slope, so front
    # and back close cleanly and the compiler welds the seam.
    "smooth": lambda t: t * t * (3.0 - 2.0 * t),
    # Flat chamfer. Reads as carved rather than inflated.
    "cone": lambda t: t,
}


def thickness(mask, radius=None, profile="round"):
    """Bake a silhouette into a 0..1 thickness field.

    `mask` is a boolean array, True inside the shape. `radius` is the distance
    from the edge at which the form reaches full depth; None means "the
    thickest part of this shape", which keeps thin features proportionally
    thin instead of inflating everything to the same depth.
    """
    if mask.dtype != bool:
        mask = mask > 0.5
    if not mask.any():
        return np.zeros(mask.shape, dtype=np.float64)
    distance = distance_transform_edt(mask)
    if radius is None:
        radius = float(distance.max())
    if radius <= 0:
        return np.zeros(mask.shape, dtype=np.float64)
    curve = PROFILES[profile]
    return curve(np.clip(distance / radius, 0.0, 1.0)) * mask


def write_height(path, field, mask=None, size=None):
    """Write a height PNG: grayscale carries depth, alpha carries coverage."""
    if mask is None:
        mask = field > 0
    height, width = field.shape
    grey = np.clip(np.rint(field * 255.0), 0, 255).astype(np.uint8)
    alpha = np.where(mask, 255, 0).astype(np.uint8)
    rgba = np.dstack([grey, grey, grey, alpha])
    image = Image.fromarray(rgba, mode="RGBA")
    if size:
        image = image.resize(size, Image.Resampling.NEAREST)
    image.save(path)
    return image


def mask_from_image(path, threshold=0.5, key=None, tolerance=0.04):
    """Silhouette from a drawing.

    Three ways a silhouette gets expressed, in the order they are preferred:

      alpha        art drawn on a transparent layer
      colour key   art on a flat background, which is what pixel art usually
                   is; `key` may be "auto" to take the corner colour
      luminance    a plain black-and-white sketch

    Luminance alone is the wrong default for coloured art: a figure's own dark
    outline and shadows sit below any threshold that excludes the background,
    so the silhouette comes out full of holes.
    """
    image = Image.open(path).convert("RGBA")
    data = np.asarray(image).astype(np.float64) / 255.0
    alpha = data[..., 3]
    if alpha.min() < 1.0:
        return alpha > threshold

    rgb = data[..., :3]
    if key is not None:
        if key == "auto":
            # All four corners agree on a keyed background; disagreement means
            # the guess is unsafe and should be stated rather than assumed.
            corners = [tuple(rgb[0, 0]), tuple(rgb[0, -1]),
                       tuple(rgb[-1, 0]), tuple(rgb[-1, -1])]
            if len(set(corners)) != 1:
                raise SystemExit(
                    "heightgen: --key-color auto needs all four corners to be "
                    "the same colour; pass an explicit #RRGGBB instead")
            colour = np.array(corners[0])
        else:
            text = key.lstrip("#")
            colour = np.array([int(text[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0
        distance = np.abs(rgb - colour).max(axis=2)
        return distance > tolerance

    luminance = rgb.mean(axis=2)
    return luminance > threshold


def bleed(image, mask, iterations=6):
    """Push edge colour outward into the background.

    The compiler discards transparent texels and the mesh stops at the
    silhouette, but a boundary triangle still INTERPOLATES its UVs slightly
    past the mask -- so whatever colour sits just outside shows as a fringe.
    On art keyed off white that reads as a bright halo around the model; off
    black, as a dark outline.

    Repeatedly averaging known neighbours into the unknown region replaces the
    background with a continuation of the art, so the fringe is the figure's
    own colour and becomes invisible. Standard texture-atlas practice, and the
    reason `--bleed` is on by default.
    """
    rgb = np.asarray(image.convert("RGB")).astype(np.float64)
    known = mask.copy()
    filled = rgb.copy()
    for _ in range(iterations):
        if known.all():
            break
        # 4-neighbour sums of known pixels
        total = np.zeros_like(filled)
        count = np.zeros(known.shape, dtype=np.float64)
        for axis, shift in ((0, 1), (0, -1), (1, 1), (1, -1)):
            total += np.roll(np.where(known[..., None], filled, 0), shift, axis=axis)
            count += np.roll(known.astype(np.float64), shift, axis=axis)
        frontier = (~known) & (count > 0)
        safe = np.where(count > 0, count, 1)[..., None]
        filled = np.where(frontier[..., None], total / safe, filled)
        known = known | frontier
    return Image.fromarray(np.clip(filled, 0, 255).astype(np.uint8), mode="RGB")


# --- script-side shape helpers -------------------------------------------
#
# Coordinates are normalized 0..1 over the field, so a recipe is independent of
# the resolution it is baked at.

def grid(width, height):
    ys, xs = np.mgrid[0:height, 0:width]
    return xs / max(1, width - 1), ys / max(1, height - 1)


def disc(u, v, cx, cy, radius, aspect=1.0):
    return ((u - cx) * aspect) ** 2 + (v - cy) ** 2 < radius ** 2


def box(u, v, cx, cy, halfWidth, halfHeight):
    return (np.abs(u - cx) < halfWidth) & (np.abs(v - cy) < halfHeight)


def capsule(u, v, x0, y0, x1, y1, radius, aspect=1.0):
    """A thick line segment -- the honest primitive for a neck or a limb."""
    dx, dy = (x1 - x0) * aspect, y1 - y0
    length2 = dx * dx + dy * dy
    px, py = (u - x0) * aspect, v - y0
    t = np.clip((px * dx + py * dy) / length2, 0.0, 1.0) if length2 > 0 else 0.0
    return (px - t * dx) ** 2 + (py - t * dy) ** 2 < radius ** 2


def solid(*parts):
    """Union. Overlapping primitives become ONE shape, which is the point:
    the distance transform then rounds the whole silhouette together."""
    result = parts[0]
    for part in parts[1:]:
        result = result | part
    return result


def estimate_depth(image, model_id="depth-anything/Depth-Anything-V2-Small-hf",
                   resolution=518):
    """Monocular depth estimate, higher is nearer.

    Imported lazily: the distance-field path is the default and must keep
    working on a machine with no torch at all.
    """
    import torch
    from transformers import AutoImageProcessor, AutoModelForDepthEstimation

    processor = AutoImageProcessor.from_pretrained(model_id)
    model = AutoModelForDepthEstimation.from_pretrained(model_id)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = model.to(device).eval()
    # These models read photographs. Sprite-sized input is far out of
    # distribution, so upscale before inference rather than after.
    large = image.convert("RGB").resize((resolution, resolution), Image.LANCZOS)
    with torch.no_grad():
        inputs = {k: v.to(device) for k, v in
                  processor(images=large, return_tensors="pt").items()}
        depth = model(**inputs).predicted_depth
    return depth.squeeze().float().cpu().numpy()


def thickness_from_depth(image, mask, radius=None, profile="smooth",
                         strength=0.65, model_id=None, percentiles=(2, 98)):
    """Combine an estimated depth with the distance field.

    The estimate supplies INTERIOR form; the distance field supplies the
    contour. Multiplying them is what makes this safe: whatever the model
    hallucinates, depth still reaches zero at the silhouette, so a shell's
    halves close and the mesh stays valid.

    Using the estimate alone still does not work: a monocular model reports
    distance from the CAMERA, not half-thickness about a central plane, so it
    knows nothing about the back of the object and cannot be trusted to reach
    zero at the contour.

    How much the estimate is WORTH depends entirely on the art. Flat four-colour
    sprites give nothing readable. The same figure redrawn with real shading and
    contrast resolves clearly -- crossed arms correctly read as the nearest
    part -- but only once normalized against percentiles, because the raw values
    are packed into a narrow band.
    """
    kwargs = {"model_id": model_id} if model_id else {}
    raw = estimate_depth(image, **kwargs)
    estimate = np.array(Image.fromarray(raw).resize(
        (mask.shape[1], mask.shape[0]), Image.BILINEAR))

    inside = estimate[mask]
    if inside.size == 0 or inside.max() <= inside.min():
        return thickness(mask, radius, profile)
    # Normalize within the silhouette only -- background depth is meaningless
    # here -- and to PERCENTILES rather than min/max. A handful of outlier
    # pixels otherwise eat most of the range and squash all the real structure
    # into a few levels: measured on a 64px figure, 2% of pixels occupied 17%
    # of the min..max span. The form is there; it just needs the contrast.
    low, high = np.percentile(inside, percentiles[0]), np.percentile(inside, percentiles[1])
    if high <= low:
        return thickness(mask, radius, profile)
    normalized = np.clip((estimate - low) / (high - low), 0.0, 1.0)

    base = thickness(mask, radius, profile)
    # strength=0 is the pure distance field; 1 lets the estimate fully shape
    # the interior. The product always vanishes at the contour.
    return base * ((1.0 - strength) + strength * normalized)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    from_mask = sub.add_parser("from-mask",
                               help="bake a silhouette image into a height map")
    from_mask.add_argument("source")
    from_mask.add_argument("output")
    from_mask.add_argument("--profile", choices=sorted(PROFILES), default="round")
    from_mask.add_argument("--radius", type=float, default=None,
                           help="distance from the edge at which full depth is "
                                "reached, in pixels; default is the shape's own "
                                "thickest point")
    from_mask.add_argument("--key-color", default=None,
                           help="treat this background colour as empty; "
                                "\"auto\" takes it from the image corners. Use "
                                "for art on a flat background rather than a "
                                "transparent layer")
    from_mask.add_argument("--tolerance", type=float, default=0.04,
                           help="how close a pixel must be to the key colour to "
                                "count as background (0..1)")
    from_mask.add_argument("--halves", action="store_true",
                           help="treat the image as a front/back atlas and bake "
                                "each half separately, so depth cannot bleed "
                                "across the seam")

    from_depth = sub.add_parser("from-depth",
                                help="bake a height map from a monocular depth "
                                     "estimate, bounded by the silhouette")
    from_depth.add_argument("source")
    from_depth.add_argument("output")
    from_depth.add_argument("--profile", choices=sorted(PROFILES), default="smooth")
    from_depth.add_argument("--radius", type=float, default=None)
    from_depth.add_argument("--key-color", default=None)
    from_depth.add_argument("--tolerance", type=float, default=0.04)
    from_depth.add_argument("--halves", action="store_true")
    from_depth.add_argument("--strength", type=float, default=0.65,
                            help="0 is the pure distance field, 1 lets the "
                                 "estimate fully shape the interior")
    from_depth.add_argument("--model",
                            default="depth-anything/Depth-Anything-V2-Small-hf")

    args = parser.parse_args()
    if args.command == "from-depth":
        mask = mask_from_image(args.source, key=args.key_color,
                               tolerance=args.tolerance)
        image = Image.open(args.source)
        field = np.zeros(mask.shape, dtype=np.float64)
        if args.halves:
            middle = mask.shape[1] // 2
            for lo, hi in ((0, middle), (middle, mask.shape[1])):
                half = image.crop((lo, 0, hi, mask.shape[0]))
                field[:, lo:hi] = thickness_from_depth(
                    half, mask[:, lo:hi], args.radius, args.profile,
                    args.strength, args.model)
        else:
            field = thickness_from_depth(image, mask, args.radius, args.profile,
                                         args.strength, args.model)
        write_height(args.output, field, mask)
        print(args.output)
        return

    if args.command == "from-mask":
        mask = mask_from_image(args.source, key=args.key_color,
                               tolerance=args.tolerance)
        field = np.zeros(mask.shape, dtype=np.float64)
        if args.halves:
            middle = mask.shape[1] // 2
            field[:, :middle] = thickness(mask[:, :middle], args.radius, args.profile)
            field[:, middle:] = thickness(mask[:, middle:], args.radius, args.profile)
        else:
            field = thickness(mask, args.radius, args.profile)
        write_height(args.output, field, mask)
        print(args.output)


if __name__ == "__main__":
    main()
