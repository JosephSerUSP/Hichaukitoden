#!/usr/bin/env python3
"""Verify deterministic Blender depth maps and manage reviewed baseline changes.

This tool deliberately separates renderer repeatability from historical-baseline
compatibility. It never changes tracked assets unless ``--mode adopt`` and the
explicit confirmation token are both supplied.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageEnhance

ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "tools" / "asset-gen" / "blendergeom.py"
TRACKED = ROOT / "assets" / "geometry" / "1_blender_depth_maps"
PRESETS = (
    "wall_pilasters",
    "floor_flagstones",
    "ceiling_coffers",
    "wall_boulders_rough",
)
CONFIRMATION = "UPDATE_TRACKED_DEPTH_BASELINE"


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("report", "verify", "adopt"),
                        default="report")
    parser.add_argument("--diagnostics-dir")
    parser.add_argument("--confirm-production-write")
    parser.add_argument("--blender", default=os.environ.get("BLENDER"))
    return parser.parse_args()


def run(command, *, env=None):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                            capture_output=True)
    if result.returncode:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(map(str, command))}\n"
            f"stdout:\n{result.stdout[-4000:]}\n"
            f"stderr:\n{result.stderr[-4000:]}"
        )
    return result


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def render(output, blender):
    command = [sys.executable, str(GENERATOR), "--out", str(output),
               "--size", "512", "--no-blend"]
    for preset in PRESETS:
        command.extend(("--preset", preset))
    env = os.environ.copy()
    if blender:
        env["BLENDER"] = blender
    run(command, env=env)


def image_data(path):
    with Image.open(path) as image:
        return image.mode, image.size, list(image.getdata())


def compare_images(left_path, right_path):
    left_mode, left_size, left = image_data(left_path)
    right_mode, right_size, right = image_data(right_path)
    if left_mode != right_mode or left_size != right_size:
        return {
            "shapeEqual": False,
            "leftMode": left_mode,
            "rightMode": right_mode,
            "leftSize": list(left_size),
            "rightSize": list(right_size),
            "changedPixels": None,
            "maximumChannelDelta": None,
            "firstDifferences": [],
        }

    changed = 0
    maximum = 0
    first = []
    for index, (old, new) in enumerate(zip(left, right)):
        if old == new:
            continue
        changed += 1
        old_values = old if isinstance(old, tuple) else (old,)
        new_values = new if isinstance(new, tuple) else (new,)
        maximum = max(maximum, max(abs(int(a) - int(b))
                                   for a, b in zip(old_values, new_values)))
        if len(first) < 20:
            first.append({
                "x": index % left_size[0],
                "y": index // left_size[0],
                "left": old,
                "right": new,
            })
    return {
        "shapeEqual": True,
        "mode": left_mode,
        "size": list(left_size),
        "changedPixels": changed,
        "maximumChannelDelta": maximum,
        "firstDifferences": first,
    }


def manifest_projection(path):
    manifest = json.loads(Path(path).read_text(encoding="utf-8"))
    by_name = {entry["preset"]: entry for entry in manifest["maps"]}
    return {
        preset: {key: by_name[preset][key]
                 for key in ("surface", "view", "tileAxes", "wrapOk")}
        for preset in PRESETS
    }


def write_visual_diff(tracked, generated, destination):
    with Image.open(tracked).convert("RGBA") as old:
        with Image.open(generated).convert("RGBA") as new:
            difference = ImageChops.difference(old, new)
            ImageEnhance.Contrast(difference).enhance(8.0).save(destination)


def adopt(run_dir, mismatches):
    manifest_path = TRACKED / "manifest.json"
    tracked_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    generated_manifest = json.loads(
        (run_dir / "manifest.json").read_text(encoding="utf-8"))
    tracked_by_name = {entry["preset"]: entry
                       for entry in tracked_manifest["maps"]}
    generated_by_name = {entry["preset"]: entry
                         for entry in generated_manifest["maps"]}
    metadata_fields = (
        "surface", "view", "tileAxes", "wrapError", "wrapOk",
        "reliefMin", "reliefMax", "contrast", "size",
    )
    for preset in mismatches:
        shutil.copy2(run_dir / f"{preset}.png", TRACKED / f"{preset}.png")
        for field in metadata_fields:
            if field in generated_by_name[preset]:
                tracked_by_name[preset][field] = generated_by_name[preset][field]
    tracked_manifest["maps"] = [tracked_by_name[item["preset"]]
                                for item in tracked_manifest["maps"]]
    manifest_path.write_text(
        json.dumps(tracked_manifest, indent=2) + "\n", encoding="utf-8")


def main():
    args = parse_args()
    if args.mode == "adopt" and args.confirm_production_write != CONFIRMATION:
        raise SystemExit(
            f"adopt mode requires --confirm-production-write {CONFIRMATION}")

    diagnostics = (Path(args.diagnostics_dir).resolve()
                   if args.diagnostics_dir else
                   Path(tempfile.gettempdir()) /
                   "second-rite-depth-baseline-diagnostics")
    if diagnostics.exists():
        shutil.rmtree(diagnostics)
    diagnostics.mkdir(parents=True)

    with tempfile.TemporaryDirectory(prefix="second-rite-depth-baseline-") as temp:
        temp = Path(temp)
        runs = []
        for index in range(3):
            output = temp / f"run-{index + 1}"
            output.mkdir()
            render(output, args.blender)
            runs.append(output)

        metadata = [manifest_projection(run_dir / "manifest.json")
                    for run_dir in runs]
        if metadata[0] != metadata[1] or metadata[1] != metadata[2]:
            raise RuntimeError("semantic depth metadata differs between runs")

        report = {
            "schemaVersion": 1,
            "purpose": "repeatability and explicit historical-baseline review",
            "runs": 3,
            "generatorSha256": sha256(GENERATOR),
            "renderDepthSha256": sha256(
                ROOT / "tools/asset-gen/blender/render_depth.py"),
            "scenesSha256": sha256(
                ROOT / "tools/asset-gen/blender/scenes.py"),
            "presets": {},
        }
        mismatches = []
        for preset in PRESETS:
            first = runs[0] / f"{preset}.png"
            second = runs[1] / f"{preset}.png"
            third = runs[2] / f"{preset}.png"
            repeat_12 = compare_images(first, second)
            repeat_23 = compare_images(second, third)
            if (not repeat_12["shapeEqual"] or
                    not repeat_23["shapeEqual"] or
                    repeat_12["changedPixels"] or
                    repeat_23["changedPixels"]):
                raise RuntimeError(f"repeatability failed for {preset}")
            print(f"{preset} repeatability: exact")

            tracked = TRACKED / f"{preset}.png"
            baseline = compare_images(tracked, first)
            candidate = diagnostics / f"{preset}.candidate.png"
            difference = diagnostics / f"{preset}.difference.png"
            shutil.copy2(first, candidate)
            write_visual_diff(tracked, first, difference)
            report["presets"][preset] = {
                "repeat1Vs2": repeat_12,
                "repeat2Vs3": repeat_23,
                "trackedVsGenerated": baseline,
                "trackedSha256": sha256(tracked),
                "generatedSha256": sha256(first),
                "metadata": metadata[0][preset],
                "candidate": candidate.name,
                "difference": difference.name,
            }
            if (not baseline["shapeEqual"] or baseline["changedPixels"]):
                mismatches.append(preset)

        report["baselineMismatches"] = mismatches
        report_path = diagnostics / "report.json"
        report_path.write_text(
            json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"diagnostics: {report_path}")

        if args.mode == "verify" and mismatches:
            raise RuntimeError(
                "tracked baseline differs for: " + ", ".join(mismatches))
        if args.mode == "adopt":
            adopt(runs[0], mismatches)
            print("tracked baseline updated: " +
                  (", ".join(mismatches) if mismatches else "no changes"))
        elif mismatches:
            print("baseline review required: " + ", ".join(mismatches))
        else:
            print("tracked baseline: exact")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
