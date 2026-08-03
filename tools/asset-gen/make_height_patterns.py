#!/usr/bin/env python3
"""Create deterministic, tile-safe plane height fields for depth-guided art.

These are authoring guides, not inferred depth. Every pattern wraps in both
axes and is written as an opaque RGBA plane height map with 128 as neutral.
The generated fields deliberately include different architectural structures
so a depth-guided SD batch can be compared against the same source geometry.
"""

import argparse
import json
from pathlib import Path

import numpy
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter


def wrap_delta(value, period):
    return (value + period * 0.5) % period - period * 0.5


def smoothstep(edge0, edge1, value):
    t = numpy.clip((value - edge0) / max(edge1 - edge0, 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def periodic_noise(rng, size, sigma):
    raw = rng.random((size, size))
    field = gaussian_filter(raw, sigma=sigma, mode="wrap")
    field -= field.mean()
    scale = max(float(numpy.max(numpy.abs(field))), 1e-9)
    return field / scale


def brick_relief(size, rng):
    u, v = numpy.meshgrid(numpy.arange(size) / size,
                          numpy.arange(size) / size)
    cols, rows = 4.0, 6.0
    row = numpy.floor(v * rows)
    x = (u * cols + (row % 2) * 0.5) % 1.0
    y = (v * rows) % 1.0
    edge = numpy.minimum(numpy.minimum(x, 1 - x), numpy.minimum(y, 1 - y))
    block = smoothstep(0.02, 0.16, edge)
    mortar = 1.0 - smoothstep(0.005, 0.055, edge)
    rough = periodic_noise(rng, size, 5.5)
    return 0.34 * block + 0.06 * rough - 0.23 * mortar


def regular_wall(size, rng):
    """A restrained, tile-safe masonry guide for the base wall material.

    This intentionally has no repeated sculptural object.  The modest contrast
    leaves SD room to invent stone grain while still providing a stable seam
    rhythm for depth-to-image.
    """
    u, v = numpy.meshgrid(numpy.arange(size) / size,
                          numpy.arange(size) / size)
    cols, rows = 3.0, 4.0
    row = numpy.floor(v * rows)
    x = (u * cols + (row % 2) * 0.5) % 1.0
    y = (v * rows) % 1.0
    edge = numpy.minimum(numpy.minimum(x, 1 - x), numpy.minimum(y, 1 - y))
    stone = smoothstep(0.035, 0.20, edge)
    mortar = 1.0 - smoothstep(0.012, 0.070, edge)
    broad = periodic_noise(rng, size, 13.0)
    grain = periodic_noise(rng, size, 4.5)
    return 0.12 * stone - 0.085 * mortar + 0.018 * broad + 0.010 * grain


def recessed_holes(size, rng):
    u, v = numpy.meshgrid(numpy.arange(size) / size,
                          numpy.arange(size) / size)
    field = numpy.zeros((size, size), dtype=numpy.float64)
    for cy in (0.18, 0.68):
        for cx in (0.16, 0.58, 0.94):
            dx = wrap_delta(u - cx, 1.0)
            dy = wrap_delta(v - cy, 1.0)
            radius = 0.105 + 0.018 * float(rng.random())
            distance = numpy.sqrt((dx / 1.15) ** 2 + (dy * 1.15) ** 2)
            pit = numpy.exp(-((distance / radius) ** 2) * 2.3)
            rim = numpy.exp(-(((distance - radius * 1.12) / (radius * 0.23)) ** 2))
            field += -0.36 * pit + 0.20 * rim
    return field + 0.045 * periodic_noise(rng, size, 8.0)


def broken_flagstones(size, rng):
    u, v = numpy.meshgrid(numpy.arange(size) / size,
                          numpy.arange(size) / size)
    # A small periodic Voronoi field: stone interiors rise, borders recede.
    centres = [(0.12, 0.16), (0.43, 0.12), (0.78, 0.18),
               (0.24, 0.49), (0.59, 0.48), (0.92, 0.55),
               (0.08, 0.84), (0.42, 0.82), (0.75, 0.86)]
    nearest = numpy.full((size, size), 99.0)
    second = numpy.full((size, size), 99.0)
    for cx, cy in centres:
        dx = wrap_delta(u - cx, 1.0)
        dy = wrap_delta(v - cy, 1.0)
        distance = numpy.sqrt(dx * dx + dy * dy)
        replace = distance < nearest
        second = numpy.where(replace, nearest, numpy.minimum(second, distance))
        nearest = numpy.minimum(nearest, distance)
    border = smoothstep(0.018, 0.07, second - nearest)
    chips = periodic_noise(rng, size, 4.0)
    return 0.24 * border + 0.045 * chips - 0.18 * (1 - border)


def stalactite_ceiling(size, rng):
    u, v = numpy.meshgrid(numpy.arange(size) / size,
                          numpy.arange(size) / size)
    field = numpy.zeros((size, size), dtype=numpy.float64)
    for cx, cy, rx, ry in ((0.14, 0.16, 0.10, 0.16),
                           (0.46, 0.34, 0.13, 0.22),
                           (0.78, 0.17, 0.11, 0.18),
                           (0.25, 0.78, 0.14, 0.12),
                           (0.70, 0.76, 0.16, 0.14)):
        dx = wrap_delta(u - cx, 1.0) / rx
        dy = wrap_delta(v - cy, 1.0) / ry
        bump = numpy.exp(-(dx * dx + dy * dy) * 1.5)
        field += 0.24 * bump
        field -= 0.09 * numpy.exp(-((dx * 1.9) ** 2 + (dy * 1.9) ** 2))
    return field + 0.05 * periodic_noise(rng, size, 7.0)


PATTERNS = {
    "regular_wall": regular_wall,
    "wall_relief": brick_relief,
    "recessed_holes": recessed_holes,
    "broken_flagstones": broken_flagstones,
    "stalactite_ceiling": stalactite_ceiling,
}

PATTERN_CONTRAST = {
    "regular_wall": 0.38,
}


def write_height(path, field, contrast=1.0):
    limit = max(float(numpy.percentile(numpy.abs(field), 99.0)), 1e-9)
    normalized = numpy.clip(field / limit, -1.0, 1.0)
    grey = numpy.clip(numpy.rint(128 + normalized * 112 * contrast), 0, 255).astype(numpy.uint8)
    alpha = numpy.full(grey.shape, 255, dtype=numpy.uint8)
    Image.fromarray(numpy.dstack([grey, grey, grey, alpha]), mode="RGBA").save(path)


def matrix(paths, path):
    size = Image.open(paths[0]).size[0]
    sheet = Image.new("RGB", (size * 2, size * 2), (24, 22, 30))
    labels = list(paths)
    draw = ImageDraw.Draw(sheet)
    for index, source in enumerate(paths):
        image = Image.open(source).convert("RGB")
        x, y = (index % 2) * size, (index // 2) * size
        sheet.paste(image, (x, y))
        draw.rectangle((x + 8, y + 8, x + 150, y + 30), fill=(20, 18, 22))
        draw.text((x + 12, y + 12), labels[index].stem, fill=(240, 230, 210))
    sheet.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", help="directory for height PNGs and manifest")
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument("--seed", type=int, default=8421)
    args = parser.parse_args()
    if args.size < 32:
        parser.error("--size must be at least 32")
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    rng = numpy.random.default_rng(args.seed)
    paths = []
    for name, builder in PATTERNS.items():
        path = out / f"{name}.png"
        write_height(path, builder(args.size, rng), PATTERN_CONTRAST.get(name, 1.0))
        paths.append(path)
    matrix(paths, out / "heightmap-matrix.png")
    (out / "manifest.json").write_text(json.dumps({
        "size": args.size, "seed": args.seed,
        "patterns": list(PATTERNS),
        "note": "All patterns use periodic coordinates and are authored depth guides, not inferred depth."
    }, indent=2) + "\n", encoding="utf-8")
    for path in paths:
        print(path)
    print(out / "heightmap-matrix.png")


if __name__ == "__main__":
    main()
