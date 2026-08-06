#!/usr/bin/env python3
"""Build the authored height/control maps for the 2026-08-06 first-stratum batch.

The generated PNGs follow the image-authored-geometry contract:

* RGB is grayscale; 128 is the neutral plane.
* Alpha is geometric influence. Base surfaces are fully opaque. Local fixtures
  are transparent outside their footprint and feather to opaque at the merge.
* Wall maps wrap on X. Floor and ceiling maps wrap on X and Y. Local fixtures
  reach neutral, zero-alpha borders, so they compose without a repeated ridge.

This script is deterministic and intentionally contains no image-model calls.
Stable Diffusion is conditioned on these maps later; it never invents geometry.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt, gaussian_filter

ROOT = Path(__file__).resolve().parents[2]
BATCH_ROOT = ROOT / "assets" / "geometry" / "3_authored_surface_maps" / "first_stratum_20260806"
HEIGHT_DIR = BATCH_ROOT / "height"
MANIFEST_PATH = BATCH_ROOT / "manifest.json"
CONTACT_PATH = BATCH_ROOT / "contact-sheet.png"
SIZE = 512
NEUTRAL = 128


@dataclass(frozen=True)
class MapSpec:
    name: str
    surface: str
    role: str
    operation: str
    scale: float
    description: str
    builder: Callable[[int], tuple[np.ndarray, np.ndarray]]

    @property
    def tile_axes(self) -> str:
        return "x" if self.surface == "wall" else "xy"


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    width = max(1e-9, edge1 - edge0)
    t = np.clip((value - edge0) / width, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def periodic_noise(size: int, seed: int, octaves: tuple[tuple[int, float], ...]) -> np.ndarray:
    """Low-cost periodic noise from random Fourier components."""
    rng = np.random.default_rng(seed)
    u = np.linspace(0.0, 1.0, size, endpoint=True)
    v = np.linspace(0.0, 1.0, size, endpoint=True)
    uu, vv = np.meshgrid(u, v)
    field = np.zeros((size, size), dtype=np.float64)
    weight = 0.0
    for frequency, amplitude in octaves:
        component = np.zeros_like(field)
        count = 5 + frequency
        for _ in range(count):
            fx = int(rng.integers(1, frequency + 2))
            fy = int(rng.integers(1, frequency + 2))
            phase = float(rng.uniform(0.0, math.tau))
            component += np.sin(math.tau * (fx * uu + fy * vv) + phase)
        component /= max(1, count)
        field += component * amplitude
        weight += amplitude
    field /= max(weight, 1e-9)
    maximum = float(np.max(np.abs(field))) or 1.0
    return np.clip(field / maximum, -1.0, 1.0)


def toroidal_voronoi(size: int, seed: int, columns: int, rows: int,
                      x_scale: float = 1.0, y_scale: float = 1.0):
    """Periodic nearest/second-nearest cell fields and per-cell random values."""
    rng = np.random.default_rng(seed)
    points = []
    values = []
    for row in range(rows):
        for column in range(columns):
            jitter_x = rng.uniform(-0.22, 0.22) / columns
            jitter_y = rng.uniform(-0.22, 0.22) / rows
            points.append(((column + 0.5) / columns + jitter_x,
                           (row + 0.5) / rows + jitter_y))
            values.append(float(rng.uniform(-1.0, 1.0)))
    points = np.asarray(points)
    values = np.asarray(values)

    coordinate = np.linspace(0.0, 1.0, size, endpoint=True)
    uu, vv = np.meshgrid(coordinate, coordinate)
    distances = []
    for px, py in points:
        dx = np.minimum(np.abs(uu - px), 1.0 - np.abs(uu - px)) * x_scale
        dy = np.minimum(np.abs(vv - py), 1.0 - np.abs(vv - py)) * y_scale
        distances.append(dx * dx + dy * dy)
    stack = np.stack(distances, axis=0)
    order = np.argpartition(stack, 1, axis=0)
    first_index = order[0]
    second_index = order[1]
    first = np.take_along_axis(stack, first_index[None, ...], axis=0)[0]
    second = np.take_along_axis(stack, second_index[None, ...], axis=0)[0]
    cell_value = values[first_index]
    boundary = np.sqrt(np.maximum(second, 0.0)) - np.sqrt(np.maximum(first, 0.0))
    return first, boundary, cell_value


def force_wrap(field: np.ndarray, axes: str) -> np.ndarray:
    result = field.copy()
    if "x" in axes:
        edge = (result[:, 0] + result[:, -1]) * 0.5
        result[:, 0] = edge
        result[:, -1] = edge
    if "y" in axes:
        edge = (result[0, :] + result[-1, :]) * 0.5
        result[0, :] = edge
        result[-1, :] = edge
    return result


def mask_alpha(mask: np.ndarray, feather: float = 12.0) -> np.ndarray:
    """Opaque interior with a smooth geometric merge at the contour."""
    if not mask.any():
        return np.zeros(mask.shape, dtype=np.float64)
    inside = distance_transform_edt(mask)
    alpha = smoothstep(0.0, feather, inside)
    alpha[~mask] = 0.0
    return alpha


def write_height(path: Path, signed: np.ndarray, alpha: np.ndarray) -> None:
    signed = np.clip(signed, -1.0, 1.0)
    grey = np.clip(np.rint(NEUTRAL + signed * 127.0), 0, 255).astype(np.uint8)
    coverage = np.clip(np.rint(alpha * 255.0), 0, 255).astype(np.uint8)
    rgba = np.dstack([grey, grey, grey, coverage])
    Image.fromarray(rgba, mode="RGBA").save(path, optimize=True)


def floor_flagstones(size: int):
    _, boundary, cell = toroidal_voronoi(size, 6101, 4, 4, x_scale=1.0, y_scale=1.0)
    grain = periodic_noise(size, 6102, ((2, 0.55), (5, 0.28), (11, 0.17)))
    mortar = 1.0 - smoothstep(0.008, 0.032, boundary)
    field = 0.22 + cell * 0.10 + grain * 0.055 - mortar * 0.55
    field = gaussian_filter(field, 1.0, mode="wrap")
    return force_wrap(field, "xy"), np.ones_like(field)


def floor_slabs(size: int):
    _, boundary, cell = toroidal_voronoi(size, 6201, 3, 4, x_scale=0.78, y_scale=1.22)
    grain = periodic_noise(size, 6202, ((2, 0.62), (6, 0.25), (13, 0.13)))
    joint = 1.0 - smoothstep(0.010, 0.038, boundary)
    broad_set = gaussian_filter(cell, 5.0, mode="wrap")
    field = 0.16 + broad_set * 0.16 + grain * 0.06 - joint * 0.48
    return force_wrap(gaussian_filter(field, 1.2, mode="wrap"), "xy"), np.ones_like(field)


def wall_ashlar(size: int):
    rng = np.random.default_rng(6301)
    y = np.linspace(0.0, 1.0, size, endpoint=True)
    x = np.linspace(0.0, 1.0, size, endpoint=True)
    xx, yy = np.meshgrid(x, y)
    courses = 4
    local_y = (yy * courses) % 1.0
    course_index = np.minimum((yy * courses).astype(int), courses - 1)
    field = np.full((size, size), 0.20, dtype=np.float64)
    horizontal_joint = np.minimum(local_y, 1.0 - local_y)
    field -= (1.0 - smoothstep(0.02, 0.13, horizontal_joint)) * 0.48
    for course in range(courses):
        blocks = 2 if course % 2 == 0 else 3
        offset = 0.0 if course % 2 == 0 else 0.17
        local_x = ((xx + offset) * blocks) % 1.0
        vertical_distance = np.minimum(local_x, 1.0 - local_x)
        joint = 1.0 - smoothstep(0.018, 0.11, vertical_distance)
        row_mask = course_index == course
        field[row_mask] -= joint[row_mask] * 0.42
        for block in range(blocks):
            block_mask = row_mask & ((((xx + offset) * blocks).astype(int) % blocks) == block)
            field[block_mask] += rng.uniform(-0.10, 0.12)
    field += periodic_noise(size, 6302, ((2, 0.7), (7, 0.3))) * 0.05
    field = gaussian_filter(field, 1.1, mode=("nearest", "wrap"))
    return force_wrap(field, "x"), np.ones_like(field)


def wall_limewash(size: int):
    broad = periodic_noise(size, 6401, ((1, 0.72), (3, 0.21), (7, 0.07)))
    fine = periodic_noise(size, 6402, ((5, 0.55), (11, 0.45)))
    field = broad * 0.10 + fine * 0.025
    # Three shallow, broad losses in the plaster. They remain material-scale,
    # not literal photographed holes or a perspective scene.
    coordinate = np.linspace(-1.0, 1.0, size, endpoint=True)
    xx, yy = np.meshgrid(coordinate, coordinate)
    for cx, cy, rx, ry, depth in [(-0.42, -0.24, 0.26, 0.18, -0.16),
                                  (0.36, 0.18, 0.30, 0.22, -0.12),
                                  (0.02, 0.62, 0.22, 0.13, -0.10)]:
        d = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
        field += np.clip(1.0 - d, 0.0, 1.0) ** 2 * depth
    return force_wrap(gaussian_filter(field, 2.0, mode=("nearest", "wrap")), "x"), np.ones_like(field)


def ceiling_ribs(size: int):
    coordinate = np.linspace(0.0, 1.0, size, endpoint=True)
    xx, yy = np.meshgrid(coordinate, coordinate)
    # Two broad crossing ribs, periodic and deliberately shallow.
    d1 = np.abs(((xx - yy + 0.5) % 1.0) - 0.5)
    d2 = np.abs(((xx + yy + 0.5) % 1.0) - 0.5)
    ribs = np.maximum(np.exp(-(d1 / 0.055) ** 2), np.exp(-(d2 / 0.055) ** 2))
    bay = periodic_noise(size, 6501, ((1, 0.75), (4, 0.25)))
    field = -0.14 + ribs * 0.42 + bay * 0.035
    return force_wrap(gaussian_filter(field, 1.2, mode="wrap"), "xy"), np.ones_like(field)


def ceiling_coffers(size: int):
    coordinate = np.linspace(0.0, 1.0, size, endpoint=True)
    xx, yy = np.meshgrid(coordinate, coordinate)
    gx = np.minimum((xx * 2.0) % 1.0, 1.0 - ((xx * 2.0) % 1.0))
    gy = np.minimum((yy * 2.0) % 1.0, 1.0 - ((yy * 2.0) % 1.0))
    edge = np.minimum(gx, gy)
    rim = 1.0 - smoothstep(0.035, 0.15, edge)
    inner = smoothstep(0.11, 0.22, edge)
    field = -0.20 * inner + 0.25 * rim
    field += periodic_noise(size, 6601, ((2, 0.65), (6, 0.35))) * 0.035
    return force_wrap(gaussian_filter(field, 1.0, mode="wrap"), "xy"), np.ones_like(field)


def fixture_grid(size: int):
    coordinate = np.linspace(-1.0, 1.0, size, endpoint=True)
    return np.meshgrid(coordinate, coordinate)


def wall_votive_relief(size: int):
    xx, yy = fixture_grid(size)
    oval = (xx / 0.36) ** 2 + ((yy + 0.02) / 0.52) ** 2 < 1.0
    stem = (np.abs(xx) < 0.075) & (yy > -0.42) & (yy < 0.45)
    arms = (np.abs(yy + 0.02) < 0.065) & (np.abs(xx) < 0.28)
    mask = oval | stem | arms
    alpha = mask_alpha(mask, 13.0)
    distance = distance_transform_edt(mask)
    relief = smoothstep(0.0, 36.0, distance)
    field = (0.08 + relief * 0.68) * alpha
    return field, alpha


def wall_niche(size: int):
    xx, yy = fixture_grid(size)
    spring = -0.12
    half_width = 0.34
    rectangle = (np.abs(xx) < half_width) & (yy >= spring) & (yy < 0.64)
    arch = (xx / half_width) ** 2 + ((yy - spring) / 0.36) ** 2 < 1.0
    arch &= yy < spring
    mask = rectangle | arch
    alpha = mask_alpha(mask, 14.0)
    distance = distance_transform_edt(mask)
    interior = smoothstep(2.0, 48.0, distance)
    # Replace operation: a modest proud rim falls into a deep back plane.
    field = (0.22 * (1.0 - interior) - 0.82 * interior) * alpha
    shelf = (np.abs(xx) < 0.27) & (yy > 0.42) & (yy < 0.52) & mask
    field[shelf] = -0.18 * alpha[shelf]
    return gaussian_filter(field, 0.8), alpha


def wall_breach(size: int):
    xx, yy = fixture_grid(size)
    angle = 0.18
    xr = xx * math.cos(angle) - yy * math.sin(angle)
    yr = xx * math.sin(angle) + yy * math.cos(angle)
    radius = np.sqrt((xr / 0.34) ** 2 + ((yr + 0.02) / 0.27) ** 2)
    wobble = periodic_noise(size, 6701, ((2, 0.65), (5, 0.35))) * 0.12
    mask = radius + wobble < 1.0
    alpha = mask_alpha(mask, 12.0)
    distance = distance_transform_edt(mask)
    interior = smoothstep(1.0, 34.0, distance)
    rim = np.exp(-((radius - 0.86) / 0.10) ** 2)
    field = (-0.88 * interior + 0.30 * rim) * alpha
    return gaussian_filter(field, 0.9), alpha


def wall_runnel(size: int):
    xx, yy = fixture_grid(size)
    centre = 0.06 * np.sin((yy + 1.0) * 5.6) - 0.05 * np.sin((yy + 0.2) * 11.0)
    trunk = np.abs(xx - centre) < (0.055 + 0.025 * (yy + 1.0) * 0.5)
    branch_a = (np.abs(yy + 0.18 + 1.8 * (xx + 0.15)) < 0.045) & (xx < -0.04) & (yy < 0.05)
    branch_b = (np.abs(yy - 0.28 - 1.5 * (xx - 0.13)) < 0.038) & (xx > 0.05) & (yy > 0.0)
    mask = (trunk | branch_a | branch_b) & (np.abs(xx) < 0.42) & (np.abs(yy) < 0.83)
    alpha = mask_alpha(mask, 8.0)
    distance = distance_transform_edt(mask)
    groove = smoothstep(0.0, 18.0, distance)
    field = (-0.18 - groove * 0.55) * alpha
    return gaussian_filter(field, 0.75), alpha


def floor_puddle(size: int):
    xx, yy = fixture_grid(size)
    radial = np.sqrt((xx / 0.57) ** 2 + ((yy + 0.04) / 0.40) ** 2)
    wobble = periodic_noise(size, 6801, ((2, 0.6), (5, 0.4))) * 0.15
    mask = radial + wobble < 1.0
    alpha = mask_alpha(mask, 15.0)
    distance = distance_transform_edt(mask)
    basin = smoothstep(0.0, 52.0, distance)
    rim = np.exp(-((radial - 0.91) / 0.08) ** 2)
    field = (-0.48 * basin + 0.08 * rim) * alpha
    return gaussian_filter(field, 1.1), alpha


def floor_socket(size: int):
    xx, yy = fixture_grid(size)
    radial = np.sqrt(((xx + 0.06) / 0.46) ** 2 + ((yy - 0.03) / 0.43) ** 2)
    wobble = periodic_noise(size, 6901, ((2, 0.7), (7, 0.3))) * 0.18
    mask = radial + wobble < 1.0
    alpha = mask_alpha(mask, 12.0)
    distance = distance_transform_edt(mask)
    pit = smoothstep(0.0, 42.0, distance)
    rim = np.exp(-((radial - 0.86) / 0.11) ** 2)
    field = (-0.72 * pit + 0.22 * rim) * alpha
    # A few surviving slab shoulders interrupt the crater without becoming
    # repeated pebble noise.
    for cx, cy, radius, lift in [(-0.25, -0.11, 0.11, 0.22),
                                 (0.20, 0.17, 0.13, 0.18),
                                 (0.16, -0.22, 0.09, 0.15)]:
        chunk = ((xx - cx) ** 2 + (yy - cy) ** 2) < radius ** 2
        field[chunk & mask] += lift * alpha[chunk & mask]
    return gaussian_filter(field, 0.9), alpha


def floor_inlay(size: int):
    xx, yy = fixture_grid(size)
    radius = np.sqrt(xx * xx + yy * yy)
    ring = np.abs(radius - 0.43) < 0.035
    inner_ring = np.abs(radius - 0.22) < 0.026
    spokes = np.minimum(np.abs(xx), np.abs(yy)) < 0.024
    diagonals = np.minimum(np.abs(xx - yy), np.abs(xx + yy)) < 0.028
    mask = (ring | inner_ring | spokes | diagonals) & (radius < 0.50)
    alpha = mask_alpha(mask, 5.0)
    distance = distance_transform_edt(mask)
    field = (0.10 + smoothstep(0.0, 9.0, distance) * 0.34) * alpha
    return gaussian_filter(field, 0.45), alpha


def ceiling_fissure(size: int):
    xx, yy = fixture_grid(size)
    main = yy - (0.16 * np.sin(xx * 5.0) - 0.08 * np.sin(xx * 11.0))
    branch_a = yy - (0.36 + 1.35 * (xx + 0.18))
    branch_b = yy - (-0.30 - 1.1 * (xx - 0.22))
    mask = ((np.abs(main) < 0.045) |
            ((np.abs(branch_a) < 0.035) & (xx < -0.04)) |
            ((np.abs(branch_b) < 0.032) & (xx > 0.05)))
    mask &= (np.abs(xx) < 0.72) & (np.abs(yy) < 0.68)
    alpha = mask_alpha(mask, 7.0)
    distance = distance_transform_edt(mask)
    field = (-0.16 - smoothstep(0.0, 15.0, distance) * 0.58) * alpha
    return gaussian_filter(field, 0.7), alpha


def ceiling_boss(size: int):
    xx, yy = fixture_grid(size)
    discs = np.zeros((size, size), dtype=bool)
    lifts = np.zeros((size, size), dtype=np.float64)
    for cx, cy, radius, lift in [(-0.20, -0.10, 0.19, 0.62),
                                 (0.10, -0.18, 0.24, 0.78),
                                 (0.24, 0.13, 0.17, 0.55),
                                 (-0.08, 0.20, 0.15, 0.48)]:
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        disc = d < radius
        discs |= disc
        lifts = np.maximum(lifts, np.clip(1.0 - d / radius, 0.0, 1.0) * lift)
    alpha = mask_alpha(discs, 10.0)
    field = lifts * alpha
    return gaussian_filter(field, 1.0), alpha


SPECS = [
    MapSpec("floor_flagstones_broad_irregular", "floor", "baseSurface", "replace", 0.10,
            "Broad irregular fitted flagstones; restrained joints and low-frequency slab variation.", floor_flagstones),
    MapSpec("floor_slabs_varied_restrained", "floor", "baseSurface", "replace", 0.10,
            "Large nonuniform slabs with restrained wear; avoids the failed small-cobble repetition.", floor_slabs),
    MapSpec("wall_broad_ashlar_courses", "wall", "baseSurface", "replace", 0.08,
            "Broad masonry courses with resolvable mortar and no scene-like erosion language.", wall_ashlar),
    MapSpec("wall_limewash_broad_undulation", "wall", "baseSurface", "replace", 0.055,
            "Subtle limewash undulation and broad plaster loss, kept at material scale.", wall_limewash),
    MapSpec("ceiling_shallow_cross_ribs", "ceiling", "baseSurface", "replace", 0.09,
            "Shallow broad crossing ribs over quiet ceiling bays.", ceiling_ribs),
    MapSpec("ceiling_wide_coffers", "ceiling", "baseSurface", "replace", 0.085,
            "Two-by-two wide coffers with shallow recesses and broad rims.", ceiling_coffers),
    MapSpec("fixture_wall_votive_relief", "wall", "surfaceFixture", "add", 0.055,
            "Localized votive relief; transparent height alpha outside the carved footprint.", wall_votive_relief),
    MapSpec("fixture_wall_reliquary_niche", "wall", "surfaceFixture", "replace", 0.14,
            "Arched reliquary niche; alpha selects where base relief is replaced by the cavity.", wall_niche),
    MapSpec("fixture_wall_breach_socket", "wall", "surfaceFixture", "replace", 0.18,
            "Irregular deep wall socket with broken rim; remains safely shallower than half a cell.", wall_breach),
    MapSpec("fixture_wall_drain_runnel", "wall", "surfaceFixture", "replace", 0.095,
            "Localized branching drain runnel cut into masonry.", wall_runnel),
    MapSpec("fixture_floor_shallow_puddle", "floor", "surfaceFixture", "replace", 0.045,
            "Shallow irregular puddle basin with soft merge and a very low rim.", floor_puddle),
    MapSpec("fixture_floor_collapsed_socket", "floor", "surfaceFixture", "replace", 0.11,
            "Localized collapsed floor socket with a few broad surviving slab shoulders.", floor_socket),
    MapSpec("fixture_floor_bronze_rite_inlay", "floor", "surfaceFixture", "add", 0.025,
            "Thin ritual bronze inlay; geometry alpha follows only the metal lines.", floor_inlay),
    MapSpec("fixture_ceiling_root_fissure", "ceiling", "surfaceFixture", "replace", 0.06,
            "Localized branching ceiling fissure; transparent outside its crack network.", ceiling_fissure),
    MapSpec("fixture_ceiling_drip_boss", "ceiling", "surfaceFixture", "add", 0.085,
            "Clustered mineral drip boss with a soft transparent merge.", ceiling_boss),
]


def edge_error(array: np.ndarray, axes: str) -> dict[str, float]:
    result = {}
    if "x" in axes:
        result["x"] = float(np.max(np.abs(array[:, 0] - array[:, -1])))
    if "y" in axes:
        result["y"] = float(np.max(np.abs(array[0, :] - array[-1, :])))
    return result


def preview(image: Image.Image, title: str, width: int = 256) -> Image.Image:
    source = np.asarray(image.convert("RGBA"))
    alpha = source[..., 3:4].astype(np.float64) / 255.0
    grey = source[..., :3].astype(np.float64)
    checker = np.indices(source.shape[:2]).sum(axis=0) // 24 % 2
    checker = np.where(checker[..., None] == 0, 44, 72).astype(np.float64)
    composite = grey * alpha + checker * (1.0 - alpha)
    picture = Image.fromarray(np.clip(composite, 0, 255).astype(np.uint8), mode="RGB")
    picture = picture.resize((width, width), Image.Resampling.NEAREST)
    card = Image.new("RGB", (width, width + 38), (22, 22, 24))
    card.paste(picture, (0, 0))
    draw = ImageDraw.Draw(card)
    font = ImageFont.load_default()
    draw.text((7, width + 7), title, fill=(230, 230, 232), font=font)
    return card


def build(check_only: bool = False) -> dict:
    HEIGHT_DIR.mkdir(parents=True, exist_ok=True)
    records = []
    cards = []
    failures = []

    for spec in SPECS:
        signed, alpha = spec.builder(SIZE)
        signed = np.clip(signed, -1.0, 1.0)
        alpha = np.clip(alpha, 0.0, 1.0)
        if spec.role == "baseSurface":
            alpha[:] = 1.0
            signed = force_wrap(signed, spec.tile_axes)
        else:
            # Geometric influence must be exactly absent at wrapping borders.
            border = 18
            fade_x = np.minimum(np.arange(SIZE), np.arange(SIZE)[::-1])
            alpha *= smoothstep(0.0, border, fade_x)[None, :]
            if "y" in spec.tile_axes:
                fade_y = np.minimum(np.arange(SIZE), np.arange(SIZE)[::-1])
                alpha *= smoothstep(0.0, border, fade_y)[:, None]
            signed *= alpha
            signed[alpha <= 1e-8] = 0.0

        path = HEIGHT_DIR / f"{spec.name}.png"
        if not check_only:
            write_height(path, signed, alpha)

        contribution = signed * alpha
        wrap = edge_error(contribution, spec.tile_axes)
        alpha_wrap = edge_error(alpha, spec.tile_axes)
        coverage = float(np.mean(alpha > 0.001))
        if max([*wrap.values(), *alpha_wrap.values()], default=0.0) > 1e-6:
            failures.append(f"{spec.name}: active border mismatch")
        if spec.role == "baseSurface" and not np.allclose(alpha, 1.0):
            failures.append(f"{spec.name}: base alpha is not opaque")
        if spec.role == "surfaceFixture":
            if not (np.any(alpha <= 1e-8) and np.any(alpha >= 0.99)):
                failures.append(f"{spec.name}: fixture alpha lacks ignore/opaque regions")

        record = {
            "preset": spec.name,
            "surface": spec.surface,
            "role": spec.role,
            "heightOperation": spec.operation,
            "recommendedHeightScale": spec.scale,
            "path": path.relative_to(ROOT).as_posix(),
            "size": SIZE,
            "tileAxes": spec.tile_axes,
            "neutral": NEUTRAL,
            "alphaSemantic": ("opaque base coverage" if spec.role == "baseSurface"
                              else "geometric influence; 0 ignores base, 1 merges/replaces according to heightOperation"),
            "signedMin": round(float(signed.min()), 5),
            "signedMax": round(float(signed.max()), 5),
            "alphaCoverage": round(coverage, 5),
            "wrapError": {key: round(value, 8) for key, value in wrap.items()},
            "alphaWrapError": {key: round(value, 8) for key, value in alpha_wrap.items()},
            "wrapOk": True,
            "description": spec.description,
        }
        records.append(record)

        if not check_only:
            cards.append(preview(Image.open(path), spec.name))

    manifest = {
        "manifestKind": "authored_height_batch",
        "manifestVersion": 1,
        "batchId": "first_stratum_surface_fixture_20260806",
        "source": "tools/asset-gen/build_surface_fixture_batch_20260806.py",
        "method": "deterministic analytic fields, periodic Voronoi, distance-transform fixture masks",
        "convention": "RGBA grayscale; 128 neutral; alpha is geometric influence",
        "maps": records,
    }

    if failures:
        raise SystemExit("height batch validation failed:\n  " + "\n  ".join(failures))

    if not check_only:
        MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        columns = 4
        card_w, card_h = cards[0].size
        rows = math.ceil(len(cards) / columns)
        sheet = Image.new("RGB", (columns * card_w, rows * card_h), (14, 14, 16))
        for index, card in enumerate(cards):
            sheet.paste(card, ((index % columns) * card_w, (index // columns) * card_h))
        sheet.save(CONTACT_PATH, optimize=True)
        print(BATCH_ROOT.relative_to(ROOT).as_posix())
        print(f"  {len(records)} authored maps")
        print(f"  {sum(r['role'] == 'surfaceFixture' for r in records)} alpha-masked fixtures")
        print(f"  contact: {CONTACT_PATH.relative_to(ROOT).as_posix()}")
    else:
        print(f"validated {len(records)} map recipes")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate recipes without writing files")
    args = parser.parse_args()
    build(check_only=args.check)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
