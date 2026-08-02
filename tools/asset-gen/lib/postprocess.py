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


def _downscale(img, size, wrap=False):
    """Shrink to pixel-art scale without the mush a plain LANCZOS pass leaves.

    A light sharpen before the reduction keeps the chunky edges that make the
    result read as pixel art rather than as a photograph of pixel art.

    `wrap` matters for anything that has to tile. Both the sharpen kernel and
    the LANCZOS window are clamped at the image border, so the outermost pixels
    are computed from less information than their neighbours -- which quietly
    damages a wrap that was exact on the way in. Padding the image with copies
    of itself first, and cropping afterwards, means every pixel including the
    edges sees a full neighbourhood, and the tile survives the reduction.
    """
    if img.size == tuple(size):
        return img
    if not wrap:
        if img.size[0] > size[0] * 2:
            img = img.filter(ImageFilter.SHARPEN)
        return img.resize(tuple(size), Image.LANCZOS)

    width, height = img.size
    # A whole number of DESTINATION pixels, so the crop lands on an exact
    # boundary and no half-pixel shift creeps in.
    margin = 4
    pad_x, pad_y = margin * width // size[0], margin * height // size[1]
    padded = Image.new(img.mode, (width + 2 * pad_x, height + 2 * pad_y))
    for column in (-1, 0, 1):
        for row in (-1, 0, 1):
            padded.paste(img, (pad_x + column * width, pad_y + row * height))
    if width > size[0] * 2:
        padded = padded.filter(ImageFilter.SHARPEN)
    padded = padded.resize((size[0] + 2 * margin, size[1] + 2 * margin), Image.LANCZOS)
    return padded.crop((margin, margin, margin + size[0], margin + size[1]))


def pixel_fit(img, ctx):
    return _downscale(img, ctx["size"], wrap=ctx["classDef"].get("tiles", False))


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


def _step_scale(steps):
    """What counts as a strong edge in this texture: the 95th-percentile step.

    Not the mean, which a mostly-smooth material drags to near zero, and not the
    maximum, which one stray pixel row can own.
    """
    import numpy

    return max(float(numpy.percentile(steps, 95)), 0.5)


def tile_seam_score(img):
    """How visible is the wrap seam, relative to this texture's own busyness?

    A RATIO, not a difference. The absolute gap between the first and last
    column says nothing on its own: a noisy granite texture has large
    column-to-column differences everywhere, and a flat plaster one has almost
    none, so the same absolute number means "invisible" in the first and
    "glaring" in the second. It is compared against the STRONGEST transitions
    the texture already contains -- the 95th percentile of the steps between
    adjacent interior lines -- which asks the only question that matters: would
    this join look out of place among the edges this material already has?

    Normalising against the MEAN interior step, as this first did, fails on the
    most common texture in the project. A brick wall is mostly smooth field with
    a few hard mortar lines, so the mean is tiny; when a mortar line lands on the
    wrap -- which is what a well-made brick tile does deliberately -- the ratio
    read 10 and the audit called a perfectly tiling hand-made wall broken.
    Measured on that wall: wrap step 54, mean interior step 5.5, but the mortar
    lines themselves step 47-49. The seam is one of its own edges.

      ~1.0  the wrap is indistinguishable from the interior
      >2    a join a player will see once the texture repeats down a corridor

    Returned per axis, because a wall tiles horizontally while a floor tiles
    both ways, and a texture can be perfect on one axis and broken on the other.

    An axis whose two edges are TRANSPARENT returns None, not a perfect score.
    A cut-out figure has nothing at its left and right edges, so the naive ratio
    calls it a flawless tile -- that is the metric failing to see, not the
    texture passing. Caught by scoring a figure asset as a negative control,
    which is the only reason to ever run one.

    A flat but OPAQUE edge is measured normally: a texture banded horizontally
    has an identical run of colour down both sides and genuinely does tile that
    way. An earlier version rejected those as unmeasurable and threw away the
    one case that is trivially correct.
    """
    import numpy

    rgba = numpy.asarray(img.convert("RGBA"), dtype=numpy.float32)
    pixels, alpha = rgba[:, :, :3], rgba[:, :, 3]
    if pixels.shape[0] < 3 or pixels.shape[1] < 3:
        return {"x": None, "y": None, "note": "too small to score"}

    result = {}
    for axis in ("x", "y"):
        if axis == "x":
            near, far = pixels[:, 0, :], pixels[:, -1, :]
            near_a, far_a = alpha[:, 0], alpha[:, -1]
            interior = _step_scale(numpy.abs(numpy.diff(pixels, axis=1)).mean(axis=(0, 2)))
        else:
            near, far = pixels[0, :, :], pixels[-1, :, :]
            near_a, far_a = alpha[0, :], alpha[-1, :]
            interior = _step_scale(numpy.abs(numpy.diff(pixels, axis=0)).mean(axis=(1, 2)))

        # Nothing at the edges to compare: this is a cut-out, not a tile.
        if max(float(near_a.mean()), float(far_a.mean())) < 8:
            result[axis] = None
            result["note"] = (result.get("note", "")
                              + f"{axis}: edges are transparent, not a tiling surface. ")
            continue

        wrap = float(numpy.abs(near - far).mean())
        # A texture with no interior variation has nothing to normalise against;
        # then the wrap difference IS the answer, in 0-255 terms.
        result[axis] = round(wrap if interior < 0.5 else wrap / interior, 3)

    # The line down the MIDDLE, on the same scale.
    #
    # Measuring only the border is how a seam hides. Offset-and-inpaint does not
    # remove a texture's discontinuity, it RELOCATES it to the centre -- so a
    # texture can score a perfect wrap while carrying a hard line down its
    # middle, which is exactly what the first version of this function called
    # seamless. Checking the centre specifically, rather than the worst line
    # anywhere, is deliberate: a brick texture is SUPPOSED to have hard lines at
    # its mortar, and a metric that punished those would be useless on the very
    # material this project is mostly made of.
    for axis, step_axis in (("x", 1), ("y", 0)):
        steps = numpy.abs(numpy.diff(pixels, axis=step_axis)).mean(
            axis=tuple(index for index in (0, 1, 2) if index != step_axis))
        typical = _step_scale(steps)
        middle = len(steps) // 2
        # A window, not a single line: mask blur spreads the repaint over a few
        # pixels and the exact centre can land either side of the join.
        centre = float(steps[max(0, middle - 2):middle + 2].max())
        result[f"centre_{axis}"] = round(centre if typical < 0.5 else centre / typical, 3)
    return result


def tile_score(img, ctx):
    """Measure the wrap seam and record it in ctx. Does not touch the pixels."""
    ctx["tileScore"] = tile_seam_score(img)
    return img


def tiled_sheet(path, repeat=3, scale=2):
    """The texture laid out `repeat` times each way -- what the seam looks like."""
    tile = Image.open(path).convert("RGBA")
    sheet = Image.new("RGBA", (tile.width * repeat, tile.height * repeat))
    for row in range(repeat):
        for column in range(repeat):
            sheet.paste(tile, (column * tile.width, row * tile.height))
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)


STEPS = {
    "key_background": key_background,
    "tile_score": tile_score,
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
