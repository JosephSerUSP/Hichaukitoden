#!/usr/bin/env python3
"""Build the owner-review follow-up geometry for the 2026-08-06 surface batch.

This is deliberately a new batch root: the rated maps remain immutable evidence.
Only maps whose owner notes called for geometry or scale changes are regenerated.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from scipy.ndimage import gaussian_filter

import build_surface_fixture_batch_20260806 as base

ROOT = Path(__file__).resolve().parents[2]
BATCH_ROOT = ROOT / "assets" / "geometry" / "3_authored_surface_maps" / "first_stratum_20260807_followup"


def floor_slabs_denser(size: int):
    # Owner liked the language but asked for a denser/smaller scale. 4x5 keeps
    # them broad enough to read at 64px while adding 67% more cells than 3x4.
    _, boundary, cell = base.toroidal_voronoi(size, 7201, 4, 5, x_scale=0.86, y_scale=1.14)
    grain = base.periodic_noise(size, 7202, ((2, 0.62), (7, 0.25), (14, 0.13)))
    joint = 1.0 - base.smoothstep(0.009, 0.034, boundary)
    broad_set = gaussian_filter(cell, 4.0, mode="wrap")
    field = 0.14 + broad_set * 0.14 + grain * 0.05 - joint * 0.44
    return base.force_wrap(gaussian_filter(field, 1.05, mode="wrap"), "xy"), np.ones_like(field)


def wall_ashlar_irregular(size: int):
    """Five gently warped courses with nonuniform, staggered block widths."""
    rng = np.random.default_rng(7301)
    coordinate = np.linspace(0.0, 1.0, size, endpoint=True)
    xx, yy = np.meshgrid(coordinate, coordinate)
    edges = np.asarray([0.0, 0.17, 0.38, 0.57, 0.79, 1.0])
    internal_curves = []
    for index, edge in enumerate(edges):
        if index in {0, len(edges) - 1}:
            internal_curves.append(np.full_like(xx, edge))
        else:
            phase = rng.uniform(0.0, math.tau)
            internal_curves.append(edge + 0.006 * np.sin(math.tau * (xx * (index % 2 + 1)) + phase))
    horizontal_distance = np.min(
        np.stack([np.abs(yy - curve) for curve in internal_curves], axis=0), axis=0)
    field = np.full((size, size), 0.15, dtype=np.float64)
    field -= (1.0 - base.smoothstep(0.010, 0.046, horizontal_distance)) * 0.40

    block_edges = [
        [0.00, 0.28, 0.63, 1.00],
        [0.00, 0.19, 0.48, 0.76, 1.00],
        [0.00, 0.34, 0.68, 1.00],
        [0.00, 0.22, 0.54, 0.81, 1.00],
        [0.00, 0.30, 0.59, 1.00],
    ]
    offsets = [0.00, 0.13, 0.31, 0.06, 0.21]
    course = np.clip(np.searchsorted(edges, yy, side="right") - 1, 0, 4)
    for row, boundaries in enumerate(block_edges):
        row_mask = course == row
        local_x = (xx + offsets[row]) % 1.0
        y_mid = (edges[row] + edges[row + 1]) * 0.5
        wobble = 0.005 * np.sin(math.tau * ((yy - y_mid) * 5.0 + row * 0.17))
        distances = []
        for boundary in boundaries[:-1]:
            delta = np.abs(local_x - ((boundary + wobble) % 1.0))
            distances.append(np.minimum(delta, 1.0 - delta))
        vertical_distance = np.min(np.stack(distances, axis=0), axis=0)
        joint = 1.0 - base.smoothstep(0.009, 0.050, vertical_distance)
        field[row_mask] -= joint[row_mask] * 0.34

        shifted = (local_x - wobble) % 1.0
        indices = np.searchsorted(np.asarray(boundaries), shifted, side="right") - 1
        indices = np.clip(indices, 0, len(boundaries) - 2)
        values = rng.uniform(-0.070, 0.085, len(boundaries) - 1)
        field[row_mask] += values[indices[row_mask]]

    field += base.periodic_noise(size, 7302, ((2, 0.72), (8, 0.28))) * 0.042
    field = gaussian_filter(field, 0.95, mode=("nearest", "wrap"))
    return base.force_wrap(field, "x"), np.ones_like(field)


def votive_soft(size: int):
    signed, alpha = base.wall_votive_relief(size)
    return signed * 0.64, alpha


def breach_restrained(size: int):
    signed, alpha = base.wall_breach(size)
    # Preserve the cavity sign while making the broken rim less cliff-like.
    signed = np.where(signed > 0.0, signed * 0.58, signed * 0.78)
    return signed, alpha


def bronze_inlay_soft(size: int):
    signed, alpha = base.floor_inlay(size)
    return signed * 0.62, alpha


def mineral_fissure(size: int):
    xx, yy = base.fixture_grid(size)
    main = yy - (0.11 * np.sin(xx * 5.4) - 0.045 * np.sin(xx * 12.0))
    branch_a = yy - (0.26 + 1.30 * (xx + 0.17))
    branch_b = yy - (-0.24 - 1.05 * (xx - 0.20))
    mask = ((np.abs(main) < 0.027) |
            ((np.abs(branch_a) < 0.022) & (xx < -0.05)) |
            ((np.abs(branch_b) < 0.020) & (xx > 0.06)))
    mask &= (np.abs(xx) < 0.70) & (np.abs(yy) < 0.60)
    alpha = base.mask_alpha(mask, 5.0)
    distance = base.distance_transform_edt(mask)
    field = (-0.12 - base.smoothstep(0.0, 11.0, distance) * 0.46) * alpha
    return gaussian_filter(field, 0.55), alpha


SPECS = [
    base.MapSpec("floor_slabs_denser", "floor", "baseSurface", "replace", 0.09,
                 "Denser 4x5 slab field derived from the owner-favoured broad slab map.", floor_slabs_denser),
    base.MapSpec("wall_ashlar_irregular_courses", "wall", "baseSurface", "replace", 0.07,
                 "Five irregular staggered ashlar courses with less diagrammatic block spacing.", wall_ashlar_irregular),
    base.MapSpec("fixture_wall_votive_relief_soft", "wall", "surfaceFixture", "add", 0.042,
                 "Owner-favoured votive relief with reduced authored amplitude and review scale.", votive_soft),
    base.MapSpec("fixture_wall_breach_socket_restrained", "wall", "surfaceFixture", "replace", 0.14,
                 "Less cliff-like broken socket; cavity remains signed below neutral.", breach_restrained),
    base.MapSpec("fixture_floor_bronze_rite_inlay_soft", "floor", "surfaceFixture", "add", 0.016,
                 "Thinner bronze inlay with reduced authored amplitude and review scale.", bronze_inlay_soft),
    base.MapSpec("fixture_ceiling_mineral_fissure", "ceiling", "surfaceFixture", "replace", 0.05,
                 "Hairline mineral fracture network, intentionally authored without root imagery.", mineral_fissure),
]


def _assert_signs(manifest: dict) -> None:
    records = {row["preset"]: row for row in manifest["maps"]}
    raised = ["fixture_wall_votive_relief_soft", "fixture_floor_bronze_rite_inlay_soft"]
    recessed = ["fixture_wall_breach_socket_restrained", "fixture_ceiling_mineral_fissure"]
    for name in raised:
        assert records[name]["signedMax"] > 0.0, f"{name} must rise above neutral"
    for name in recessed:
        assert records[name]["signedMin"] < 0.0, f"{name} must cut below neutral"


def build(check_only: bool = False) -> dict:
    base.BATCH_ROOT = BATCH_ROOT
    base.HEIGHT_DIR = BATCH_ROOT / "height"
    base.MANIFEST_PATH = BATCH_ROOT / "manifest.json"
    base.CONTACT_PATH = BATCH_ROOT / "contact-sheet.png"
    base.SPECS = SPECS
    manifest = base.build(check_only=check_only)
    manifest["batchId"] = "first_stratum_surface_fixture_followup_20260807"
    manifest["source"] = "tools/asset-gen/build_surface_fixture_followup_20260807.py"
    manifest["reviewBasis"] = "tools/asset-gen/reviews/ratings.json at ed0de35e570260b9355848b73131a0373ccfa42f"
    _assert_signs(manifest)
    if not check_only:
        base.MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    build(check_only=args.check)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
