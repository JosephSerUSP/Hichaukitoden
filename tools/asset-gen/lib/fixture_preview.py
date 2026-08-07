"""Exact neutral-base previews for alpha-masked surface fixtures.

The runtime interprets height RGB as signed displacement around 128 and alpha as
geometric influence.  These helpers reproduce that contract in Python so a
fixture can be judged without mistaking an opaque ControlNet render for the
thing the engine will actually compose.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt

NEUTRAL = 128
PREVIEW_VERSION = "surface-fixture-neutral-alpha-v2"


def _rgba(image: Image.Image) -> np.ndarray:
    return np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()


def bleed_rgb(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Extend covered colour under transparent texels to prevent edge fringes."""
    inside = alpha > 0
    if not inside.any():
        raise ValueError("fixture alpha contains no covered pixels")
    outside = ~inside
    if not outside.any():
        return rgb.copy()
    _, indices = distance_transform_edt(outside, return_indices=True)
    filled = rgb.copy()
    filled[outside] = rgb[indices[0][outside], indices[1][outside]]
    return filled


def prepare_fixture_albedo(albedo: Image.Image, height: Image.Image) -> Image.Image:
    """Copy authoritative height alpha onto albedo and bleed RGB under it."""
    albedo_data = _rgba(albedo)
    height_data = _rgba(height.resize(albedo.size, Image.Resampling.LANCZOS))
    alpha = height_data[..., 3]
    albedo_data[..., :3] = bleed_rgb(albedo_data[..., :3], alpha)
    albedo_data[..., 3] = alpha
    return Image.fromarray(albedo_data, mode="RGBA")


def normalize_height(height: Image.Image, size: tuple[int, int] | None = None) -> Image.Image:
    """Resize a height map while keeping RGB grayscale and alpha authoritative."""
    image = height.convert("RGBA")
    if size is not None and image.size != size:
        image = image.resize(size, Image.Resampling.LANCZOS)
    data = _rgba(image)
    grey = data[..., 0]
    data[..., 1] = grey
    data[..., 2] = grey
    return Image.fromarray(data, mode="RGBA")


def compose_height(base: Image.Image, fixture: Image.Image, operation: str) -> Image.Image:
    """Compose fixture displacement using the engine's add/replace equations.

    RGB is interpreted as signed displacement around 128. Alpha is applied once
    by the composition operation. The returned diagnostic map is fully opaque.
    """
    if operation not in {"add", "replace"}:
        raise ValueError(f"unsupported height operation: {operation}")
    fixture = normalize_height(fixture, base.size)
    base_data = _rgba(base)
    fixture_data = _rgba(fixture)
    base_signed = base_data[..., 0].astype(np.float64) - NEUTRAL
    fixture_signed = fixture_data[..., 0].astype(np.float64) - NEUTRAL
    alpha = fixture_data[..., 3].astype(np.float64) / 255.0
    if operation == "add":
        composed = base_signed + fixture_signed * alpha
    else:
        composed = base_signed + (fixture_signed - base_signed) * alpha
    grey = np.clip(np.rint(NEUTRAL + composed), 0, 255).astype(np.uint8)
    opaque = np.full_like(grey, 255)
    return Image.fromarray(np.dstack([grey, grey, grey, opaque]), mode="RGBA")


def neutral_height(size: tuple[int, int]) -> Image.Image:
    return Image.new("RGBA", size, (NEUTRAL, NEUTRAL, NEUTRAL, 255))


def composite_albedo_on_neutral(albedo: Image.Image, value: int = 116) -> Image.Image:
    base = Image.new("RGBA", albedo.size, (value, value, value, 255))
    base.alpha_composite(albedo.convert("RGBA"))
    return base


def shade_composite(albedo: Image.Image, height: Image.Image, scale: float) -> Image.Image:
    """A neutral directional diagnostic, not baked lighting for game content."""
    colour = np.asarray(albedo.convert("RGB"), dtype=np.float64)
    grey = np.asarray(height.convert("L"), dtype=np.float64)
    signed = (grey - NEUTRAL) / 127.0
    gy, gx = np.gradient(signed * max(scale, 1e-6) * 28.0)
    nx, ny, nz = -gx, -gy, np.ones_like(gx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / length, ny / length, nz / length
    light = np.asarray([-0.45, -0.55, 1.0], dtype=np.float64)
    light /= np.linalg.norm(light)
    diffuse = np.clip(nx * light[0] + ny * light[1] + nz * light[2], 0.0, 1.0)
    lighting = 0.52 + 0.48 * diffuse
    # Keep the sign legible even under the classic convex/concave light illusion:
    # below-neutral displacement remains darker, above-neutral remains lighter.
    sign_value = np.clip(1.0 + signed * 0.18, 0.78, 1.18)
    shaded = np.clip(colour * (lighting * sign_value)[..., None], 0, 255).astype(np.uint8)
    return Image.fromarray(shaded, mode="RGB")


def _panel(image: Image.Image, label: str, size: int = 256) -> Image.Image:
    picture = image.convert("RGB").resize((size, size), Image.Resampling.NEAREST)
    panel = Image.new("RGB", (size, size + 28), (20, 20, 22))
    panel.paste(picture, (0, 0))
    ImageDraw.Draw(panel).text((7, size + 7), label, fill=(230, 230, 232), font=ImageFont.load_default())
    return panel


def fixture_preview(albedo: Image.Image, height: Image.Image, operation: str,
                    scale: float, surface: str) -> tuple[Image.Image, Image.Image]:
    """Return a three-panel review card and the exact neutral-base height map."""
    prepared = prepare_fixture_albedo(albedo, height)
    composed_albedo = composite_albedo_on_neutral(prepared)
    composed_height = compose_height(neutral_height(prepared.size), height, operation)
    shaded = shade_composite(composed_albedo, composed_height, scale)
    signed = np.asarray(composed_height.convert("L"), dtype=np.int16) - NEUTRAL
    minimum, maximum = int(signed.min()), int(signed.max())
    tendency = "RECESS below neutral" if abs(minimum) >= maximum else "RAISED above neutral"
    cards = [
        _panel(composed_albedo, "authoritative alpha on neutral grey"),
        _panel(composed_height, f"neutral height + {operation} fixture"),
        _panel(shaded, f"{tendency}  {minimum:+d}..{maximum:+d}  scale={scale:g}"),
    ]
    gap = 6
    sheet = Image.new("RGB", (sum(card.width for card in cards) + gap * 2,
                              max(card.height for card in cards)), (12, 12, 14))
    x = 0
    for card in cards:
        sheet.paste(card, (x, 0))
        x += card.width + gap
    return sheet, composed_height


def contact_sheet(paths: list[Path], output: Path) -> None:
    cards = [Image.open(path).convert("RGB") for path in paths]
    if not cards:
        return
    gap = 8
    width = max(card.width for card in cards)
    height = sum(card.height for card in cards) + gap * (len(cards) - 1)
    sheet = Image.new("RGB", (width, height), (14, 14, 16))
    y = 0
    for card in cards:
        sheet.paste(card, (0, y))
        y += card.height + gap
    sheet.save(output, optimize=True)
