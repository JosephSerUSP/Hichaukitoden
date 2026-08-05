#!/usr/bin/env python3
"""Assemble reviewed single-piece renders into a game atlas and report.

Examples:
  python tools/asset-gen/assemble_atlas.py --cols 4 --rows 4 \
    --out tools/asset-gen/out/dungeon-atlas.png \
    --report tools/asset-gen/out/dungeon-atlas.html \
    --cell 0,0=tools/asset-gen/out/texturePiece-wall/.../variant-1.png

  # The same grid can optionally receive a shared grayscale depth atlas:
  #   --height-out assets/tilesets/dungeon-height.png \
  #   --height-cell 0,0=assets/geometry/hand-authored/wall.png

Coordinates are always ``ROW,COLUMN``, matching ``data/tilesets.json`` atlas
coordinates. The same command assembles a five-column portrait expression sheet with
``--cols 5 --rows 1 --cell-size 128x192``. Inputs must already be processed,
reviewed PNGs from staged runs. The script never promotes into assets/.
"""

import argparse
import base64
import html
import io
import os
from pathlib import Path

from PIL import Image


def parse_size(value):
    try:
        width, height = (int(part) for part in value.lower().split("x"))
        if width <= 0 or height <= 0:
            raise ValueError
        return width, height
    except ValueError as exc:
        raise argparse.ArgumentTypeError("size must be WxH") from exc


def parse_cell(value):
    try:
        key, path = value.split("=", 1)
        row, col = (int(part) for part in key.split(","))
        if row < 0 or col < 0 or not path:
            raise ValueError
        return row, col, path
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            "cell must be ROW,COL=path/to/processed.png") from exc


