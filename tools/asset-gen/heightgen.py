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


def mask_from_image(path, threshold=0.5):
    """Silhouette from a drawing.

    Uses alpha when the image has any transparency -- the usual case for art
    drawn on a transparent layer -- and otherwise treats non-black luminance as
    the shape, so a plain black-and-white sketch works too.
    """
    image = Image.open(path).convert("RGBA")
    data = np.asarray(image).astype(np.float64) / 255.0
    alpha = data[..., 3]
    if alpha.min() < 1.0:
        return alpha > threshold
    luminance = data[..., :3].mean(axis=2)
    return luminance > threshold


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
    from_mask.add_argument("--halves", action="store_true",
                           help="treat the image as a front/back atlas and bake "
                                "each half separately, so depth cannot bleed "
                                "across the seam")

    args = parser.parse_args()
    if args.command == "from-mask":
        mask = mask_from_image(args.source)
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
