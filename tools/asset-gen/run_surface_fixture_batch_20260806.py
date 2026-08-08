#!/usr/bin/env python3
"""Run the rich first-stratum surface/fixture batch and prepare fixture alpha.

This wrapper exists because `gen.py batch` deliberately models ordinary opaque
asset classes. Local surface fixtures need two extra guarantees:

1. Stable Diffusion is run without circular padding for localized fixtures.
2. The generated RGB is never trusted for transparency. The authoritative alpha
   from the authored height map is copied into an equally sized albedo/height
   pair after generation, with RGB bleed outside the visible contour.

The original staged variants are preserved. Prepared files are added beside them
as `fixture-<n>.png` and `fixture-height-<n>.png`, and the run manifest records
those paths for review and later promotion.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

from lib.fixture_preview import (PREVIEW_VERSION, contact_sheet, fixture_preview,
                                 normalize_height, prepare_fixture_albedo)

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "asset-gen"
DEFAULT_JOBS = TOOL / "batches" / "first_stratum_surface_fixture_20260806.json"
OUT = TOOL / "out"
SUMMARY = OUT / "first-stratum-surface-fixture-20260806-summary.json"


def safe(value: str) -> str:
    return re.sub(r"[^\w\-]", "_", str(value)).strip("_") or "unnamed"


def load_jobs(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    jobs = data.get("jobs", data) if isinstance(data, dict) else data
    if not isinstance(jobs, list) or not jobs:
        raise SystemExit(f"no jobs in {path}")
    return jobs


def run_path_for(job: dict) -> Path | None:
    prefix = f"{job['class']}-{safe(job['name'])}-"
    candidates = []
    for path in OUT.glob(prefix + "*"):
        manifest_path = path / "manifest.json"
        if not manifest_path.is_file():
            continue
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if manifest.get("name") != job["name"]:
            continue
        variants = manifest.get("variants") or []
        if len(variants) < int(job.get("variants", 1)):
            continue
        if not all((path / row.get("file", "")).is_file() for row in variants):
            continue
        candidates.append(path)
    return max(candidates, key=lambda item: item.stat().st_mtime) if candidates else None


def command_for(job: dict) -> list[str]:
    command = [sys.executable, str(TOOL / "gen.py"), "generate",
               job["class"], job["name"], job["description"]]
    scalar_flags = {
        "provider": "provider",
        "model": "model",
        "variants": "variants",
        "height": "height",
        "steps": "steps",
        "cfg": "cfg",
        "sampler": "sampler",
        "seed": "seed",
        "requestSize": "request-size",
        "depthWeight": "depth-weight",
        "negativeExtra": "negative-extra",
        "extra": "extra",
        "promptStyle": "prompt-style",
    }
    for key, flag in scalar_flags.items():
        value = job.get(key)
        # The model and the engine are shown DIFFERENT maps on purpose. SD gets
        # the fixture merged over the base surface it will sit in, because
        # conditioning on a shape floating in transparency hands the depth
        # preprocessor a hard blob boundary and the model paints the object that
        # boundary implies -- that is how a broken socket came back as a machined
        # porthole. The engine still gets `height`, the authoritative signed map
        # with real alpha; the conditioning map is opaque and would claim every
        # texel. prepare_fixture() deliberately keeps reading job["height"].
        if key == "height" and job.get("conditioningHeight"):
            value = job["conditioningHeight"]
        if value is not None:
            command.extend([f"--{flag}", str(value)])
    for lora in job.get("loras") or []:
        if isinstance(lora, dict):
            lora = f"{lora['name']}:{lora.get('weight', 0.8)}"
        command.extend(["--lora", str(lora)])
    if job.get("noTiling"):
        command.append("--no-tiling")
    return command


def forge_ready(url: str = "http://127.0.0.1:7860") -> bool:
    try:
        with urllib.request.urlopen(url.rstrip("/") + "/sdapi/v1/options", timeout=4) as response:
            return 200 <= response.status < 300
    except (OSError, urllib.error.URLError):
        return False


def prepare_fixture(job: dict, run_path: Path) -> None:
    """Prepare authoritative fixture pairs and a truthful neutral-base preview."""
    manifest_path = run_path / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_path = ROOT / job["height"]
    source = Image.open(source_path).convert("RGBA")
    previews = []

    for row in manifest.get("variants") or []:
        index = int(row["index"])
        variant_path = run_path / row["file"]
        albedo = Image.open(variant_path).convert("RGBA")
        height = normalize_height(source, albedo.size)
        prepared_albedo = prepare_fixture_albedo(albedo, height)
        review, composed_height = fixture_preview(
            prepared_albedo, height, job["heightOperation"],
            float(job["recommendedHeightScale"]), job["surface"])

        fixture_name = f"fixture-{index}.png"
        fixture_height_name = f"fixture-height-{index}.png"
        composite_height_name = f"fixture-composite-height-{index}.png"
        preview_name = f"fixture-preview-{index}.png"
        prepared_albedo.save(run_path / fixture_name, optimize=True)
        height.save(run_path / fixture_height_name, optimize=True)
        composed_height.save(run_path / composite_height_name, optimize=True)
        review.save(run_path / preview_name, optimize=True)

        alpha = np.asarray(height, dtype=np.uint8)[..., 3]
        grey = np.asarray(height, dtype=np.uint8)[..., 0].astype(np.int16)
        active = alpha > 0
        row["fixtureFile"] = fixture_name
        row["fixtureHeight"] = fixture_height_name
        row["fixtureCompositeHeight"] = composite_height_name
        row["fixturePreview"] = preview_name
        row["fixtureAlphaCoverage"] = round(float(np.mean(active)), 5)
        row["fixtureSignedMin"] = int(grey[active].min()) - 128
        row["fixtureSignedMax"] = int(grey[active].max()) - 128
        # gen.py/report and the browser rater already understand `context`.
        # Stamping this exact alpha-aware diagnostic prevents the old opaque
        # room preview from being silently reused.
        row["context"] = preview_name
        row["contextSurface"] = job["surface"]
        row["contextPreviewVersion"] = PREVIEW_VERSION
        row["contextLabel"] = (
            f"alpha-composited fixture over neutral grey and neutral height; "
            f"operation={job['heightOperation']}; "
            f"recommended scale={job['recommendedHeightScale']}"
        )
        previews.append(run_path / preview_name)

    manifest["surfaceFixturePreparation"] = {
        "preparedAt": dt.datetime.now().isoformat(timespec="seconds"),
        "heightSource": job["height"],
        "heightOperation": job["heightOperation"],
        "recommendedHeightScale": job["recommendedHeightScale"],
        "previewVersion": PREVIEW_VERSION,
        "previewBase": "neutral grey albedo and opaque RGB=128 neutral height",
        "alphaAuthority": "height PNG alpha copied after generation; SD output alpha ignored",
        "originalVariantsPreserved": True,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    contact_sheet(previews, run_path / "fixture-contact-sheet.png")


def select_jobs(jobs: list[dict], only: list[str], group: str | None,
                start_at: str | None, limit: int | None) -> list[dict]:
    selected = jobs
    if only:
        tokens = [token.casefold() for token in only]
        selected = [job for job in selected
                    if any(token in job["name"].casefold() for token in tokens)]
    if group:
        selected = [job for job in selected if job.get("group") == group]
    if start_at:
        position = next((i for i, job in enumerate(selected)
                         if start_at.casefold() in job["name"].casefold()), None)
        if position is None:
            raise SystemExit(f"--start-at did not match a job: {start_at}")
        selected = selected[position:]
    if limit is not None:
        selected = selected[:limit]
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=Path, default=DEFAULT_JOBS)
    parser.add_argument("--only", action="append", default=[], help="run names containing this; repeatable")
    parser.add_argument("--group", choices=("base", "fixture"))
    parser.add_argument("--start-at")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--force", action="store_true", help="regenerate even when a complete run exists")
    parser.add_argument("--dry-run", action="store_true", help="print exact commands without calling Forge")
    parser.add_argument("--skip-forge-check", action="store_true")
    parser.add_argument("--prepare-only", action="store_true",
                        help="rebuild authoritative fixture pairs/previews from existing runs; no Forge call")
    args = parser.parse_args()

    jobs = select_jobs(load_jobs(args.jobs), args.only, args.group, args.start_at, args.limit)
    if not jobs:
        raise SystemExit("selection contains no jobs")
    if (not args.dry_run and not args.prepare_only and
            not args.skip_forge_check and not forge_ready()):
        raise SystemExit("Forge is not responding at http://127.0.0.1:7860; start it with --api first")

    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for position, job in enumerate(jobs, 1):
        existing = run_path_for(job)
        command = command_for(job)
        print(f"\n=== [{position}/{len(jobs)}] {job['name']} ===")
        print(subprocess.list2cmdline(command))
        status = "dry-run"
        run_path = existing
        if not args.dry_run:
            if args.prepare_only:
                if not job.get("alphaFromHeight"):
                    print("  skip: not an alpha fixture")
                    status = "skipped-nonfixture"
                elif existing is None:
                    results.append({"name": job["name"], "status": "failed",
                                    "error": "--prepare-only found no complete staged run"})
                    continue
                else:
                    prepare_fixture(job, existing)
                    run_path = existing
                    status = "prepared-only+alpha-preview-v2"
                    print(f"  rebuilt authoritative alpha preview: {existing.relative_to(ROOT)}")
            else:
                if existing and not args.force:
                    print(f"  reuse complete run: {existing.relative_to(ROOT)}")
                    status = "reused"
                else:
                    completed = subprocess.run(command, cwd=ROOT, check=False)
                    if completed.returncode != 0:
                        results.append({"name": job["name"], "status": "failed",
                                        "returnCode": completed.returncode})
                        continue
                    run_path = run_path_for(job)
                    if run_path is None:
                        results.append({"name": job["name"], "status": "failed",
                                        "error": "generation completed but no staged run was found"})
                        continue
                    status = "generated"
                if job.get("alphaFromHeight"):
                    prepare_fixture(job, run_path)
                    status += "+alpha-preview-v2"
                    print(f"  prepared authoritative fixture alpha: {run_path.relative_to(ROOT)}")

        results.append({
            "name": job["name"],
            "group": job.get("group"),
            "status": status,
            "run": run_path.relative_to(ROOT).as_posix() if run_path else None,
        })

    summary = {
        "batch": "first_stratum_surface_fixture_20260806",
        "updatedAt": dt.datetime.now().isoformat(timespec="seconds"),
        "jobsFile": args.jobs.relative_to(ROOT).as_posix() if args.jobs.is_absolute() else args.jobs.as_posix(),
        "selected": len(jobs),
        "results": results,
    }
    if not args.dry_run:
        SUMMARY.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"\nsummary: {SUMMARY.relative_to(ROOT)}")
    failed = [row for row in results if row["status"] == "failed"]
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
