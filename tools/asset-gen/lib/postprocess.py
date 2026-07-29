"""Pixel post-processing for tools/asset-gen.

Image models return large, smooth, opaque pictures. The engine wants small,
hard-edged, palette-limited, often-transparent sheets at exact dimensions. Every
step of that conversion lives here as a named function; a class's "post" list in
classes.json picks the steps and their order, so a new asset class is data, not
code.

Every step has the signature step(img: RGBA Image, ctx: dict) -> RGBA Image.
ctx carries the resolved geometry ("size", "cell", "frames", "transparent"), the
class definition, and the CLI options.
"""

from PIL import Image, ImageFilter

# The background colour the prompts ask for on transparent classes. Pure magenta
# is the classic chroma key: it appears in no plausible dungeon palette, so a
# wide tolerance cannot eat real art.
KEY_RGB = (255, 0, 255)
KEY_TOLERANCE = 90


# ---------------------------------------------------------------------------
def _distance(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))


def key_background(img, ctx):
    """Knock out the flat chroma-key background, then the corner colour as backup.

    Models often ignore "magenta background" and give a flat grey or white one
    instead, so if keying magenta clears less than 2% of the image we retry with
    whatever colour occupies all four corners (only when they agree, which is the
    signature of a flat backdrop -- a real scene rarely has four matching corners).
    """
    px = img.load()
    w, h = img.size

    def key(target, tolerance):
        cleared = 0
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a and _distance((r, g, b), target) <= tolerance:
                    px[x, y] = (r, g, b, 0)
                    cleared += 1
        return cleared

    cleared = key(KEY_RGB, KEY_TOLERANCE)
    if cleared < (w * h) * 0.02:
        corners = [img.getpixel(p)[:3] for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
        if all(_distance(corners[0], c) <= 24 for c in corners[1:]):
            cleared += key(corners[0], 40)

    if not cleared:
        print("  [key_background] no background keyed -- check the art by eye")
    return img


def _cells(img, cols, rows):
    w, h = img.size
    cw, ch = w // cols, h // rows
    return [img.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            for r in range(rows) for c in range(cols)]


def slice_grid(img, ctx):
    """Cut the model's grid render into cells and rebuild the engine's sheet.

    The prompt asks for a gridHint layout (e.g. 3x1 poses, 4x4 textures); each
    cell is resized to the class's cell size and packed row-major into a sheet
    of exactly `frames` cells laid out as the engine reads them.
    """
    cols, rows = ctx["gridHint"]
    cell_w, cell_h = ctx["cell"]
    frames = ctx["frames"]

    cells = _cells(img, cols, rows)[:frames]
    while len(cells) < frames:                      # short render: repeat the last cell
        cells.append(cells[-1].copy())

    sheet_cols = ctx["size"][0] // cell_w
    sheet_rows = max(1, ctx["size"][1] // cell_h)
    sheet = Image.new("RGBA", tuple(ctx["size"]), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        col, row = index % sheet_cols, index // sheet_cols
        if row >= sheet_rows:
            break
        sheet.paste(_downscale(cell, (cell_w, cell_h)), (col * cell_w, row * cell_h))
    return sheet


def _downscale(img, size):
    """Shrink to pixel-art scale without the mush a plain LANCZOS pass leaves.

    A light sharpen before the reduction keeps the chunky edges that make the
    result read as pixel art rather than as a photograph of pixel art.
    """
    if img.size == tuple(size):
        return img
    if img.size[0] > size[0] * 2:
        img = img.filter(ImageFilter.SHARPEN)
    return img.resize(tuple(size), Image.LANCZOS)


def pixel_fit(img, ctx):
    return _downscale(img, ctx["size"])


def quantize(img, ctx):
    """Clamp to a small adaptive palette, keeping the alpha channel intact.

    PIL's own RGBA quantize folds transparency into the palette and produces
    fringes, so colour and alpha are quantized separately and recombined.
    """
    colors = ctx["classDef"].get("quantizeColors")
    if not colors:
        return img
    alpha = img.getchannel("A")
    rgb = img.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def harden_alpha(img, ctx):
    """Pixel art has no soft edges: every pixel is fully opaque or fully gone."""
    alpha = img.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    img.putalpha(alpha)
    return img


def greyscale(img, ctx):
    """Particle sheets are tinted at runtime, so the art must be neutral."""
    alpha = img.getchannel("A")
    out = img.convert("L").convert("RGBA")
    out.putalpha(alpha)
    return out


def seam_blend_x(img, ctx):
    """Cross-fade the left and right edges so a scrolling panorama wraps cleanly."""
    w, h = img.size
    blend = max(4, w // 16)
    left = img.crop((0, 0, blend, h))
    right = img.crop((w - blend, 0, w, h))
    for x in range(blend):
        weight = x / float(blend)             # 0 at the seam, 1 blend-pixels in
        column_l = left.crop((x, 0, x + 1, h))
        column_r = right.crop((x, 0, x + 1, h))
        mixed = Image.blend(column_r, column_l, weight)
        img.paste(mixed, (w - blend + x, 0))
    return img


STEPS = {
    "key_background": key_background,
    "slice_grid": slice_grid,
    "pixel_fit": pixel_fit,
    "quantize": quantize,
    "harden_alpha": harden_alpha,
    "greyscale": greyscale,
    "seam_blend_x": seam_blend_x,
}


def run(img, ctx, verbose=True):
    img = img.convert("RGBA")
    for name in ctx["classDef"].get("post", []):
        step = STEPS.get(name)
        if step is None:
            raise KeyError(f"unknown post step '{name}' in classes.json")
        img = step(img, ctx)
        if verbose:
            print(f"  post: {name} -> {img.size[0]}x{img.size[1]}")

    if tuple(img.size) != tuple(ctx["size"]):
        raise ValueError(
            f"post-processing produced {img.size[0]}x{img.size[1]}, "
            f"expected {ctx['size'][0]}x{ctx['size'][1]}"
        )
    if not ctx["transparent"]:
        flat = Image.new("RGBA", img.size, (0, 0, 0, 255))
        flat.alpha_composite(img)
        img = flat
    return img


def contact_sheet(paths, scale=4, pad=8):
    """Side-by-side preview of a run's variants, upscaled so pixels stay legible."""
    images = [Image.open(p).convert("RGBA") for p in paths]
    if not images:
        return None
    width = sum(i.width for i in images) * scale + pad * (len(images) + 1)
    height = max(i.height for i in images) * scale + pad * 2
    sheet = Image.new("RGBA", (width, height), (24, 22, 30, 255))
    x = pad
    for img in images:
        big = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
        sheet.alpha_composite(big, (x, pad))
        x += big.width + pad
    return sheet
