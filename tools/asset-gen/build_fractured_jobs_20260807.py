#!/usr/bin/env python3
"""Render jobs for the fractured base-surface variants.

Base surfaces need no conditioning twin: the authored map is already opaque, so
what the engine receives and what the model is conditioned on are the same image.
That is the second reason a fracture belongs here rather than in a fixture -- the
whole alpha/transparency problem simply does not arise.

Depth weight sits in the 0.56-0.62 band every 5-and-6 rated surface map used,
NOT the 0.74-0.82 the fixtures needed. A base surface fills the depth field, so
it does not have to shout over anything.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parents[1]
MANIFEST = ROOT / "assets" / "geometry" / "3_authored_surface_maps" / "first_stratum_20260807_fractured" / "manifest.json"
OUT = TOOL / "batches" / "first_stratum_fractured_20260807.json"

NEGATIVE = ("interior room, corridor, tunnel, passage, architecture scene, "
            "environmental concept art, establishing shot, camera view, receding floor, "
            "receding ceiling, perspective wall, outdoor facade, ruin landscape, "
            "doorway view, archway view, horizon line, foreground, background, cutaway, "
            "diorama, framed picture, poster, diagram labels, repeated emblem, "
            "repeated focal object, dramatic black cavity")

# The fracture network and a paving pattern are the same shape to a diffusion
# model, so every prompt here has to say which one it is. Left unsaid, the model
# resolves a crack net into mortar joints and returns a mosaic.
NOT_PAVING = ("mosaic, tile pattern, crazy paving, cobblestone pattern, grout, "
              "mortar joints between separate tiles, inlay, marquetry, "
              "deliberate stonework pattern, tiled floor, brickwork infill")

CLASS_FOR = {"wall": "wallPiece", "floor": "texturePiece", "ceiling": "texturePiece"}

JOBS = {
    "ceiling_coffers_fractured": dict(
        seed=371100, depthWeight=0.60,
        description=(
            "aged limestone ceiling of wide shallow coffers, one region split by open "
            "structural cracks with crumbling lips and dark interiors, fine grit and "
            "mineral staining along the breaks, intact coffered panels elsewhere, "
            "muted ivory and smoke-grey, orthographic ceiling material"),
        extra=("cracked stone ceiling material, fractures cut into the panels, "
               "coffers still legible, damage in one region only")),
    "wall_ashlar_fractured": dict(
        seed=371200, depthWeight=0.58,
        description=(
            "old fitted limestone ashlar wall, staggered courses broken by open fracture "
            "lines running across several blocks, split stone faces with chipped crumbling "
            "edges and dark crack interiors, muted warm grey and old ivory, sparse mineral "
            "staining, quiet undercroft wall material"),
        extra=("cracked masonry material, fractures crossing the blocks, courses still "
               "legible, structural damage not decoration")),
    "wall_limewash_fractured": dict(
        seed=371300, depthWeight=0.56,
        description=(
            "old limewashed plaster wall, dense fine crazing across the render, hairline "
            "craquelure with a few flakes lifted at the edges, chalky muted ivory with "
            "faint ochre staining, soft undulation beneath, quiet interior wall material"),
        extra=("crazed lime render material, fine craquelure network, shallow hairline "
               "cracking, chalky matte surface")),
    "floor_flagstones_fractured": dict(
        seed=371400, depthWeight=0.60,
        description=(
            "worn limestone flagstone floor, several slabs split by open cracks with "
            "crumbling edges and dark interiors, displaced fragments settled slightly "
            "out of level, muted grey-brown stone with restrained mortar, orthographic "
            "floor material seen from directly above"),
        extra=("cracked paving material, fractures splitting the slabs themselves, "
               "broken stone not new stonework, damage across part of the surface")),
}


def build() -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    jobs = []
    for record in manifest["maps"]:
        name = record["preset"]
        spec = JOBS.get(name)
        if spec is None:
            raise SystemExit(f"no prompt authored for {name}")
        if record["role"] != "baseSurface":
            raise SystemExit(f"{name} is not a base surface")
        jobs.append({
            "group": "base",
            "name": f"first_stratum_frac_{name}",
            "class": CLASS_FOR[record["surface"]],
            "surface": record["surface"],
            "description": spec["description"],
            "height": record["path"],
            "seed": spec["seed"],
            "depthWeight": spec["depthWeight"],
            "heightOperation": record["heightOperation"],
            "recommendedHeightScale": record["recommendedHeightScale"],
            # Opaque by construction; there is no alpha to copy and no fixture
            # preparation step. Tiling stays ON: these are instanced per cell.
            "alphaFromHeight": False,
            "extra": spec["extra"],
            "provider": "forge-quality",
            "model": "ohmenOrigins_ohmenOriginsV3",
            "variants": 3,
            "steps": 26,
            "cfg": 6.5,
            "sampler": "DPM++ 2M",
            "requestSize": "512x512",
            "promptStyle": "tags",
            "negativeExtra": NEGATIVE + ", " + NOT_PAVING,
        })
    return {
        "manifestKind": "surfaceFixtureRenderJobs",
        "manifestVersion": 2,
        "batchId": "first_stratum_fractured_20260807",
        "createdFrom": MANIFEST.relative_to(ROOT).as_posix(),
        "notes": (
            "Fracture as a base-surface variant after the fixture route scored 2.0 at "
            "every depth weight. Opaque and tiling, so no conditioning twin and no alpha "
            "to negotiate. Prompts negate paving/mosaic explicitly because a crack net "
            "and mortar joints are the same shape to the model."),
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
        print(f"  {job['name']:<48} {job['surface']:<8} depth {job['depthWeight']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
