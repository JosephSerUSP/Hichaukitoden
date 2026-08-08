#!/usr/bin/env python3
"""Fracture as a base-surface variant, not as a fixture.

The 08-07 review settled this. A thin recessed feature cannot win as a fixture:
merged over a finished surface it competes with that surface for the depth
field's dynamic range, and a scratch never beats a coffer. At depth weight 0.76
the model read the seam as a raised ribbon lying on the ceiling; at 0.40 it
followed the dominant signal and the fissure simply vanished. There is no weight
in between that turns it into a cut, because the ambiguity is not about strength.

A crack is a property of the material, so it belongs in the material: these are
whole opaque surfaces generated WITH the fracture already in them, which is also
the shape every 5-and-6 rated map in this project has had.

The one real constraint a fixture did not have: a base surface is instanced in
every cell, so the fracture network has to TILE. Every crack here is a level set
of a periodic field, so it wraps by construction rather than by correction.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from scipy.ndimage import binary_dilation, distance_transform_edt, gaussian_filter

import build_surface_fixture_batch_20260806 as base
from lib import fixture_alpha as fa

ROOT = Path(__file__).resolve().parents[2]
BATCH_ROOT = ROOT / "assets" / "geometry" / "3_authored_surface_maps" / "first_stratum_20260807_fractured"

SIZE = base.SIZE


def fracture_mask(size: int, seed: int, cells: int = 5, width: float = 0.010,
                  fragment_share: float | None = None,
                  runtime_texels: float = 2.0) -> np.ndarray:
    """A tiling crack network built from toroidal Voronoi edges.

    The first attempt took the level set of smooth periodic noise. It tiled
    perfectly and looked completely wrong: a level set of a smooth field is a set
    of smooth closed contours, so the result read as worm trails, not fractures.
    Stone does not crack in sinuous curves -- it cracks in straight runs that
    meet at sharp junctions and stop.

    Voronoi edges are that shape by construction: straight segments, Y junctions
    where three cells meet, and toroidal by the same seed geometry the slab maps
    already rely on. Cutting the network with a broad noise mask keeps it from
    becoming a complete mosaic, because a fractured surface is cracked in places,
    not tessellated everywhere.

    `cells` is how many fragments the surface is broken into, and is deliberately
    independent of any slab layout in the base surface:
    a crack that followed the mortar would only deepen the joints it ran along.
    """
    _, boundary, cell = base.toroidal_voronoi(size, seed, cells, cells)
    mask = boundary < width
    if fragment_share is not None:
        # A COMPLETE network is crazy paving, not damage: over a surface that
        # already has a pattern it reads as a second competing tessellation
        # rather than as stone that has cracked. Selecting whole cells and
        # keeping only their perimeters gives contiguous closed runs -- a region
        # of broken material -- instead of either a full mosaic or the
        # disconnected stubs that per-pixel gating produced.
        lo = float(np.quantile(cell, 1.0 - fragment_share))
        chosen = cell >= lo
        touching = binary_dilation(chosen, iterations=max(2, int(size * width * 2)))
        mask = mask & touching
    # No region mask. Gating the edges on a noise field was the second wrong
    # answer: it cut every run into disconnected stubs, and dilating those to a
    # minimum width turned them into scattered dashes and plus-signs. A crack is
    # continuous or it is not a crack, so the whole network is kept and its
    # coarseness -- how many pieces the surface is broken into -- is the control.
    # A crack narrower than a runtime texel is not a subtle crack, it is absent:
    # the same lesson the fissure fixture taught at 52/4096 texels.
    return fa.enforce_min_thickness(mask, runtime_texels=runtime_texels)


def cut_fracture(field: np.ndarray, mask: np.ndarray, depth: float,
                 lip: float = 0.0) -> np.ndarray:
    """Remove material along the network, with an optional broken lip.

    The cut is subtractive and unconditional. A base surface has no alpha to
    negotiate with, which is the whole advantage: the fracture cannot be read as
    something added, because there is nothing here that was ever separate.
    """
    inside = distance_transform_edt(mask)
    # Tight: a crack has walls, not a valley. A wide profile is what turned the
    # first attempt into soft troughs.
    profile = base.smoothstep(0.0, 2.5, inside)
    out = field - profile * depth
    if lip > 0.0:
        # Material displaced from the crack piles at its edge, which is what
        # makes a fracture read as broken rather than machined.
        rim = base.smoothstep(0.0, 3.0, distance_transform_edt(~mask))
        out = out + np.clip(1.0 - rim, 0.0, 1.0) * lip
    return out


def ceiling_coffers_fractured(size: int):
    field, _ = base.ceiling_coffers(size)
    mask = fracture_mask(size, 8101, cells=4, fragment_share=0.22, runtime_texels=2.0)
    field = cut_fracture(field, mask, depth=0.34, lip=0.05)
    field += base.periodic_noise(size, 8102, ((3, 0.6), (9, 0.4))) * 0.02
    return base.force_wrap(gaussian_filter(field, 0.8, mode="wrap"), "xy"), np.ones_like(field)


def wall_ashlar_fractured(size: int):
    field, _ = base.wall_ashlar(size)
    mask = fracture_mask(size, 8201, cells=5, fragment_share=0.40)
    # 0.26 rather than 0.30: the ashlar's own joints are already deep, and the
    # sum bottomed out the encodable range at its darkest joints.
    field = cut_fracture(field, mask, depth=0.26, lip=0.045)
    return base.force_wrap(gaussian_filter(field, 0.85, mode=("nearest", "wrap")), "x"), np.ones_like(field)


def wall_limewash_fractured(size: int):
    field, _ = base.wall_limewash(size)
    # Crazing on a rendered surface: denser, shallower, no lip.
    #
    # The first version used the COMPLETE fine network at depth 0.22 and the model
    # painted a mosaic of separate stone tiles with grout -- precisely what the
    # prompt's negatives were written to prevent. The geometry decides and the
    # prompt cannot overrule it: a complete tessellation cut that deep IS the
    # paving signal. Partial coverage and a much shallower cut make it read as
    # craquelure in a render rather than as joints between pieces.
    mask = fracture_mask(size, 8301, cells=10, width=0.008, fragment_share=0.34,
                         runtime_texels=1.25)
    field = cut_fracture(field, mask, depth=0.13)
    return base.force_wrap(gaussian_filter(field, 0.7, mode=("nearest", "wrap")), "x"), np.ones_like(field)


def floor_flagstones_fractured(size: int):
    field, _ = base.floor_flagstones(size)
    mask = fracture_mask(size, 8401, cells=6, fragment_share=0.24)
    field = cut_fracture(field, mask, depth=0.32, lip=0.05)
    return base.force_wrap(gaussian_filter(field, 0.8, mode="wrap"), "xy"), np.ones_like(field)


SPECS = [
    base.MapSpec("ceiling_coffers_fractured", "ceiling", "baseSurface", "replace", 0.08,
                 "Wide coffers carrying a tiling fracture network; replaces the failed "
                 "hairline ceiling fixture.", ceiling_coffers_fractured),
    base.MapSpec("wall_ashlar_fractured", "wall", "baseSurface", "replace", 0.13,
                 "Ashlar courses broken by a tiling fracture network, as a wall variant.",
                 wall_ashlar_fractured),
    base.MapSpec("wall_limewash_fractured", "wall", "baseSurface", "replace", 0.10,
                 "Limewash render with tiling crazing; shallow and dense rather than broken.",
                 wall_limewash_fractured),
    base.MapSpec("floor_flagstones_fractured", "floor", "baseSurface", "replace", 0.11,
                 "Flagstone paving split by a tiling fracture network.", floor_flagstones_fractured),
]


def _assert_rules(manifest: dict) -> None:
    for row in manifest["maps"]:
        name = row["preset"]
        assert row["role"] == "baseSurface", f"{name} must be a base surface"
        assert row["alphaCoverage"] == 1.0, f"{name} must be fully opaque"
        # The cut has to actually reach below the surface it is cut into.
        floor = -0.12 if "limewash" in name else -0.18
        assert row["signedMin"] < floor, (
            f"{name} only reaches {row['signedMin']}; the fracture is not cutting")
        worst = max(row["wrapError"].values(), default=0.0)
        assert worst <= 1e-6, f"{name} fracture does not tile: wrap error {worst}"
        # Saturation is silent data loss: a clipped trench has a flat bottom the
        # engine will displace as a plateau, not a crack.
        assert row["signedMin"] > -0.995, (
            f"{name} bottoms out the encodable range at {row['signedMin']}")


def build(check_only: bool = False) -> dict:
    base.BATCH_ROOT = BATCH_ROOT
    base.HEIGHT_DIR = BATCH_ROOT / "height"
    base.MANIFEST_PATH = BATCH_ROOT / "manifest.json"
    base.CONTACT_PATH = BATCH_ROOT / "contact-sheet.png"
    base.SPECS = SPECS
    manifest = base.build(check_only=check_only)
    manifest["batchId"] = "first_stratum_fractured_baselines_20260807"
    manifest["source"] = "tools/asset-gen/build_fractured_baselines_20260807.py"
    manifest["reviewBasis"] = (
        "08-07 owner review: fissure-as-fixture scored 2.0 at every depth weight tried; "
        "a fracture belongs in the material, not on it.")
    if not check_only:
        _assert_rules(manifest)
        base.MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    manifest = build(check_only=args.check)
    for row in manifest["maps"]:
        print(f"  {row['preset']:<32} min {row['signedMin']:+.3f} max {row['signedMax']:+.3f} "
              f"wrap {max(row['wrapError'].values(), default=0):.1e}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
