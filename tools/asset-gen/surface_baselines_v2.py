#!/usr/bin/env python3
"""Generate deterministic Second Rite V2 surface baselines.

The canonical source is a fixed-point scalar field produced directly by Python.
Blender may consume the field for inspection meshes and renders, but Blender's
BVH, modifiers, or ray-casting order never determine canonical pixels.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "assets" / "geometry" / "2_procedural_surface_baselines"
DEFAULT_SIZE = 128
DEFAULT_RANGE_CELLS = 0.25
FIELD_MIN = -32767
FIELD_MAX = 32767
METRIC_NEUTRAL = 32768
GUIDE_NEUTRAL = 128
GUIDE_CONTRAST = 112
SCHEMA_VERSION = 1
GENERATOR_VERSION = 1


@dataclass(frozen=True)
class Recipe:
    asset_id: str
    display_name: str
    surface: str
    tile_axes: str
    seed: int
    material_id: str
    recipe_version: int
    description: str
    build: Callable[[int, int], list[int]]


def clamp(value: int, low: int, high: int) -> int:
    return low if value < low else high if value > high else value


def round_div_signed(numerator: int, denominator: int) -> int:
    if denominator <= 0:
        raise ValueError("denominator must be positive")
    if numerator >= 0:
        return (numerator + denominator // 2) // denominator
    return -((-numerator + denominator // 2) // denominator)


def mix64(value: int) -> int:
    value &= 0xFFFFFFFFFFFFFFFF
    value ^= value >> 30
    value = (value * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
    value ^= value >> 27
    value = (value * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
    value ^= value >> 31
    return value & 0xFFFFFFFFFFFFFFFF


def hash_u32(seed: int, x: int, y: int, channel: int = 0) -> int:
    value = (
        (seed & 0xFFFFFFFFFFFFFFFF)
        ^ ((x & 0xFFFFFFFF) * 0x9E3779B185EBCA87)
        ^ ((y & 0xFFFFFFFF) * 0xC2B2AE3D27D4EB4F)
        ^ ((channel & 0xFFFFFFFF) * 0x165667B19E3779F9)
    )
    return mix64(value) & 0xFFFFFFFF


def hash_signed(seed: int, x: int, y: int, amplitude: int, channel: int = 0) -> int:
    if amplitude < 0:
        raise ValueError("amplitude must be non-negative")
    span = amplitude * 2 + 1
    return int(hash_u32(seed, x, y, channel) % span) - amplitude


def periodic_distance(a: int, b: int, period: int) -> int:
    delta = abs(a - b) % period
    return min(delta, period - delta)


def field_index(size: int, x: int, y: int) -> int:
    return y * size + x


def enforce_tiling(field: list[int], size: int, tile_axes: str) -> None:
    if "x" in tile_axes:
        for y in range(size):
            field[field_index(size, size - 1, y)] = field[field_index(size, 0, y)]
    if "y" in tile_axes:
        for x in range(size):
            field[field_index(size, x, size - 1)] = field[field_index(size, x, 0)]


def _normalized_coordinate(value: int, period: int) -> int:
    return round_div_signed(value * 65536, period)


def _smooth_band(distance: int, width: int, height: int) -> int:
    if distance >= width:
        return 0
    remaining = width - distance
    return (height * remaining * remaining) // (width * width)


def build_wall_ritual_pilasters(size: int, seed: int) -> list[int]:
    period = size - 1
    bay = 65536 // 2
    field = [0] * (size * size)
    for y in range(size):
        v = _normalized_coordinate(y, period)
        for x in range(size):
            u = _normalized_coordinate(x, period) % bay
            center = bay // 2
            edge = min(u, bay - u)
            value = -6400

            # Repeating load-bearing pilasters at bay boundaries.
            pillar_width = 6200
            value += _smooth_band(edge, pillar_width, 12500)
            inner_pillar = abs(edge - 3900)
            value += _smooth_band(inner_pillar, 900, 2600)

            # Recessed central field and a raised inner moulding.
            panel_x = abs(u - center)
            panel_y = abs(v - 39200)
            if panel_x < 11200 and 14500 < v < 59000:
                value -= 1800
                frame_distance = min(11200 - panel_x, v - 14500, 59000 - v)
                if frame_distance < 1700:
                    value += _smooth_band(frame_distance, 1700, 4200)

            # Shallow arch above each panel.
            arch_cy = 22600
            dx = u - center
            dy = v - arch_cy
            radius = math.isqrt(dx * dx + dy * dy)
            if v <= arch_cy + 1200:
                ring = abs(radius - 10400)
                value += _smooth_band(ring, 1450, 5200)

            # Cornice and base course.
            value += _smooth_band(abs(v - 9300), 1800, 4300)
            value += _smooth_band(abs(v - 62000), 2100, 5000)

            # Small deterministic chipping, deliberately subordinate to form.
            chip = hash_signed(seed, x // 4, y // 4, 260, 1)
            field[field_index(size, x, y)] = clamp(value + chip, FIELD_MIN, FIELD_MAX)
    enforce_tiling(field, size, "x")
    return field


def _stone_centres(seed: int, columns: int, rows: int) -> list[tuple[int, int, int, int, int]]:
    centres: list[tuple[int, int, int, int, int]] = []
    for row in range(rows):
        for column in range(columns):
            jitter_x = hash_signed(seed, column, row, 2300, 1)
            jitter_y = hash_signed(seed, column, row, 2100, 2)
            cx = ((column * 65536) // columns + 65536 // (2 * columns) + jitter_x) % 65536
            cy = ((row * 65536) // rows + 65536 // (2 * rows) + jitter_y) % 65536
            rx = 5000 + int(hash_u32(seed, column, row, 3) % 2100)
            ry = 4300 + int(hash_u32(seed, column, row, 4) % 1900)
            height = 2500 + int(hash_u32(seed, column, row, 5) % 4300)
            centres.append((cx, cy, rx, ry, height))
    return centres


def build_floor_broken_flagstones(size: int, seed: int) -> list[int]:
    period = size - 1
    centres = _stone_centres(seed, columns=7, rows=7)
    field = [0] * (size * size)
    for y in range(size):
        v = _normalized_coordinate(y, period) % 65536
        for x in range(size):
            u = _normalized_coordinate(x, period) % 65536
            nearest: tuple[int, int, int, int, int] | None = None
            nearest_score = 1 << 62
            second_score = 1 << 62
            for stone in centres:
                cx, cy, rx, ry, _height = stone
                dx = periodic_distance(u, cx, 65536)
                dy = periodic_distance(v, cy, 65536)
                score = (dx * dx * 65536) // (rx * rx) + (dy * dy * 65536) // (ry * ry)
                if score < nearest_score:
                    second_score = nearest_score
                    nearest_score = score
                    nearest = stone
                elif score < second_score:
                    second_score = score

            assert nearest is not None
            _cx, _cy, _rx, _ry, stone_height = nearest
            boundary_gap = second_score - nearest_score
            if nearest_score >= 76000 or boundary_gap < 11500:
                value = -8600
            else:
                radial = math.isqrt(max(0, nearest_score) << 16)
                crown = max(0, (65536 - radial) * 3000 // 65536)
                value = stone_height + crown
                value += hash_signed(seed, x // 3, y // 3, 420, 9)
                if hash_u32(seed, x // 5, y // 5, 10) % 31 == 0:
                    value -= 1200
            field[field_index(size, x, y)] = clamp(value, FIELD_MIN, FIELD_MAX)
    enforce_tiling(field, size, "xy")
    return field


def build_ceiling_shallow_coffers(size: int, seed: int) -> list[int]:
    period = size - 1
    cells = 4
    cell = 65536 // cells
    field = [0] * (size * size)
    for y in range(size):
        v = _normalized_coordinate(y, period) % 65536
        local_y = v % cell
        for x in range(size):
            u = _normalized_coordinate(x, period) % 65536
            local_x = u % cell
            edge = min(local_x, cell - local_x, local_y, cell - local_y)
            value = -7200
            if edge < 2400:
                value = 8200 - (edge * 3000 // 2400)
            elif edge < 4700:
                value = 2600 - ((edge - 2400) * 7200 // 2300)

            cx = local_x - cell // 2
            cy = local_y - cell // 2
            radial = math.isqrt(cx * cx + cy * cy)
            if radial < 2600:
                value += (2600 - radial) * 4400 // 2600
            elif abs(radial - 5200) < 950:
                value += _smooth_band(abs(radial - 5200), 950, 1800)

            value += hash_signed(seed, x // 8, y // 8, 100, 1)
            field[field_index(size, x, y)] = clamp(value, FIELD_MIN, FIELD_MAX)
    enforce_tiling(field, size, "xy")
    return field


def _boulder_layout(seed: int, rows: int = 6) -> list[tuple[int, int, int, int, int]]:
    stones: list[tuple[int, int, int, int, int]] = []
    for row in range(rows):
        count = 5 + (row % 2)
        spacing = 65536 // count
        row_height = 65536 // rows
        offset = spacing // 2 if row % 2 else 0
        for column in range(count):
            cx = (column * spacing + spacing // 2 + offset + hash_signed(seed, column, row, 1800, 1)) % 65536
            cy = clamp(row * row_height + row_height // 2 + hash_signed(seed, column, row, 1300, 2), 0, 65535)
            rx = spacing * (39 + int(hash_u32(seed, column, row, 3) % 9)) // 100
            ry = row_height * (38 + int(hash_u32(seed, column, row, 4) % 11)) // 100
            base = 1800 + int(hash_u32(seed, column, row, 5) % 3600)
            stones.append((cx, cy, max(rx, 1), max(ry, 1), base))
    return stones


def build_wall_ossuary_boulders(size: int, seed: int) -> list[int]:
    period = size - 1
    stones = _boulder_layout(seed)
    field = [-9800] * (size * size)
    for y in range(size):
        v = _normalized_coordinate(y, period)
        for x in range(size):
            u = _normalized_coordinate(x, period) % 65536
            best = -9800
            for cx, cy, rx, ry, base in stones:
                dx = periodic_distance(u, cx, 65536)
                dy = abs(v - cy)
                score = (dx * dx * 65536) // (rx * rx) + (dy * dy * 65536) // (ry * ry)
                if score >= 65536:
                    continue
                radial = math.isqrt(score << 16)
                crown = (65536 - radial) * 8200 // 65536
                chipped = hash_signed(seed, x // 3, y // 3, 680, 11)
                fissure = 0
                if hash_u32(seed, x // 6, y // 6, 12) % 37 == 0:
                    fissure = -1500
                candidate = base + crown + chipped + fissure
                if candidate > best:
                    best = candidate
            field[field_index(size, x, y)] = clamp(best, FIELD_MIN, FIELD_MAX)
    enforce_tiling(field, size, "x")
    return field


RECIPES: dict[str, Recipe] = {
    recipe.asset_id: recipe
    for recipe in (
        Recipe(
            asset_id="wall_ritual_pilasters",
            display_name="Ritual Pilaster Wall",
            surface="wall",
            tile_axes="x",
            seed=0x5ECA1001,
            material_id="old_limestone",
            recipe_version=1,
            description="Repeated pilaster bays, recessed ritual panels, arch moulding, cornice, and base course.",
            build=build_wall_ritual_pilasters,
        ),
        Recipe(
            asset_id="floor_broken_flagstones",
            display_name="Broken Flagstone Floor",
            surface="floor",
            tile_axes="xy",
            seed=0x5ECA2002,
            material_id="rough_limestone",
            recipe_version=1,
            description="Periodic irregular flagstone cells with mortar joints, crowns, chips, and varied course height.",
            build=build_floor_broken_flagstones,
        ),
        Recipe(
            asset_id="ceiling_shallow_coffers",
            display_name="Shallow Coffered Ceiling",
            surface="ceiling",
            tile_axes="xy",
            seed=0x5ECA3003,
            material_id="old_limestone",
            recipe_version=1,
            description="Four-by-four coffer grid with raised ribs, bevelled recesses, and restrained central bosses.",
            build=build_ceiling_shallow_coffers,
        ),
        Recipe(
            asset_id="wall_ossuary_boulders",
            display_name="Ossuary Boulder Wall",
            surface="wall",
            tile_axes="x",
            seed=0x5ECA4004,
            material_id="rough_limestone",
            recipe_version=1,
            description="Deterministic courses of irregular elliptical stones with deep mortar, chipped crowns, and fissures.",
            build=build_wall_ossuary_boulders,
        ),
    )
}


def validate_field(field: list[int], size: int, tile_axes: str) -> None:
    if len(field) != size * size:
        raise ValueError(f"field has {len(field)} samples; expected {size * size}")
    if any(value < FIELD_MIN or value > FIELD_MAX for value in field):
        raise ValueError("field contains values outside signed Q15 range")
    if "x" in tile_axes:
        for y in range(size):
            if field[field_index(size, 0, y)] != field[field_index(size, size - 1, y)]:
                raise ValueError(f"field is not x-periodic at row {y}")
    if "y" in tile_axes:
        for x in range(size):
            if field[field_index(size, x, 0)] != field[field_index(size, x, size - 1)]:
                raise ValueError(f"field is not y-periodic at column {x}")


def field_bytes(field: Iterable[int]) -> bytes:
    output = bytearray()
    for value in field:
        encoded = value & 0xFFFF
        output.append(encoded & 0xFF)
        output.append((encoded >> 8) & 0xFF)
    return bytes(output)


def metric_values(field: Iterable[int]) -> list[int]:
    return [clamp(METRIC_NEUTRAL + value, 1, 65535) for value in field]


def guide_values(field: list[int]) -> tuple[list[int], int, int]:
    ordered = sorted(field)
    median = ordered[len(ordered) // 2]
    deviations = sorted(abs(value - median) for value in field)
    percentile_index = max(0, math.ceil(len(deviations) * 0.99) - 1)
    scale = max(1, deviations[percentile_index])
    guide = [
        clamp(GUIDE_NEUTRAL + round_div_signed((value - median) * GUIDE_CONTRAST, scale),
              GUIDE_NEUTRAL - GUIDE_CONTRAST,
              GUIDE_NEUTRAL + GUIDE_CONTRAST)
        for value in field
    ]
    return guide, median, scale


def png_bytes(values: list[int], size: int, mode: str) -> bytes:
    from io import BytesIO
    from PIL import Image

    image = Image.new(mode, (size, size))
    image.putdata(values)
    stream = BytesIO()
    image.save(stream, format="PNG", compress_level=9, optimize=False)
    return stream.getvalue()


def source_hash() -> str:
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build_field(asset_id: str, size: int = DEFAULT_SIZE) -> tuple[Recipe, list[int]]:
    if size < 17:
        raise ValueError("size must be at least 17")
    recipe = RECIPES[asset_id]
    field = recipe.build(size, recipe.seed)
    validate_field(field, size, recipe.tile_axes)
    return recipe, field


def baseline_artifacts(asset_id: str, size: int = DEFAULT_SIZE) -> tuple[dict[str, bytes], dict]:
    recipe, field = build_field(asset_id, size)
    raw = field_bytes(field)
    metric = png_bytes(metric_values(field), size, "I;16")
    guide_data, guide_median, guide_scale = guide_values(field)
    guide = png_bytes(guide_data, size, "L")
    generator_hash = source_hash()
    range_cells = DEFAULT_RANGE_CELLS
    relief_min = min(field) / 32767.0 * range_cells
    relief_max = max(field) / 32767.0 * range_cells
    metadata = {
        "schemaVersion": SCHEMA_VERSION,
        "generatorVersion": GENERATOR_VERSION,
        "assetId": recipe.asset_id,
        "displayName": recipe.display_name,
        "description": recipe.description,
        "recipeVersion": recipe.recipe_version,
        "seed": recipe.seed,
        "representation": "plane",
        "role": "surface_material",
        "authoringSpace": "depth_tile",
        "placementFrame": "surface_domain",
        "surface": recipe.surface,
        "tileAxes": recipe.tile_axes,
        "materialId": recipe.material_id,
        "size": size,
        "rangeCells": range_cells,
        "metricEncoding": {
            "file": "height_metric.png",
            "mode": "I;16",
            "neutral": METRIC_NEUTRAL,
            "formula": "round(32768 + clamp(reliefCells / rangeCells, -1, 1) * 32767)",
        },
        "guideEncoding": {
            "file": "depth_guide.png",
            "mode": "L",
            "neutral": GUIDE_NEUTRAL,
            "contrast": GUIDE_CONTRAST,
            "medianQ15": guide_median,
            "p99AbsoluteDeviationQ15": guide_scale,
        },
        "reliefCells": {"min": round(relief_min, 8), "max": round(relief_max, 8)},
        "hashes": {
            "fieldQ15LeSha256": sha256(raw),
            "heightMetricPngSha256": sha256(metric),
            "depthGuidePngSha256": sha256(guide),
            "generatorSourceSha256": generator_hash,
        },
        "canonicalFiles": ["height_metric.png", "depth_guide.png", "baseline.json"],
        "derivatives": {
            "blenderPreview": "generated by tools/asset-gen/blender/build_surface_v2_preview.py",
            "canonical": False,
        },
    }
    metadata_bytes = (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode("utf-8")
    return {
        "height_metric.png": metric,
        "depth_guide.png": guide,
        "baseline.json": metadata_bytes,
    }, metadata


def write_baselines(out_dir: Path, asset_ids: Iterable[str], size: int, runs: int) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for asset_id in asset_ids:
        first_artifacts: dict[str, bytes] | None = None
        first_metadata: dict | None = None
        for run_index in range(runs):
            artifacts, metadata = baseline_artifacts(asset_id, size)
            if first_artifacts is None:
                first_artifacts = artifacts
                first_metadata = metadata
            elif artifacts != first_artifacts:
                raise RuntimeError(f"determinism failure for {asset_id} on run {run_index + 1}")
        assert first_artifacts is not None and first_metadata is not None
        target = out_dir / asset_id
        target.mkdir(parents=True, exist_ok=True)
        for name, data in first_artifacts.items():
            (target / name).write_bytes(data)
        entries.append({
            "assetId": asset_id,
            "path": asset_id,
            "fieldQ15LeSha256": first_metadata["hashes"]["fieldQ15LeSha256"],
            "heightMetricPngSha256": first_metadata["hashes"]["heightMetricPngSha256"],
            "depthGuidePngSha256": first_metadata["hashes"]["depthGuidePngSha256"],
        })
        print(f"{asset_id}: deterministic across {runs} run(s)")
    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "generatorVersion": GENERATOR_VERSION,
        "generatorSourceSha256": source_hash(),
        "size": size,
        "rangeCells": DEFAULT_RANGE_CELLS,
        "baselines": sorted(entries, key=lambda item: item["assetId"]),
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def compare_directories(expected: Path, actual: Path) -> list[str]:
    expected_files = sorted(path.relative_to(expected) for path in expected.rglob("*") if path.is_file())
    actual_files = sorted(path.relative_to(actual) for path in actual.rglob("*") if path.is_file())
    problems: list[str] = []
    if expected_files != actual_files:
        problems.append(f"file set differs: expected={expected_files}, actual={actual_files}")
    for relative in sorted(set(expected_files) & set(actual_files)):
        if (expected / relative).read_bytes() != (actual / relative).read_bytes():
            problems.append(f"content differs: {relative.as_posix()}")
    return problems


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preset", action="append", choices=sorted(RECIPES),
                        help="repeatable; default is all four V2 baselines")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--runs", type=int, default=3,
                        help="generate each baseline repeatedly before writing")
    parser.add_argument("--verify", action="store_true",
                        help="regenerate temporarily and compare byte-for-byte with --out")
    parser.add_argument("--list", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.list:
        for asset_id in sorted(RECIPES):
            print(asset_id)
        return 0
    if args.runs < 2:
        raise SystemExit("--runs must be at least 2")
    asset_ids = args.preset or sorted(RECIPES)
    if args.verify:
        if set(asset_ids) != set(RECIPES):
            raise SystemExit("--verify requires the complete V2 baseline set")
        with tempfile.TemporaryDirectory(prefix="second-rite-surface-v2-") as directory:
            generated = Path(directory)
            write_baselines(generated, asset_ids, args.size, args.runs)
            problems = compare_directories(args.out, generated)
            if problems:
                for problem in problems:
                    print(problem)
                return 1
        print("V2 surface baselines: verified")
        return 0
    write_baselines(args.out, asset_ids, args.size, args.runs)
    print(f"V2 surface baselines written to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
