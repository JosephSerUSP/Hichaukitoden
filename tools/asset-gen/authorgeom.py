#!/usr/bin/env python3
"""Author source art for image-authored geometry assets.

This is PRE-PRESS, not the compiler. It produces the albedo/height PNG pair
that engine/geometry/ compiles at load; it never emits meshes. Everything here
is deterministic so regenerating an asset is a no-op unless the recipe changed.

Height convention for plane topology: 128 is the neutral wall plane, darker
recedes, lighter projects.

    python tools/asset-gen/authorgeom.py limestone_wall
"""

import argparse
import json
import math
from pathlib import Path

from PIL import Image

SIZE = 128
NEUTRAL = 128
ROOT = Path("assets/geometry")


def noise(x, y, seed):
    """Deterministic value noise in 0..1 -- no RNG state, no platform drift."""
    value = math.sin((x + seed * 0.17) * 12.9898 + (y - seed * 0.31) * 78.233)
    return (value * 43758.5453) % 1.0


def smooth_noise(x, y, seed, scale):
    """Bilinear-interpolated value noise, so erosion reads as broad mottling."""
    fx, fy = x / scale, y / scale
    x0, y0 = math.floor(fx), math.floor(fy)
    tx, ty = fx - x0, fy - y0
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    n00, n10 = noise(x0, y0, seed), noise(x0 + 1, y0, seed)
    n01, n11 = noise(x0, y0 + 1, seed), noise(x0 + 1, y0 + 1, seed)
    return (n00 * (1 - tx) + n10 * tx) * (1 - ty) + (n01 * (1 - tx) + n11 * tx) * ty