def embed(image, scale=1):
    if scale != 1:
        image = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
    buf = io.BytesIO()
    image.convert("RGBA").save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def write_report(path, title, atlas, sources, cols, rows, cell_size, base_path=None):
    repeated = Image.new("RGBA", (atlas.width * 3, atlas.height * 3))
    for row in range(3):
        for col in range(3):
            repeated.alpha_composite(atlas, (col * atlas.width, row * atlas.height))
    cards = []
    for (row, col), source in sorted(sources.items()):
        image = Image.open(source).convert("RGBA")
        cards.append(
            f"<figure><figcaption>cell [{row},{col}] — {html.escape(str(source))}</figcaption>"
            f"<img src='{embed(image, 3)}' alt='cell [{row},{col}]'></figure>"
        )
    body = f"""<!doctype html>
<html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>
<title>{html.escape(title)}</title>
<style>
body{{font:15px/1.45 system-ui,sans-serif;background:#17161a;color:#eee8df;margin:2rem}}
main{{max-width:1200px;margin:auto}} .pair{{display:grid;grid-template-columns:minmax(300px,1fr) minmax(300px,1fr);gap:1rem}}
section,figure{{background:#242126;border:1px solid #443d46;border-radius:8px;padding:1rem}}
img{{max-width:100%;image-rendering:pixelated;display:block}} figure{{margin:0}}
.cells{{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:.75rem;margin-top:1rem}}
figcaption{{font-size:.8rem;color:#b8aeb9;overflow-wrap:anywhere;margin-bottom:.5rem}}
code{{color:#eacb84}}
</style></head><body><main>
<h1>{html.escape(title)}</h1>
<p>Assembled from reviewed single-piece Stable Diffusion renders. Grid: {cols}x{rows}; cell: {cell_size[0]}x{cell_size[1]}.</p>
{f"<p>Unspecified cells were inherited from <code>{html.escape(str(base_path))}</code>.</p>" if base_path else ""}
<div class='pair'><section><h2>Atlas</h2><img src='{embed(atlas, 3)}'></section>
<section><h2>3x3 repeat</h2><img src='{embed(repeated)}'></section></div>
<h2>Source pieces</h2><div class='cells'>{''.join(cards)}</div>
</main></body></html>"""
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(body, encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cols", type=int, required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--cell-size", type=parse_size, default=(64, 64))
    parser.add_argument("--out", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--title", default="Assembled game atlas")
    parser.add_argument("--base", help="existing atlas used for cells not overridden")
    parser.add_argument("--cell", action="append", type=parse_cell, required=True)
    parser.add_argument("--height-out", help="optional atlas-sized grayscale height output")
    parser.add_argument("--height-base", help="existing height atlas used for unspecified height cells")
    parser.add_argument("--height-cell", action="append", type=parse_cell,
                        help="HEIGHT cell mapping, e.g. ROW,COL=height.png")
    args = parser.parse_args(argv)
    if args.cols <= 0 or args.rows <= 0:
        parser.error("cols and rows must be positive")

    sources = {}
    for row, col, raw_path in args.cell:
        if row >= args.rows or col >= args.cols:
            parser.error(f"cell [{row},{col}] is outside {args.rows}x{args.cols}")
        if (row, col) in sources:
            parser.error(f"cell [{row},{col}] was supplied twice")
        path = Path(raw_path)
        if not path.is_file():
            parser.error(f"source not found: {path}")
        image = Image.open(path).convert("RGBA")
        if image.size != args.cell_size:
            parser.error(f"{path} is {image.size[0]}x{image.size[1]}, expected "
                         f"{args.cell_size[0]}x{args.cell_size[1]}")
        sources[(row, col)] = path
    atlas_size = (args.cols * args.cell_size[0], args.rows * args.cell_size[1])
    if args.base:
        base = Path(args.base)
        if not base.is_file():
            parser.error(f"base atlas not found: {base}")
        atlas = Image.open(base).convert("RGBA")
        if atlas.size != atlas_size:
            parser.error(f"base atlas is {atlas.width}x{atlas.height}, expected "
                         f"{atlas_size[0]}x{atlas_size[1]}")
    else:
        expected = args.cols * args.rows
        if len(sources) != expected:
            parser.error(f"expected {expected} cells, received {len(sources)}")
        atlas = Image.new("RGBA", atlas_size)
    for (row, col), path in sources.items():
        atlas.alpha_composite(Image.open(path).convert("RGBA"),
                              (col * args.cell_size[0], row * args.cell_size[1]))
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.out)
    if args.height_out:
        height_sources = {}
        for row, col, raw_path in args.height_cell or []:
            if row >= args.rows or col >= args.cols:
                parser.error(f"height cell [{row},{col}] is outside {args.rows}x{args.cols}")
            if (row, col) in height_sources:
                parser.error(f"height cell [{row},{col}] was supplied twice")
            path = Path(raw_path)
            if not path.is_file():
                parser.error(f"height source not found: {path}")
            image = Image.open(path).convert("RGBA")
            if image.size != args.cell_size:
                parser.error(f"height source {path} is {image.width}x{image.height}, expected "
                             f"{args.cell_size[0]}x{args.cell_size[1]}")
            height_sources[(row, col)] = path
        height_size = atlas_size
        if args.height_base:
            height_base = Path(args.height_base)
            if not height_base.is_file():
                parser.error(f"base height atlas not found: {height_base}")
            height_atlas = Image.open(height_base).convert("RGBA")
            if height_atlas.size != height_size:
                parser.error(f"base height atlas is {height_atlas.width}x{height_atlas.height}, expected "
                             f"{height_size[0]}x{height_size[1]}")
        else:
            if len(height_sources) != args.cols * args.rows:
                parser.error("without --height-base, --height-cell must cover every cell")
            height_atlas = Image.new("RGBA", height_size, (128, 128, 128, 255))
        for (row, col), path in height_sources.items():
            height_atlas.paste(Image.open(path).convert("RGBA"),
                               (col * args.cell_size[0], row * args.cell_size[1]))
        Path(args.height_out).parent.mkdir(parents=True, exist_ok=True)
        height_atlas.save(args.height_out)
        print(f"wrote {args.height_out}")
    write_report(args.report, args.title, atlas, sources, args.cols, args.rows,
                 args.cell_size, args.base)
    print(f"wrote {args.out}")
    print(f"wrote {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
