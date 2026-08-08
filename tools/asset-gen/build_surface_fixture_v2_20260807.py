#!/usr/bin/env python3
"""Corrected fixture geometry for the 2026-08-07 owner review.

The rated 08-06 and follow-up roots stay untouched as evidence. This root fixes
the three alpha defects the owner identified (see lib/fixture_alpha.py for why
each one mattered) and, for the first time, also writes a CONDITIONING map per
fixture: the fixture merged over the base surface it will actually sit in, which
is what Stable Diffusion is shown instead of a shape floating on transparency.

Each fixture therefore emits two files:

  height/<name>.png         authoritative -- signed relief + alpha the ENGINE uses
  conditioning/<name>.png   opaque merged relief the MODEL is conditioned on

Nothing downstream may confuse the two. The engine must never receive the
conditioning map (it has no alpha, so it would claim every texel), and the model
must never be conditioned on the authoritative map (transparency is what caused
the regularization in the first place).
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, gaussian_filter

import build_surface_fixture_batch_20260806 as base
from lib import fixture_alpha as fa

ROOT = Path(__file__).resolve().parents[2]
BATCH_ROOT = ROOT / "assets" / "geometry" / "3_authored_surface_maps" / "first_stratum_20260807_v2"
CONDITIONING_DIR = BATCH_ROOT / "conditioning"

SIZE = base.SIZE

# Which base surface each fixture is conditioned against. A fixture merged over
# the wrong material teaches the model the wrong surround, so this is data, not
# a default.
CONDITIONING_BASE = {
    "fixture_floor_bronze_rite_inlay_plate": base.floor_flagstones,
    "fixture_ceiling_mineral_fissure_thick": base.ceiling_coffers,
    "fixture_wall_breach_socket_hugged": base.wall_ashlar,
    "fixture_floor_collapsed_socket_hugged": base.floor_flagstones,
}


def bronze_inlay_plate(size: int):
    """The inlay as a plate that HAS a pattern, not a pattern in mid-air."""
    xx, yy = base.fixture_grid(size)
    radius = np.sqrt(xx * xx + yy * yy)
    ring = np.abs(radius - 0.43) < 0.035
    inner_ring = np.abs(radius - 0.22) < 0.026
    spokes = np.minimum(np.abs(xx), np.abs(yy)) < 0.024
    diagonals = np.minimum(np.abs(xx - yy), np.abs(xx + yy)) < 0.028
    pattern = (ring | inner_ring | spokes | diagonals) & (radius < 0.50)
    pattern = fa.enforce_min_thickness(pattern, runtime_texels=1.5)
    # The disc the pattern is cut into. Alpha covers this; height describes the
    # pattern within it, sitting just proud of the surrounding stone.
    plate = radius < 0.47
    alpha = fa.backing_alpha(pattern, plate, feather=9.0)
    distance = distance_transform_edt(pattern)
    relief = base.smoothstep(0.0, 7.0, distance)
    # A shallow seated plate with the metal proud of it: the owner asked for
    # nearly flush, so the plate itself barely rises and only the lines catch.
    field = np.where(plate, 0.05, 0.0) + relief * 0.30
    return gaussian_filter(field * alpha, 0.5), alpha


def mineral_fissure_thick(size: int):
    """The same fracture path, widened until it exists at 64px."""
    xx, yy = base.fixture_grid(size)
    main = yy - (0.11 * np.sin(xx * 5.4) - 0.045 * np.sin(xx * 12.0))
    branch_a = yy - (0.26 + 1.30 * (xx + 0.17))
    branch_b = yy - (-0.24 - 1.05 * (xx - 0.20))
    mask = ((np.abs(main) < 0.027) |
            ((np.abs(branch_a) < 0.022) & (xx < -0.05)) |
            ((np.abs(branch_b) < 0.020) & (xx > 0.06)))
    mask &= (np.abs(xx) < 0.70) & (np.abs(yy) < 0.60)
    # 2.5 runtime texels: enough that the seam reads as a seam after
    # downsampling, still far from a trench.
    mask = fa.enforce_min_thickness(mask, runtime_texels=2.5)
    alpha = base.mask_alpha(mask, 7.0)
    distance = distance_transform_edt(mask)
    field = (-0.10 - base.smoothstep(0.0, 9.0, distance) * 0.40) * alpha
    return gaussian_filter(field, 0.6), alpha


def breach_socket_hugged(size: int):
    """The restrained socket with alpha pulled back onto the cavity itself."""
    signed, _ = base.wall_breach(size)
    signed = np.where(signed > 0.0, signed * 0.58, signed * 0.78)
    alpha = fa.hug_alpha(signed, feather=9.0, deviation=0.02)
    return signed, alpha


def collapsed_socket_hugged(size: int):
    """The pit that stops bulldozing its surround.

    The authored pit was always correct; its mask reached far past the deviation,
    so `replace` flattened the base flagstones across a wide saucer.
    """
    signed, _ = base.floor_socket(size)
    alpha = fa.hug_alpha(signed, feather=10.0, deviation=0.02)
    return signed, alpha


SPECS = [
    base.MapSpec("fixture_floor_bronze_rite_inlay_plate", "floor", "surfaceFixture", "add", 0.020,
                 "Bronze rite inlay seated in a backing plate so the engine receives a "
                 "continuous disc rather than floating lines.", bronze_inlay_plate),
    base.MapSpec("fixture_ceiling_mineral_fissure_thick", "ceiling", "surfaceFixture", "replace", 0.05,
                 "Same fracture path widened to 2.5 runtime texels so it survives the 64px tile.",
                 mineral_fissure_thick),
    base.MapSpec("fixture_wall_breach_socket_hugged", "wall", "surfaceFixture", "replace", 0.14,
                 "Restrained broken socket with alpha hugging the cavity instead of a wide disc.",
                 breach_socket_hugged),
    base.MapSpec("fixture_floor_collapsed_socket_hugged", "floor", "surfaceFixture", "replace", 0.13,
                 "Collapsed floor socket whose influence no longer erases the surrounding slabs.",
                 collapsed_socket_hugged),
]


def write_conditioning(manifest: dict) -> list[dict]:
    """Emit the opaque merged map the model is conditioned on."""
    CONDITIONING_DIR.mkdir(parents=True, exist_ok=True)
    rows = []
    for record in manifest["maps"]:
        name = record["preset"]
        builder = CONDITIONING_BASE.get(name)
        if builder is None:
            raise SystemExit(f"no conditioning base declared for {name}")
        authored = Image.open(ROOT / record["path"]).convert("RGBA")
        data = np.asarray(authored, dtype=np.float64)
        signed = (data[..., 0] - base.NEUTRAL) / 127.0
        alpha = data[..., 3] / 255.0
        base_signed, _ = builder(SIZE)
        base_signed = base.force_wrap(np.clip(base_signed, -1.0, 1.0),
                                      "x" if record["surface"] == "wall" else "xy")
        merged = fa.conditioning_image(signed, alpha, base_signed,
                                       record["heightOperation"])
        grey = np.clip(np.rint(base.NEUTRAL + merged * 127.0), 0, 255).astype(np.uint8)
        out = CONDITIONING_DIR / f"{name}.png"
        Image.fromarray(np.dstack([grey, grey, grey]), mode="RGB").save(out, optimize=True)
        record["conditioningPath"] = out.relative_to(ROOT).as_posix()
        record["conditioningBase"] = builder.__name__
        record["runtimeTexelCoverage"] = fa.runtime_texel_coverage(alpha)
        rows.append(record)
    return rows


def _assert_rules(manifest: dict) -> None:
    """The three defects, as checks that fail loudly rather than as intentions."""
    records = {row["preset"]: row for row in manifest["maps"]}
    for name, row in records.items():
        assert row.get("conditioningPath"), f"{name} has no conditioning map"
        # 1. Survives the runtime tile. 52/4096 was the failure being fixed.
        coverage = row["runtimeTexelCoverage"]
        assert coverage >= 150, f"{name} reaches only {coverage} runtime texels"
    plate = records["fixture_floor_bronze_rite_inlay_plate"]
    # 2. The plate is a continuous region, not a stencil of lines.
    assert plate["alphaCoverage"] > 0.14, (
        f"inlay alpha covers only {plate['alphaCoverage']:.3f}; the backing plate is missing")
    # 3. Hugged fixtures must not claim much more than they deform.
    for name in ("fixture_wall_breach_socket_hugged", "fixture_floor_collapsed_socket_hugged"):
        row = records[name]
        assert row["signedMin"] < -0.05, f"{name} must still cut below neutral"
        assert row["alphaCoverage"] < 0.22, (
            f"{name} still claims {row['alphaCoverage']:.3f} of the tile; alpha is not hugging")


def build(check_only: bool = False) -> dict:
    base.BATCH_ROOT = BATCH_ROOT
    base.HEIGHT_DIR = BATCH_ROOT / "height"
    base.MANIFEST_PATH = BATCH_ROOT / "manifest.json"
    base.CONTACT_PATH = BATCH_ROOT / "contact-sheet.png"
    base.SPECS = SPECS
    manifest = base.build(check_only=check_only)
    manifest["batchId"] = "first_stratum_surface_fixture_v2_20260807"
    manifest["source"] = "tools/asset-gen/build_surface_fixture_v2_20260807.py"
    manifest["alphaRules"] = "tools/asset-gen/lib/fixture_alpha.py"
    if not check_only:
        write_conditioning(manifest)
        _assert_rules(manifest)
        base.MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    manifest = build(check_only=args.check)
    for row in manifest["maps"]:
        print(f"  {row['preset']:<44} alpha {row['alphaCoverage']:.3f} "
              f"texels {row.get('runtimeTexelCoverage', '-')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