def limestone_wall():
    """Warm limestone with shallow block courses and restrained erosion.

    One excellent wall rather than several interchangeable variants: variation
    is meant to come from fixtures and lighting, not from base noise.
    """
    albedo = Image.new("RGBA", (SIZE, SIZE))
    height = Image.new("RGBA", (SIZE, SIZE))
    apx, hpx = [], []
    course = SIZE // 4          # four block courses
    block = SIZE // 2           # two blocks per course, alternating offset
    mortar = 3

    for y in range(SIZE):
        row = y // course
        # Alternate courses shift by half a block, the ordinary running bond.
        shift = (block // 2) if row % 2 else 0
        for x in range(SIZE):
            local_y = y % course
            local_x = (x + shift) % block

            in_mortar = local_y < mortar or local_x < mortar

            # Broad erosion plus a fine grain keeps the stone from reading flat
            # without covering the surface in noise.
            broad = smooth_noise(x, y, 11, 22.0)
            grain = noise(x, y, 4)

            if in_mortar:
                depth = -0.55 - 0.20 * broad
                tone = 0.44 + 0.10 * broad
            else:
                # Each block gets its own slight set, so courses do not look
                # machined. Blocks sit a touch proud of the mortar.
                block_id = (row, (x + shift) // block)
                set_back = (noise(block_id[0], block_id[1], 29) - 0.5) * 0.18
                depth = 0.28 + set_back + 0.10 * (broad - 0.5)
                # Shallow weathering bites into the upper edge of a course.
                weather = max(0.0, 1.0 - local_y / (course * 0.45))
                depth -= 0.22 * weather * broad
                tone = 0.72 + 0.14 * (broad - 0.5) + 0.05 * (grain - 0.5)

            depth = max(-1.0, min(1.0, depth))
            tone = max(0.0, min(1.0, tone))

            # Warm limestone: a touch more red than green, noticeably less blue.
            apx.append((
                int(255 * tone * 0.98),
                int(255 * tone * 0.93),
                int(255 * tone * 0.78),
                255,
            ))
            level = int(round(NEUTRAL + depth * 127))
            hpx.append((level, level, level, 255))

    albedo.putdata(apx)
    height.putdata(hpx)
    return albedo, height, {
        "id": "limestone_wall",
        "role": "surfaceFixture",
        "topology": "plane",
        "surface": "wall",
        "heightOperation": "add",
        "heightScale": 0.06,
        "meshColumns": 16,
        "meshRows": 16,
    }


def idol_silhouette(u, v):
    """Shared front/back silhouette: a shouldered votive slab with a head.

    Returns coverage in 0..1 and a 0..1 'core' value that is 1 at the middle of
    the form and falls to 0 at the contour, which the depth field shapes.
    """
    x = (u - 0.5) * 2.0                      # -1..1 across
    y = v                                    # 0 at top, 1 at bottom

    if y < 0.30:                             # head: a circle
        cx, cy, r = 0.0, 0.16, 0.145
        d = math.hypot(x * 0.5, y - cy)
        return (1.0 if d < r else 0.0), max(0.0, 1.0 - d / r)
    if y < 0.38:                             # neck
        half = 0.10
        inside = abs(x) < half
        return (1.0 if inside else 0.0), max(0.0, 1.0 - abs(x) / half)
    # body: shoulders taper outward then run straight to the base
    shoulder = min(1.0, (y - 0.38) / 0.14)
    half = 0.16 + 0.26 * shoulder
    inside = abs(x) < half
    return (1.0 if inside else 0.0), max(0.0, 1.0 - abs(x) / half)


def sacred_idol():
    """Front/back shell: independently painted faces, one shared silhouette.

    Front carries a carved sigil; the back is plain, weathered stone. Both
    halves share the coverage mask exactly, which is what lets the compiler
    stitch the side deterministically.
    """
    half = 64
    albedo = Image.new("RGBA", (half * 2, half))
    height = Image.new("RGBA", (half * 2, half))
    apx, hpx = [], []

    for y in range(half):
        for x in range(half * 2):
            back = x >= half
            u = (x % half) / (half - 1)
            v = y / (half - 1)
            coverage, core = idol_silhouette(u, v)

            if coverage == 0.0:
                apx.append((0, 0, 0, 0))
                hpx.append((0, 0, 0, 0))
                continue

            weather = smooth_noise(x % half, y, 7, 9.0)
            # Rounded body: depth follows the core, so the form reads as carved
            # rather than as a flat cut-out.
            depth = 0.35 + 0.65 * math.sqrt(core)

            if back:
                tone = 0.52 + 0.16 * (weather - 0.5)
                depth *= 0.72                # the back is a shallower relief
            else:
                # A recessed sigil: a vertical bar with a crossing band.
                bar = abs(u - 0.5) < 0.045 and 0.46 < v < 0.86
                band = abs(v - 0.62) < 0.035 and abs(u - 0.5) < 0.20
                tone = 0.66 + 0.14 * (weather - 0.5)
                if bar or band:
                    depth *= 0.62
                    tone *= 0.72

            depth = max(0.0, min(1.0, depth))
            tone = max(0.0, min(1.0, tone))
            apx.append((
                int(255 * tone * 0.97),
                int(255 * tone * 0.94),
                int(255 * tone * 0.82),
                255,
            ))
            level = int(round(depth * 255))
            hpx.append((level, level, level, 255))

    albedo.putdata(apx)
    height.putdata(hpx)
    return albedo, height, {
        "id": "sacred_idol",
        "role": "objectFixture",
        "topology": "shell",
        "layout": "frontBackHorizontal",
        "surfaceMode": "frontBack",
        "albedoMode": "frontBack",
        "depthScale": 0.30,
        "requireMatchingMasks": True,
        "edgeMode": "stitch",
        "edgeColor": "darkenedBlend",
        "meshColumns": 18,
        "meshRows": 20,
        "blocksMovement": True,
    }


ASSETS = {"limestone_wall": limestone_wall, "sacred_idol": sacred_idol}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("asset", choices=sorted(ASSETS))
    args = parser.parse_args()

    albedo, height, meta = ASSETS[args.asset]()
    out = ROOT / args.asset
    out.mkdir(parents=True, exist_ok=True)
    albedo.save(out / "albedo.png")
    height.save(out / "height.png")
    with open(out / "asset.json", "w", encoding="utf-8", newline="\n") as fh:
        json.dump(meta, fh, indent=2)
        fh.write("\n")
    print(out)


if __name__ == "__main__":
    main()
