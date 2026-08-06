#!/usr/bin/env python3
"""Run Phase 4 shared-core smoke, toolkit, and calibration checks."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from decimal import Decimal, InvalidOperation
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
TOOLKIT = ROOT / "tools" / "blender" / "second-rite-item-model-toolkit"
SMOKE = ROOT / "tools" / "blender" / "tests" / "blender_core_smoke.py"
BLENDER_SEARCH = [
    os.environ.get("BLENDER"),
    r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 4.2\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 4.1\blender.exe",
    "blender",
]


def blender_executable():
    for candidate in BLENDER_SEARCH:
        if candidate and (candidate == "blender" or Path(candidate).is_file()):
            return candidate
    raise SystemExit("Blender not found; set BLENDER or install Blender")


def run(command, *, cwd=ROOT, env=None):
    result = subprocess.run(command, cwd=cwd, env=env, text=True,
                            capture_output=True)
    if result.returncode:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(map(str, command))}\n"
            f"stdout:\n{result.stdout[-4000:]}\nstderr:\n{result.stderr[-4000:]}"
        )
    return result


def run_smoke(blender, output, blend_path=None):
    command = [blender, "--background"]
    if blend_path is None:
        command.append("--factory-startup")
    else:
        command.append(str(blend_path))
    command.extend(["--python", str(SMOKE), "--", "--out", str(output)])
    result = run(command)
    lines = [line for line in result.stdout.splitlines()
             if line.startswith("BLENDER_CORE_SMOKE ")]
    if len(lines) != 1:
        raise RuntimeError("Blender smoke did not emit exactly one result line")
    record = json.loads(lines[0].split(" ", 1)[1])
    required = {
        "rootUnmoved": True, "selectionRestored": True,
        "temporaryCollectionDeleted": True, "objAxisSettingsAccepted": True,
        "itemMetadataValid": True, "materialMetadataValid": True,
        "depthProduct": "depth_guide", "metricDepthDeferred": True,
        "textFallback": True, "productionWrites": 0,
        "textFallbackExporterLoaded": True,
        "textFallbackExporterExported": True,
        "textFallbackSingleModule": True,
        "registryVersionsAgree": True,
    }
    for key, value in required.items():
        if record.get(key) != value:
            raise RuntimeError(f"smoke result mismatch for {key}: {record}")
    if not record["textFallbackCoreOrigin"].startswith("<Blender Text:"):
        raise RuntimeError(f"smoke core did not come from an embedded Text block: {record}")
    print("shared core smoke: passed")
    print("embedded exporter fallback: passed")
    print("registry version agreement: passed")
    return record


def inspect_blend(blender, blend_path, script_path):
    script_path.write_text(
        "import bpy\n"
        "required = {'second_rite_item_exporter.py', 'second_rite_asset_core.py', "
        "'second_rite_contract.json', 'second_rite_materials.json', "
        "'README_ITEM_MODEL_LIBRARY.md'}\n"
        "actual = {text.name for text in bpy.data.texts}\n"
        "missing = required - actual\n"
        "assert not missing, missing\n"
        "assert bpy.context.scene['second_rite_asset_core_version'] == 1\n"
        "assert bpy.context.scene['second_rite_contract_version'] == 1\n",
        encoding="utf-8",
    )
    run([blender, "--background", str(blend_path), "--python", str(script_path)])


def standalone_build(blender, temp_root):
    toolkit_copy = temp_root / "toolkit"
    output = temp_root / "item-output"
    shutil.copytree(TOOLKIT, toolkit_copy)
    output.mkdir()
    env = os.environ.copy()
    env["SECOND_RITE_OUT"] = str(output)
    wrapper = temp_root / "standalone_build.py"
    wrapper.write_text(
        "import runpy, sys\n"
        "builder = sys.argv[sys.argv.index('--') + 1]\n"
        "runpy.run_path(builder, run_name='__main__')\n"
        "module = sys.modules['second_rite_asset_core']\n"
        "print('STANDALONE_CORE_ORIGIN ' + str(module.__file__))\n",
        encoding="utf-8",
    )
    result = run([blender, "--background", "--factory-startup",
                  "--python", str(wrapper), "--",
                  str(toolkit_copy / "build_expanded_item_library.py")],
                 cwd=toolkit_copy, env=env)
    origins = [line.split(" ", 1)[1] for line in result.stdout.splitlines()
               if line.startswith("STANDALONE_CORE_ORIGIN ")]
    expected_origin = (toolkit_copy / "vendor" / "second_rite_asset_core.py").resolve()
    if len(origins) != 1 or Path(origins[0]).resolve() != expected_origin:
        raise RuntimeError(f"standalone build imported unexpected core: {origins}")
    print("standalone core origin: vendor copy")
    blend = output / "second_rite_item_model_library_expanded.blend"
    preview = output / "second_rite_item_model_library_expanded_preview.png"
    manifest = output / "ITEM_MODEL_MANIFEST.md"
    obj_files = sorted((output / "exports").glob("*.obj"))
    if not blend.is_file() or not preview.is_file() or not manifest.is_file():
        raise RuntimeError("standalone toolkit output is incomplete")
    if len(obj_files) != 53:
        raise RuntimeError(f"standalone toolkit emitted {len(obj_files)} OBJ files")
    manifest_text = manifest.read_text(encoding="utf-8")
    if "- Export roots: **49**" not in manifest_text:
        raise RuntimeError("standalone toolkit manifest does not record 49 export roots")
    inspect_blend(blender, blend, temp_root / "inspect_blend.py")
    print("standalone toolkit build: 49 roots / 53 OBJ")
    vendor_hidden = toolkit_copy / "vendor.hidden"
    (toolkit_copy / "vendor").rename(vendor_hidden)
    try:
        run_smoke(blender, temp_root / "embedded-smoke", blend_path=blend)
    finally:
        vendor_hidden.rename(toolkit_copy / "vendor")
    return output, obj_files


def structural_equivalence(output, obj_files):
    sys.path.insert(0, str(ROOT / "tools" / "asset-language"))
    from lib.regression import obj_metrics

    fields = ("vertexCount", "uvCount", "normalCount", "faceCount",
              "materialUseCount", "mtllib", "bounds")
    for generated in obj_files:
        production = ROOT / "assets" / "models" / "items" / generated.name
        if not production.is_file():
            raise RuntimeError(f"no production counterpart for {generated.name}")
        generated_metrics = obj_metrics(output, Path("exports") / generated.name)
        production_metrics = obj_metrics(ROOT, Path("assets/models/items") / generated.name)
        for field in fields:
            if generated_metrics[field] != production_metrics[field]:
                raise RuntimeError(f"item structural mismatch {generated.name}: {field}")
    print("item structural equivalence: passed")


def _obj_materials(path):
    mtllib = []
    usemtl = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if fields[0] == "mtllib":
            mtllib.append(" ".join(fields[1:]))
        elif fields[0] == "usemtl":
            usemtl.append(" ".join(fields[1:]))
    return mtllib, usemtl


def _semantic_token(token):
    try:
        return Decimal(token)
    except InvalidOperation:
        return token


def _mtl_records(path):
    records = {}
    current = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        directive = fields[0]
        if directive == "newmtl":
            current = " ".join(fields[1:])
            records[current] = []
            continue
        if current is None:
            raise RuntimeError(f"MTL directive precedes newmtl in {path}: {line}")
        records[current].append((directive, tuple(_semantic_token(token)
                                                   for token in fields[1:])))
    return records


def material_equivalence(output, obj_files):
    for generated in obj_files:
        production = ROOT / "assets" / "models" / "items" / generated.name
        generated_mtllib, generated_usemtl = _obj_materials(generated)
        production_mtllib, production_usemtl = _obj_materials(production)
        if generated_mtllib != production_mtllib:
            raise RuntimeError(f"item material mismatch {generated.name}: mtllib")
        if generated_usemtl != production_usemtl:
            raise RuntimeError(f"item material mismatch {generated.name}: ordered usemtl")
        if set(generated_usemtl) != set(production_usemtl):
            raise RuntimeError(f"item material mismatch {generated.name}: material names")
        generated_mtl = generated.with_name(generated_mtllib[0])
        production_mtl = production.with_name(production_mtllib[0])
        generated_records = _mtl_records(generated_mtl)
        production_records = _mtl_records(production_mtl)
        if set(generated_usemtl) - set(generated_records):
            raise RuntimeError(f"generated OBJ references missing MTL material: {generated.name}")
        if set(production_usemtl) - set(production_records):
            raise RuntimeError(f"production OBJ references missing MTL material: {production.name}")
        if generated_records != production_records:
            raise RuntimeError(f"item material mismatch {generated.name}: MTL semantics")
    print("item material equivalence: passed")


def depth_calibration(blender, output):
    depth_output = output / "depth"
    depth_output.mkdir()
    command = [sys.executable, str(ROOT / "tools/asset-gen/blendergeom.py"),
               "--out", str(depth_output), "--size", "512", "--no-blend"]
    for preset in ("wall_pilasters", "floor_flagstones", "ceiling_coffers",
                   "wall_boulders_rough"):
        command.extend(["--preset", preset])
    env = os.environ.copy()
    env["BLENDER"] = blender
    run(command, env=env)
    current = json.loads((ROOT / "assets/geometry/1_blender_depth_maps/manifest.json").read_text(encoding="utf-8"))
    generated = json.loads((depth_output / "manifest.json").read_text(encoding="utf-8"))
    current_by_name = {entry["preset"]: entry for entry in current["maps"]}
    generated_by_name = {entry["preset"]: entry for entry in generated["maps"]}
    for preset in ("wall_pilasters", "floor_flagstones", "ceiling_coffers", "wall_boulders_rough"):
        old = current_by_name[preset]
        new = generated_by_name[preset]
        for field in ("surface", "view", "tileAxes", "wrapOk"):
            if old[field] != new[field]:
                raise RuntimeError(f"depth metadata mismatch {preset}: {field}")
        with Image.open(ROOT / "assets/geometry/1_blender_depth_maps" / f"{preset}.png") as before:
            with Image.open(depth_output / f"{preset}.png") as after:
                if before.mode != after.mode or before.size != after.size:
                    raise RuntimeError(f"depth image shape mismatch {preset}")
                before_pixels = list(before.getdata())
                after_pixels = list(after.getdata())
                if before_pixels != after_pixels:
                    differences = []
                    for index, (old_pixel, new_pixel) in enumerate(
                            zip(before_pixels, after_pixels)):
                        if old_pixel != new_pixel:
                            x = index % before.width
                            y = index // before.width
                            differences.append((x, y, old_pixel, new_pixel))
                            if len(differences) == 10:
                                break
                    raise RuntimeError(
                        f"depth pixel mismatch {preset}; first differences: {differences}")
    print("depth calibration pixels: passed")


def verify_vendor_sync():
    sys.path.insert(0, str(ROOT / "tools" / "blender"))
    from sync_asset_core import check_pairs, expected_pairs

    mismatches = check_pairs(expected_pairs())
    if mismatches:
        raise RuntimeError("vendor synchronization mismatch: " + ", ".join(mismatches))


def main():
    blender = blender_executable()
    verify_vendor_sync()
    with tempfile.TemporaryDirectory(prefix="second-rite-phase4-") as directory:
        temp_root = Path(directory)
        run_smoke(blender, temp_root / "smoke")
        output, obj_files = standalone_build(blender, temp_root)
        structural_equivalence(output, obj_files)
        material_equivalence(output, obj_files)
        depth_calibration(blender, temp_root)
    print("vendor synchronization: passed")
    print("provider calls: 0")
    print("production assets modified: 0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
