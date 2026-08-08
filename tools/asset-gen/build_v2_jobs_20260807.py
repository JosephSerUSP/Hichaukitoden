#!/usr/bin/env python3
"""Emit render jobs for the corrected v2 fixtures.

Generated from the batch manifest rather than hand-written, so a job can never
name a height map, an operation or a recommended scale that disagrees with the
map that was actually authored -- and so `conditioningHeight` is always the twin
of `height` from the same build.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parents[1]
MANIFEST = ROOT / "assets" / "geometry" / "3_authored_surface_maps" / "first_stratum_20260807_v2" / "manifest.json"
OUT = TOOL / "batches" / "first_stratum_surface_fixture_v2_20260807.json"

NEGATIVE = ("interior room, corridor, tunnel, passage, architecture scene, "
            "environmental concept art, establishing shot, camera view, receding floor, "
            "receding ceiling, perspective wall, outdoor facade, ruin landscape, "
            "doorway view, archway view, horizon line, foreground, background, cutaway, "
            "diorama, framed picture, poster, diagram labels, repeated emblem, "
            "repeated focal object, dramatic black cavity")

# Prompts revised against the 08-07 misses. Two deliberate changes: the word
# "irregular" and its friends now appear as explicit art direction, because the
# model regularized every asymmetric authored field into a machined form; and no
# prompt names a human subject, because "votive plaque" alone was enough to make
# SD paint portrait medallions where the height map described a plain oval mass.
CLASS_FOR = {"wall": "wallPiece", "floor": "texturePiece", "ceiling": "texturePiece"}

JOBS = {
    "fixture_floor_bronze_rite_inlay_plate": dict(
        seed=361100, depthWeight=0.74, cfg=6.0,
        description=(
            "aged ritual bronze disc set flush into limestone paving, one localized "
            "circular metal plate carrying thin concentric rings and sparse radial lines, "
            "tarnished dark bronze with uneven green patina, hand-cut slightly uneven "
            "engraving, nearly flush with the stone, exact orthographic floor material, "
            "broad quiet surrounding limestone"),
        extra=("single seated metal plate, continuous disc, thin uneven engraved lines, "
               "broad plain stone margin, no lettering")),
    "fixture_ceiling_mineral_fissure_thick": dict(
        seed=361200, depthWeight=0.76, cfg=6.0,
        description=(
            "aged plaster and limestone ceiling material, one localized branching mineral "
            "fracture, open irregular crooked seams of uneven width, crumbling lips, "
            "sparse mineral staining, muted ivory and smoke-grey surface, intact ceiling "
            "material continuing quietly around the fracture"),
        extra=("single branching fissure, irregular uneven seam width, ragged natural "
               "edges, broad intact ceiling margin"),
        negativeExtra=(NEGATIVE + ", tree root, root fibres, vine, tendril, woody branch, "
                       "botanical roots, hole, opening, cave, tunnel mouth, sky through crack, "
                       "ceiling photograph, straight line, ruled line, engraved groove, "
                       "machined channel, symmetrical crack")),
    "fixture_wall_breach_socket_hugged": dict(
        seed=361300, depthWeight=0.80, cfg=6.0,
        description=(
            "old limestone wall broken away in one place, a localized irregular ragged "
            "cavity with asymmetric chipped stone lips, uneven crumbling depth, loose grit "
            "and fracture scars, muted grey-brown and old ivory, broad quiet surrounding "
            "wall material, exact front elevation"),
        extra=("single ragged broken cavity, asymmetric irregular outline, crumbled uneven "
               "rim, broad neutral wall, damage not construction"),
        negativeExtra=(NEGATIVE + ", circular porthole, round window, machined bore, "
                       "drilled hole, symmetrical opening, turned rim, moulded frame, "
                       "concentric ring, manufactured socket, pipe fitting")),
    "fixture_floor_collapsed_socket_hugged": dict(
        seed=361400, depthWeight=0.82, cfg=6.0,
        description=(
            "localized collapse in a broad limestone slab floor, one irregular subsided pit "
            "with a few large surviving slab shoulders tipped at uneven angles, compacted "
            "dark fill and rubble grit below, muted grey-brown stone, surrounding intact "
            "paving continuing quietly to every edge, orthographic view from above"),
        extra=("single contained floor collapse, asymmetric irregular outline, tipped broken "
               "slabs, broad intact paving margin"),
        negativeExtra=(NEGATIVE + ", circular pit, round manhole, machined bore, "
                       "symmetrical opening, drain cover, moulded rim")),
}


def build() -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    jobs = []
    for record in manifest["maps"]:
        name = record["preset"]
        spec = JOBS.get(name)
        if spec is None:
            raise SystemExit(f"no prompt authored for {name}")
        if not record.get("conditioningPath"):
            raise SystemExit(f"{name} has no conditioning map; rebuild the batch")
        jobs.append({
            "group": "fixture",
            "name": f"first_stratum_v2_{name}",
            "class": CLASS_FOR[record["surface"]],
            "surface": record["surface"],
            "description": spec["description"],
            # Authoritative: real alpha, what the engine and prepare_fixture use.
            "height": record["path"],
            # What SD is conditioned on: the same fixture merged over its base.
            "conditioningHeight": record["conditioningPath"],
            "seed": spec["seed"],
            "depthWeight": spec["depthWeight"],
            "heightOperation": record["heightOperation"],
            "recommendedHeightScale": record["recommendedHeightScale"],
            "alphaFromHeight": True,
            "noTiling": True,
            "extra": spec["extra"],
            "provider": "forge-quality",
            "model": "ohmenOrigins_ohmenOriginsV3",
            "variants": 3,
            "steps": 26,
            "cfg": spec["cfg"],
            "sampler": "DPM++ 2M",
            "requestSize": "512x512",
            "promptStyle": "tags",
            "negativeExtra": spec.get("negativeExtra", NEGATIVE),
        })
    return {
        "manifestKind": "surfaceFixtureRenderJobs",
        "manifestVersion": 2,
        "batchId": "first_stratum_surface_fixture_v2_20260807",
        "createdFrom": MANIFEST.relative_to(ROOT).as_posix(),
        "notes": (
            "Corrects the three alpha defects from the 08-07 owner review and conditions "
            "SD on the fixture merged over its real base surface instead of on "
            "transparency. Prompts add explicit irregularity direction and negate "
            "manufactured circular forms, because the previous pass regularized every "
            "asymmetric authored field."),
        "jobs": jobs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    spec = build()
    if not args.check:
        OUT.write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    print(f"{len(spec['jobs'])} jobs -> {OUT.relative_to(ROOT).as_posix()}")
    for job in spec["jobs"]:
        print(f"  {job['name']:<52} depth {job['depthWeight']} cfg {job['cfg']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
