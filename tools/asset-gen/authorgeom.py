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

import heightgen

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
    # Mortar must be wide enough for the declared mesh grid to resolve. At
    # 16x16 over 128px each cell is 8px, so a 3px joint falls between samples
    # and aliases into steep dark ramps that read as detached blocks. Six
    # pixels is the narrowest joint this density can actually represent.
    mortar = 6

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
                # Shallow on purpose: a deep joint at this mesh density becomes
                # a near-vertical facet whose normal faces away from every
                # light, which reads as a gap rather than a recess.
                depth = -0.30 - 0.10 * broad
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


def idol_mask(width, height):
    """The idol's silhouette, as a union of primitives.

    Deliberately NOT a per-region depth recipe. Earlier versions computed a
    separate falloff for the head, the neck and the body, so each tapered to
    zero at its own boundary -- and the head dropped to nothing exactly where
    the neck was thickest, a cliff from 12/255 to 247/255 down the centre line.
    Declaring the SHAPE and letting one distance transform round the whole
    silhouette makes the joins correct by construction.
    """
    u, v = heightgen.grid(width, height)
    # aspect squashes x so that a radius means the same distance on both axes
    # in a non-square image half.
    aspect = width / height
    return heightgen.solid(
        heightgen.disc(u, v, 0.5, 0.17, 0.155, aspect),                 # head
        heightgen.capsule(u, v, 0.5, 0.24, 0.5, 0.46, 0.075, aspect),   # neck
        heightgen.box(u, v, 0.5, 0.72, 0.21, 0.28),                     # body
        heightgen.capsule(u, v, 0.5, 0.44, 0.5, 0.52, 0.20, aspect),    # shoulders
    )


def sacred_idol():
    """Front/back shell: independently painted faces, one shared silhouette.

    Front carries a carved sigil; the back is plain, weathered stone. Both
    halves share the coverage mask exactly, which is what lets the compiler
    stitch the side deterministically.
    """
    half = 64
    mask = idol_mask(half, half)
    # `smooth` meets the central plane with zero slope, so the halves close and
    # the compiler welds the seam instead of leaving two coincident sheets.
    field = heightgen.thickness(mask, profile="smooth")

    albedo = Image.new("RGBA", (half * 2, half))
    height = Image.new("RGBA", (half * 2, half))
    apx, hpx = [], []

    for y in range(half):
        for x in range(half * 2):
            back = x >= half
            column = x % half
            inside = bool(mask[y][column])
            depth = float(field[y][column])

            if not inside:
                # Coverage lives in the HEIGHT alpha. The albedo stays OPAQUE
                # outside it: the shader discards transparent texels, and a
                # boundary quad interpolating into transparent albedo punches
                # holes that tear the model apart.
                apx.append((90, 86, 74, 255))
                hpx.append((0, 0, 0, 0))
                continue

            u = column / (half - 1)
            v = y / (half - 1)
            weather = smooth_noise(column, y, 7, 9.0)

            if back:
                tone = 0.52 + 0.16 * (weather - 0.5)
                depth *= 0.72                # the back is a shallower relief
            else:
                # A recessed sigil: a vertical bar with a crossing band.
                bar = abs(u - 0.5) < 0.045 and 0.52 < v < 0.86
                band = abs(v - 0.66) < 0.035 and abs(u - 0.5) < 0.20
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
        "depthScale": 0.22,
        "requireMatchingMasks": True,
        "edgeMode": "stitch",
        "edgeColor": "darkenedBlend",
        "meshColumns": 18,
        "meshRows": 20,
        "blocksMovement": True,
    }


