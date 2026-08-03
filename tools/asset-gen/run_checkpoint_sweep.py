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


def run(command):
    print("\n$ " + " ".join(str(part) for part in command), flush=True)
    # Keep the nested generator's output visible in the detached log while it
    # switches checkpoints and renders; otherwise Python buffers each batch.
    return subprocess.run(command, cwd=ROOT, check=False)


def completed_runs(names, variants):
    """Return the newest complete staged run for each deterministic job name."""
    found = {}
    for name in names:
        prefix = f"wallPiece-{safe_name(name)}-"
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


def write_report(prompt_id, prompt_label, runs):
    if not runs:
        print(f"No completed runs found for {prompt_id}; skipping report.")
        return 1
    report_path = OUT / f"overnight-wall-{prompt_id}-matrix.html"
    command = [sys.executable, str(GEN), "report"]
    command.extend(str(path) for path in runs)
    command.extend(
        [
            "--out",
            str(report_path),
            "--title",
            f"Overnight wall checkpoint sweep: {prompt_label}",
        ]
    )
    return run(command).returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variants", type=int, default=2)
    parser.add_argument("--only", nargs="*", help="prompt ids, for a smaller rerun")
    args = parser.parse_args()
    if args.variants < 1:
        parser.error("--variants must be positive")

    OUT.mkdir(parents=True, exist_ok=True)
    selected = [
        (index, prompt_id, description)
        for index, (prompt_id, description) in enumerate(PROMPTS, 1)
        if not args.only or prompt_id in args.only
    ]
    if not selected:
        parser.error("--only did not match a prompt id")

    all_runs = []
    failures = 0
    for prompt_index, (_, prompt_id, description) in enumerate(selected, 1):
        jobs = jobs_for(prompt_id, description, prompt_index, args.variants)
        jobs_path = OUT / f"overnight-wall-{prompt_id}-jobs.json"
        names = [job["name"] for job in jobs]
        complete = completed_runs(names, args.variants)
        pending = [job for job in jobs if job["name"] not in complete]
        jobs_path.write_text(json.dumps(pending, indent=2) + "\n", encoding="utf-8")
        print(
            f"\n=== prompt {prompt_index}/{len(selected)}: {prompt_id}; "
            f"{len(jobs)} checkpoints x {args.variants} variants; "
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
        runs = list(completed_runs(names, args.variants).values())
        all_runs.extend(runs)
        if write_report(prompt_id, prompt_id, runs):
            failures += 1

    if all_runs:
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
        f"\nSweep complete: {len(all_runs)} staged runs, {failures} report/batch issue(s).",
        flush=True,
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
