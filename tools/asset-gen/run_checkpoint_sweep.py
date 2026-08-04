"""Run a deterministic, non-agentic local checkpoint comparison sweep.

This is intentionally boring: for each prompt family it asks every installed
SD1.5-family checkpoint for a couple of variants, leaves every run in the
normal staging directory, then writes a self-contained HTML matrix.  It does
not select, promote, overwrite, or download anything.

The XL checkpoints are deliberately not included.  This Forge installation is
the project's 4 GB SD1.5 profile; sending SDXL checkpoints through the SD1.5
ControlNet/material path would turn this into a compatibility test rather than
a useful checkpoint comparison.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GEN = ROOT / "tools" / "asset-gen" / "gen.py"
OUT = ROOT / "tools" / "asset-gen" / "out"
HEIGHT = "assets/geometry/0_hand_authored_depth_maps/tiled_wall_with_column.png"

# The list is copied from the local Forge checkpoint inventory on 2026-08-03.
# Keep this explicit so a report remains reproducible if checkpoints are added
# or removed while the sweep is asleep.
MODELS = [
    "DreamShaper_8_pruned",
    "aLunarDreamBeta_aLunarDreamV1",
    "aamAnyloraAnimeMixAnime_v1",
    "airfucksWildMix_v10",
    "anyloraCheckpoint_bakedvaeBlessedFp16",
    "anyloraCheckpoint_bakedvaeFtmseFp16NOT",
    "anyloraCheckpoint_lcm",
    "boxmix25DMale_v10Boxcat",
    "chilloutmix_NiPrunedFp32Fix",
    "daddyDiffusion_v1",
    "deepboys25D_v20",
    "dreamshaper_8LCM",
    "everyjourneylcm_v10Ace",
    "goofballMix_v3Baked",
    "homodiffusionGay_homoDiffusionV10FP32",
    "homosimile_v40",
    "littleFishNaiLCM_v10",
    "lyriel_v16",
    "maturemalemix_v13",
    "megatronmerge_",
    "mistoonAnime_v30",
    "newERANewEstheticRetro_retroV60VAE",
    "ohmenOrigins_ohmenOriginsV3",
    "ohmenToontastic_ohmenToontasticV2",
    "perfectWorld_v3Baked",
    "sd-v1-4",
    "sigmatron_Hyper",
    "slimexFp16NoEmaClipFix_slimex2KClipFix",
    "tAnimeV4Pruned_v40",
    "v1-5-pruned-emaonly",
    "virileReality_v20",
]

PROMPTS = [
    (
        "masonry",
        "muted limestone dungeon masonry, broad irregular fitted stone blocks, restrained ochre and cool slate, weathered mineral variation, unlit albedo material, diffuse base color only, flat material color, soft ambient fill",
    ),
    (
        "shrine",
        "ornate low-fantasy shrine wall masonry, broad fitted sandstone blocks, shallow carved architectural bands, restrained engraved relief motifs, muted ochre and cool slate, unlit albedo material, diffuse base color only, flat material color, soft ambient fill",
    ),
    (
        "basalt",
        "dark basalt dungeon wall masonry, broad block courses, subtle pale mineral veins, worn chipped edges, restrained earth and slate palette, unlit albedo material, diffuse base color only, flat material color, soft ambient fill",
    ),
    (
        "cathedral",
        "ancient monumental dungeon wall material, pale limestone and oxidized bronze accents, broad carved masonry courses, quiet fantasy architecture, restrained desaturated jewel tones, unlit albedo material, diffuse base color only, flat material color, soft ambient fill",
    ),
]

# A second, more diagnostic experiment. The previous sweep established that
# these checkpoints can all decode coherently; this matrix asks which visual
# prior is actually useful, how strongly a retro/background LoRA should pull
# it, and how much ControlNet weight buys registration before it starts
# flattening the material. Six report groups x 40 jobs x two variants has been
# sized from the measured first sweep to occupy roughly six hours on this GPU.
STYLE_MODELS = [
    ("ohmen", "ohmenOrigins_ohmenOriginsV3"),
    ("homosimile", "homosimile_v40"),
    ("mature", "maturemalemix_v13"),
    ("newera", "newERANewEstheticRetro_retroV60VAE"),
    ("perfect", "perfectWorld_v3Baked"),
]

STYLE_LORAS = [
    ("control", None),
    ("ff8bg", "FF8BG"),
    ("ffix", "FFIX-10"),
    ("resevil", "resevil"),
    ("pc90", "1990's_PC_v2"),
    ("ps1", "Hideous_PS1_Game"),
    ("ogrebattle", "Ogre_Battle_SNES64"),
    ("genesis", "GenesisGameplayV1"),
]

STYLE_PROMPTS = [
    (
        "material",
        "muted limestone dungeon masonry, broad irregular fitted blocks, weathered mineral variation, quiet low-fantasy architectural material, restrained ochre and cool slate, unlit albedo material, diffuse base color only, flat material color, soft ambient fill",
    ),
    (
        "ornament",
        "ancient shrine wall masonry, broad carved sandstone courses, shallow geometric relief bands, eroded sacred ornament, oxidized bronze traces, restrained desaturated jewel tones, unlit albedo material, diffuse base color only, flat material color, soft ambient fill",
    ),
]

DEPTH_WEIGHTS = [0.35, 0.60, 0.85]

# A third, much smaller experiment, and the first to spend the previous two.
# The style-depth matrix settled the free parameters -- depth weight 0.60,
# maturemalemix and newERA as the two usable priors, resevil and genesis as the
# two LoRAs that help -- so nothing here re-tests them. What is new is the
# GEOMETRY: six height maps rendered from real Blender scenes instead of one
# hand-authored wall, and three surface types instead of one. The question is
# whether a configuration tuned on a single flat wall survives an arched niche,
# a groin vault and a floor.
KIT_MAPS_DIR = "assets/geometry/1_blender_depth_maps"


def kit_maps():
    """Every Blender height map, read from the library's own manifest.

    Not a list kept in step by hand: adding a preset to scenes.py and rendering
    it should be enough to put it in the next batch, and a map that failed its
    wrap check should never reach one. Re-running the experiment is safe --
    already-staged jobs are detected and skipped, so a new preset costs only its
    own renders.
    """
    path = ROOT / KIT_MAPS_DIR / "manifest.json"
    try:
        records = json.loads(path.read_text(encoding="utf-8"))["maps"]
    except (OSError, KeyError, json.JSONDecodeError) as err:
        raise SystemExit(f"no usable height-map manifest at {path}: {err}\n"
                         f"run: python tools/asset-gen/blendergeom.py")
    return [(record["preset"], record["surface"]) for record in records
            if record.get("wrapOk", True)]

# The control is carried deliberately. A LoRA earns its place on the geometry
# it will actually be used with, and neither of these was chosen on a vault.
KIT_STYLES = [
    ("mature_resevil", "maturemalemix_v13", "resevil"),
    ("newera_genesis", "newERANewEstheticRetro_retroV60VAE", "GenesisGameplayV1"),
    ("mature_control", "maturemalemix_v13", None),
]

# Walls join only left-to-right; floors and ceilings repeat in every direction.
KIT_CLASS = {"wall": "wallPiece", "floor": "texturePiece",
             "ceiling": "texturePiece"}

KIT_PROMPTS = {
    "wall": "muted limestone dungeon wall masonry, broad fitted blocks, weathered mineral variation, quiet low-fantasy architecture, restrained ochre and cool slate",
    "floor": "worn dungeon floor pavement, broad fitted flagstones, scuffed mineral variation, quiet low-fantasy architecture, restrained ochre and cool slate",
    "ceiling": "ancient dungeon ceiling masonry seen from below, broad fitted stone courses, soot-stained mineral variation, quiet low-fantasy architecture, restrained ochre and cool slate",
}

# Two material vocabularies, run as an A/B rather than a replacement.
#
# "flat" is what the first kit batch used, and it is now believed to be wrong:
# it asks for an albedo with no occlusion at all. The engine lights a scene at
# runtime but does NOT bake ambient occlusion on top of a texture, so a
# perfectly unlit albedo arrives in game with no depth in its joints and reads
# as plastic. The owner was scoring such textures down for obeying the prompt.
#
# "ao" asks for the occlusion to be painted in while still refusing DIRECT
# light, which is the part the engine really does own -- torches, direct
# shadows and their direction have to stay the renderer's job or the texture
# fights the lighting it is lit by.
#
# Both are kept because "the prompt was wrong" is a hypothesis until the same
# geometry, models and seeds have been judged under each.
KIT_SUFFIXES = {
    "flat": "unlit albedo material, diffuse base color only, flat material color, soft ambient fill",
    "ao": ("diffuse albedo with baked ambient occlusion, soft contact shadows in every joint "
           "and recess, gentle self-shadowing, deep crevices darker than raised faces, "
           "ambient fill only, no directional light, no cast shadows"),
}

KIT_DEPTH_WEIGHT = 0.60


def safe_name(value: str) -> str:
    return re.sub(r"[^\w\-]", "_", value).strip("_") or "unnamed"


def jobs_for(prompt_id: str, description: str, prompt_index: int, variants: int):
    jobs = []
    for model_index, model in enumerate(MODELS):
        name = f"overnight_{prompt_id}_{safe_name(model)}"
        jobs.append(
            {
                "name": name,
                "class": "wallPiece",
                "provider": "forge-quality",
                "model": model,
                "description": description,
                "height": HEIGHT,
                "variants": variants,
                "steps": 20,
                "cfg": 6.5,
                "seed": 120000 + prompt_index * 1000 + model_index * 10,
                "requestSize": "256x256",
            }
        )
    return jobs


def checkpoint_groups(variants):
    return [
        {
            "id": prompt_id,
            "label": f"checkpoint sweep: {prompt_id}",
            "jobs": jobs_for(prompt_id, description, index, variants),
        }
        for index, (prompt_id, description) in enumerate(PROMPTS, 1)
    ]


def style_depth_groups(variants):
    groups = []
    for prompt_index, (prompt_id, description) in enumerate(STYLE_PROMPTS, 1):
        for depth_weight in DEPTH_WEIGHTS:
            depth_id = f"d{round(depth_weight * 100):02d}"
            jobs = []
            # A paired seed across models, LoRAs and depth weights makes visual
            # differences attributable to the tested factor instead of chance.
            seed = 860000 + prompt_index * 100
            for model_key, model in STYLE_MODELS:
                for lora_key, lora in STYLE_LORAS:
                    job = {
                        "name": f"insight_{prompt_id}_{depth_id}_{model_key}_{lora_key}",
                        "class": "wallPiece",
                        "provider": "forge-quality",
                        "model": model,
                        "description": description,
                        "height": HEIGHT,
                        "depthWeight": depth_weight,
                        "variants": variants,
                        "steps": 20,
                        "cfg": 6.5,
                        "seed": seed,
                        "requestSize": "256x256",
                    }
                    if lora:
                        job["loras"] = [{"name": lora, "weight": 0.55}]
                    jobs.append(job)
            groups.append({
                "id": f"{prompt_id}-{depth_id}",
                "label": (f"style x checkpoint: {prompt_id}; "
                          f"ControlNet depth weight {depth_weight:.2f}"),
                "jobs": jobs,
            })
    return groups


def surface_kit_groups(variants, material="flat"):
    """One report per surface type, every Blender map against every style.

    `material` selects the vocabulary and is carried in the job name. That is
    what keeps the A/B honest: a re-run under a new prompt with the OLD names
    would be seen as already staged and silently skipped, so the comparison
    would quietly never happen.
    """
    groups = []
    available = kit_maps()
    tag = "" if material == "flat" else f"{material}_"
    for surface in ("wall", "floor", "ceiling"):
        maps = [name for name, kind in available if kind == surface]
        jobs = []
        for map_index, map_name in enumerate(maps):
            for style_key, model, lora in KIT_STYLES:
                job = {
                    "name": f"kit_{tag}{map_name}_{style_key}",
                    "class": KIT_CLASS[surface],
                    "provider": "forge-quality",
                    "model": model,
                    "description": f"{KIT_PROMPTS[surface]}, {KIT_SUFFIXES[material]}",
                    "height": f"{KIT_MAPS_DIR}/{map_name}.png",
                    "depthWeight": KIT_DEPTH_WEIGHT,
                    "variants": variants,
                    "steps": 20,
                    "cfg": 6.5,
                    # Held across styles so a difference between two cards is
                    # the style, and varied across maps so a good result is not
                    # one lucky seed repeated six times.
                    "seed": 910000 + map_index * 100,
                    "requestSize": "256x256",
                }
                if lora:
                    job["loras"] = [{"name": lora, "weight": 0.55}]
                jobs.append(job)
        groups.append({
            "id": f"{tag}{surface}",
            "label": (f"blender geometry kit: {surface}; {material} material; "
                      f"ControlNet depth weight {KIT_DEPTH_WEIGHT:.2f}"),
            "jobs": jobs,
        })
    return groups


# A fourth experiment, and the first whose verdict needs no eye at all.
#
# The negative prompt gained face/figure and margin/blank terms on 03.08 after
# the owner reported hallucinated faces in rock and dead white strips. Whether
# that WORKS is measurable: `lib.raw_quality.blank_bands` counts dead margins,
# and a Haar cascade counts face-like structure. So this re-runs an existing
# slice with the same models, LoRAs and seeds, changing only the negative
# prompt, and the two sets are compared mechanically.
#
# The slice is the style-depth ornament matrix at depth 0.60 -- ornament because
# carved relief is where faces appear, and these four LoRAs because they hold
# the worst measured margin rates (Ogre Battle 33%, PS1 12%, FFIX 7%, control 8%).
NEG_LORAS = [
    ("control", None),
    ("ffix", "FFIX-10"),
    ("ogrebattle", "Ogre_Battle_SNES64"),
    ("ps1", "Hideous_PS1_Game"),
]


def negprompt_groups(variants):
    prompt_id, description = STYLE_PROMPTS[1]          # "ornament"
    # Identical to the seed the original slice used, so each new image is the
    # PAIR of an existing one and any difference is the negative prompt alone.
    seed = 860000 + 2 * 100
    jobs = []
    for model_key, model in STYLE_MODELS:
        for lora_key, lora in NEG_LORAS:
            job = {
                "name": f"neg_{prompt_id}_d60_{model_key}_{lora_key}",
                "class": "wallPiece",
                "provider": "forge-quality",
                "model": model,
                "description": description,
                "height": HEIGHT,
                "depthWeight": 0.60,
                "variants": variants,
                "steps": 20,
                "cfg": 6.5,
                "seed": seed,
                "requestSize": "256x256",
            }
            if lora:
                job["loras"] = [{"name": lora, "weight": 0.55}]
            jobs.append(job)
    return [{
        "id": "negprompt",
        "label": ("negative-prompt A/B: ornament at depth 0.60, "
                  "paired by seed against the 03.08 style-depth slice"),
        "jobs": jobs,
    }]


# A fifth experiment: the first models in this project actually TRAINED for the
# job. Everything swept so far is a portrait or figure checkpoint doing masonry
# under protest, and the installed LoRA library contained no texture or
# architecture LoRA at all -- the retro ones (FF8BG, PS1, Ogre Battle) impart a
# rendering aesthetic and know nothing about tileable material.
#
# Downloaded 03.08 after that inventory:
#   DiffuseTexture_v11  SD1.5 LoRA, trained on 386 PolyHaven material textures
#   artius15_v20VAE     SD1.5 checkpoint whose author lists textures/game assets
#
# Seeds and geometry match the `kit_ao_` runs exactly, so each result has a
# direct counterpart among the current best and the comparison needs no new
# baseline. `newera` and `mature` are carried so the LoRA can be judged against
# the same checkpoints without it.
NEW_STYLES = [
    ("artius_diffuse", "artius15_v20VAE", "DiffuseTexture_v11"),
    ("artius_control", "artius15_v20VAE", None),
    ("newera_diffuse", "newERANewEstheticRetro_retroV60VAE", "DiffuseTexture_v11"),
    ("mature_diffuse", "maturemalemix_v13", "DiffuseTexture_v11"),
]

# A spread of surfaces rather than every map: enough to see whether a texture
# model generalises across wall/floor/ceiling without spending an hour on it.
NEW_MAPS = ["wall_pilasters", "wall_rubble", "floor_cobbles", "ceiling_coffers"]


def kit_seed(map_name):
    """The seed surface_kit_groups gives this map, rederived the same way.

    Its map index is per SURFACE, not global, so it cannot be guessed from a
    position in NEW_MAPS -- and a wrong seed here would quietly turn a paired
    comparison into an unpaired one that still looks like a table.
    """
    available = kit_maps()
    surface = dict(available).get(map_name)
    ordered = [name for name, kind in available if kind == surface]
    return 910000 + ordered.index(map_name) * 100


def newmodels_groups(variants):
    surface_of = dict(kit_maps())
    jobs = []
    for map_name in NEW_MAPS:
        surface = surface_of.get(map_name)
        if not surface:
            continue
        for style_key, model, lora in NEW_STYLES:
            job = {
                "name": f"new_{map_name}_{style_key}",
                "class": KIT_CLASS[surface],
                "provider": "forge-quality",
                "model": model,
                # The trained-in trigger. A material LoRA that is never invoked
                # is just a small perturbation of the base model, and the whole
                # question here is what it does when it IS invoked.
                "description": (f"diffuse texture, {KIT_PROMPTS[surface]}, "
                                f"{KIT_SUFFIXES['ao']}") if lora else
                               f"{KIT_PROMPTS[surface]}, {KIT_SUFFIXES['ao']}",
                "height": f"{KIT_MAPS_DIR}/{map_name}.png",
                "depthWeight": KIT_DEPTH_WEIGHT,
                "variants": variants,
                "steps": 20,
                "cfg": 6.5,
                # Matches surface_kit_groups' seed for this map, so a result is
                # the paired counterpart of an existing kit_ao_ image.
                "seed": kit_seed(map_name),
                "requestSize": "256x256",
            }
            if lora:
                job["loras"] = [{"name": lora, "weight": 0.7}]
            jobs.append(job)
    return [{
        "id": "newmodels",
        "label": ("purpose-trained models: Artius checkpoint and the PolyHaven "
                  "DiffuseTexture LoRA, seed-paired against the kit_ao runs"),
        "jobs": jobs,
    }]


def run(command):
    print("\n$ " + " ".join(str(part) for part in command), flush=True)
    # Keep the nested generator's output visible in the detached log while it
    # switches checkpoints and renders; otherwise Python buffers each batch.
    return subprocess.run(command, cwd=ROOT, check=False)


def completed_runs(jobs, variants):
    """Return the newest complete staged run for each deterministic job name.

    Keyed by (class, name) because the staging directory is named after both,
    and the surface kit is the first experiment to stage more than one class.
    """
    found = {}
    for job in jobs:
        name = job["name"]
        prefix = f"{job.get('class', 'wallPiece')}-{safe_name(name)}-"
        for path in OUT.glob(prefix + "*"):
            manifest_path = path / "manifest.json"
            if not manifest_path.is_file():
                continue
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if (manifest.get("name") == name
                    and len(manifest.get("variants") or []) >= variants):
                previous = found.get(name)
                if previous is None or path.stat().st_mtime > previous.stat().st_mtime:
                    found[name] = path
    return found


def write_report(group_id, group_label, runs, experiment):
    if not runs:
        print(f"No completed runs found for {group_id}; skipping report.")
        return 1
    prefix = {"style-depth": "sixhour-wall",
              "surface-kit": "surface-kit",
              "surface-kit-ao": "surface-kit",
              "negprompt": "negprompt",
              "newmodels": "newmodels"}.get(experiment, "overnight-wall")
    report_path = OUT / f"{prefix}-{group_id}-matrix.html"
    command = [sys.executable, str(GEN), "report"]
    command.extend(str(path) for path in runs)
    command.extend(
        [
            "--out",
            str(report_path),
            "--title",
            f"Local wall experiment: {group_label}",
        ]
    )
    return run(command).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variants", type=int, default=2)
    parser.add_argument("--experiment",
                        choices=("checkpoint", "style-depth", "surface-kit", "surface-kit-ao",
                                 "negprompt", "newmodels"),
                        default="checkpoint")
    parser.add_argument("--only", nargs="*", help="report group ids, for a smaller rerun")
    args = parser.parse_args()
    if args.variants < 1:
        parser.error("--variants must be positive")

    OUT.mkdir(parents=True, exist_ok=True)
    groups = {
        "style-depth": style_depth_groups,
        "surface-kit": surface_kit_groups,
        "surface-kit-ao": lambda n: surface_kit_groups(n, "ao"),
        "negprompt": negprompt_groups,
        "newmodels": newmodels_groups,
        "checkpoint": checkpoint_groups,
    }[args.experiment](args.variants)
    selected = [group for group in groups if not args.only or group["id"] in args.only]
    if not selected:
        parser.error("--only did not match a report group id")

    all_runs = []
    failures = 0
    for group_index, group in enumerate(selected, 1):
        group_id, jobs = group["id"], group["jobs"]
        jobs_path = OUT / f"{args.experiment}-wall-{group_id}-jobs.json"
        complete = completed_runs(jobs, args.variants)
        pending = [job for job in jobs if job["name"] not in complete]
        jobs_path.write_text(json.dumps(pending, indent=2) + "\n", encoding="utf-8")
        print(
            f"\n=== group {group_index}/{len(selected)}: {group_id}; "
            f"{len(jobs)} jobs x {args.variants} variants; "
            f"{len(complete)} already complete, {len(pending)} pending ===",
            flush=True,
        )
        if pending:
            result = run([sys.executable, "-u", str(GEN), "batch", str(jobs_path)])
            if result.returncode:
                failures += 1
                print(f"Batch returned {result.returncode}; continuing to the report.", flush=True)
        else:
            print("All checkpoint runs for this prompt are already staged; no SD calls made.", flush=True)
        runs = list(completed_runs(jobs, args.variants).values())
        all_runs.extend(runs)
        if write_report(group_id, group["label"], runs, args.experiment):
            failures += 1

    if all_runs and args.experiment == "checkpoint":
        overview = OUT / "overnight-wall-checkpoint-sweep.html"
        command = [sys.executable, str(GEN), "report"]
        command.extend(str(path) for path in dict.fromkeys(str(path) for path in all_runs))
        command.extend(
            [
                "--out",
                str(overview),
                "--title",
                "Overnight wall checkpoint sweep: all prompt families",
            ]
        )
        if run(command).returncode:
            failures += 1

    print(
        f"\n{args.experiment} sweep complete: {len(all_runs)} staged runs, "
        f"{failures} report/batch issue(s).",
        flush=True,
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