def fluted_pillar():
    """Radial: a fluted civic pillar with a base and a capital.

    Horizontal is angle, vertical is height, grayscale is radius offset about
    the declared base radius. 128 is that base radius, so flutes cut inward
    while the base and capital swell outward.
    """
    width, height_px = 96, 128
    albedo = Image.new("RGBA", (width, height_px))
    height = Image.new("RGBA", (width, height_px))
    apx, hpx = [], []
    flutes = 12

    for y in range(height_px):
        v = y / (height_px - 1)          # 0 at the top of the pillar
        for x in range(width):
            u = x / width                # full turn; wraps at the seam

            # Vertical profile: a capital at the top, a plinth at the bottom,
            # and a very slight entasis through the shaft between them.
            if v < 0.09:
                profile = 0.62                      # capital abacus
            elif v < 0.15:
                profile = 0.62 - 0.42 * ((v - 0.09) / 0.06)
            elif v > 0.91:
                profile = 0.62                      # plinth
            elif v > 0.85:
                profile = 0.20 + 0.42 * ((v - 0.85) / 0.06)
            else:
                shaft = (v - 0.15) / 0.70
                profile = 0.20 + 0.06 * math.sin(shaft * math.pi)

            # Flutes: shallow vertical grooves, suppressed on capital/plinth so
            # those read as solid mouldings rather than gear teeth.
            groove = math.cos(u * math.pi * 2 * flutes)
            fluting = 0.0 if (v < 0.16 or v > 0.84) else -0.16 * max(0.0, groove)

            weather = smooth_noise(x, y, 23, 12.0)
            radius = profile + fluting + 0.03 * (weather - 0.5)
            radius = max(0.0, min(1.0, radius))

            # Light catches the outer face of each flute ridge.
            tone = 0.60 + 0.22 * max(0.0, groove) + 0.10 * (weather - 0.5)
            if v < 0.15 or v > 0.85:
                tone = 0.66 + 0.10 * (weather - 0.5)
            tone = max(0.0, min(1.0, tone))

            apx.append((
                int(255 * tone * 0.99),
                int(255 * tone * 0.95),
                int(255 * tone * 0.80),
                255,
            ))
            level = int(round(radius * 255))
            hpx.append((level, level, level, 255))

    albedo.putdata(apx)
    height.putdata(hpx)
    return albedo, height, {
        "id": "fluted_pillar",
        "role": "objectFixture",
        "topology": "radial",
        "baseRadius": 0.12,
        "height": 1.40,
        "heightScale": 0.26,
        "angularSegments": 12,
        "verticalSegments": 16,
        "capTop": True,
        "capBottom": True,
        "blocksMovement": True,
    }


def shrine_recess():
    """Surface fixture: an arched votive cavity cut into a wall.

    Uses the `replace` height operation, so inside the arch the wall's own
    block relief is REPLACED by the cavity rather than added to it -- a recess
    that inherited the wall's mortar lines would not read as a cut.

    Height alpha is geometric influence: opaque inside the arch, transparent
    outside, so the wall is untouched beyond the fixture's footprint.
    """
    albedo = Image.new("RGBA", (SIZE, SIZE))
    height = Image.new("RGBA", (SIZE, SIZE))
    apx, hpx = [], []

    cx = 0.5
    top, bottom = 0.20, 0.80
    half_width = 0.20

    for y in range(SIZE):
        v = y / (SIZE - 1)
        for x in range(SIZE):
            u = x / (SIZE - 1)
            dx = abs(u - cx)

            # Arch: a rectangle below the springline, a semicircle above it.
            springline = 0.42
            if v < springline:
                r = math.hypot(dx, (springline - v) * (half_width / (springline - top)))
                inside = r < half_width and v > top
                edge = 1.0 - min(1.0, r / half_width)
            else:
                inside = dx < half_width and v < bottom
                edge = 1.0 - min(1.0, dx / half_width)

            if not inside:
                apx.append((0, 0, 0, 0))
                hpx.append((NEUTRAL, NEUTRAL, NEUTRAL, 0))   # zero influence
                continue

            # A true cavity: deepest at the back, with a chamfered rim so the
            # opening reads as cut stone rather than a painted hole.
            rim = min(1.0, edge / 0.22)
            depth = -0.30 - 0.62 * rim

            grain = smooth_noise(x, y, 31, 10.0)
            shade = 0.30 + 0.26 * (1.0 - rim) + 0.08 * (grain - 0.5)

            # A votive slab sits at the base of the cavity.
            if 0.62 < v < 0.74 and dx < half_width * 0.78:
                depth = -0.30
                shade = 0.52 + 0.10 * (grain - 0.5)

            depth = max(-1.0, min(1.0, depth))
            shade = max(0.0, min(1.0, shade))
            apx.append((
                int(255 * shade * 0.96),
                int(255 * shade * 0.92),
                int(255 * shade * 0.80),
                255,
            ))
            level = int(round(NEUTRAL + depth * 127))
            hpx.append((level, level, level, 255))

    albedo.putdata(apx)
    height.putdata(hpx)
    return albedo, height, {
        "id": "shrine_recess",
        "role": "surfaceFixture",
        "topology": "plane",
        "surface": "wall",
        "heightOperation": "replace",
        "heightScale": 0.14,
        "meshColumns": 16,
        "meshRows": 16,
    }


ASSETS = {
    "limestone_wall": limestone_wall,
    "shrine_recess": shrine_recess,
    "sacred_idol": sacred_idol,
    "fluted_pillar": fluted_pillar,
}


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
