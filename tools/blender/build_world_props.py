"""Blender-side staged builder for deterministic Second Rite world props."""
from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils import Vector

SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]
sys.path.insert(0, str(ROOT / "tools" / "asset-production"))
sys.path.insert(0, str(ROOT / "tools" / "blender"))

import asset_set as production  # noqa: E402
import second_rite_asset_core as core  # noqa: E402


def _arguments():
    raw = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--set", required=True)
    parser.add_argument("--asset", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--state", action="append", default=[])
    return parser.parse_args(raw)


def _sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _descendants(root):
    ordered = []
    pending = list(root.children)
    while pending:
        obj = pending.pop(0)
        ordered.append(obj)
        pending[0:0] = list(obj.children)
    return ordered


def _bounds(root):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in _descendants(root):
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        points.extend(evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    if not points:
        return {"min": [0, 0, 0], "max": [0, 0, 0], "size": [0, 0, 0]}
    minimum = [min(point[i] for point in points) for i in range(3)]
    maximum = [max(point[i] for point in points) for i in range(3)]
    size = [maximum[i] - minimum[i] for i in range(3)]
    return {key: [round(float(value), 6) for value in values]
            for key, values in (("min", minimum), ("max", maximum), ("size", size))}


def _relative(path):
    return production.relative_posix(Path(path), root=ROOT)


def _source_commit():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
            stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        return os.environ.get("GIT_COMMIT")


def _assert_staging_path(path):
    resolved = Path(path).resolve()
    assets = (ROOT / "assets").resolve()
    if resolved == assets or assets in resolved.parents:
        raise RuntimeError("world-prop builds must stage outside assets/; promotion is explicit")
    return resolved


def _build_state(asset_set_data, asset, state, out_root):
    core.reset_scene()
    root = bpy.data.objects.new(asset["id"], None)
    bpy.context.scene.collection.objects.link(root)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.12
    export_name = asset["id"] if len(asset["states"]) == 1 else f"{asset['id']}_{state}"
    root["item_export_name"] = export_name
    core.tag_asset_target(
        root,
        asset_id=asset["id"], representation=asset["representation"],
        role=asset["role"], authoring_space=asset["authoringSpace"],
        placement_frame=asset["placementFrame"], states=asset["states"],
        default_state=asset["defaultState"], variants=asset["variants"],
        extra={"sr_current_state": state, "sr_recipe": asset["recipe"]},
    )
    recipe = importlib.import_module(asset["recipe"])
    result = recipe.build(root=root, asset=asset, state=state, core=core) or {}
    core.validate_asset_metadata(root)
    bpy.context.view_layer.update()
    bounds = _bounds(root)
    state_dir = out_root / asset["id"] / state
    state_dir.mkdir(parents=True, exist_ok=True)
    outputs = [Path(path) for path in core.export_asset_root(
        bpy.context, root, state_dir, center_mode="PIVOT"
    )]
    blend_path = state_dir / f"{export_name}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    outputs.append(blend_path)
    for mtl in sorted(state_dir.glob("*.mtl")):
        if mtl not in outputs:
            outputs.append(mtl)
    return {
        "state": state,
        "boundsWorldCell": bounds,
        "materials": result.get("materials", asset["materials"]),
        "sockets": result.get("sockets", []),
        "outputs": [
            {"path": _relative(path), "sha256": _sha256(path)} for path in outputs
        ],
    }


def main():
    args = _arguments()
    out_root = _assert_staging_path(args.out_dir)
    asset_set_data = production.load_asset_set(args.set, root=ROOT, check_files=True)
    asset = production.get_asset(asset_set_data, args.asset, kind="world_prop")
    selected = args.state or asset["states"]
    unknown = sorted(set(selected) - set(asset["states"]))
    if unknown:
        raise SystemExit(f"unknown state(s): {', '.join(unknown)}")
    rows = [_build_state(asset_set_data, asset, state, out_root) for state in selected]
    recipe_path = ROOT / "tools" / "blender" / Path(*asset["recipe"].split(".")).with_suffix(".py")
    report = {
        "manifestKind": "second_rite_world_prop_build",
        "manifestVersion": 1,
        "assetSet": asset_set_data["id"],
        "assetId": asset["id"],
        "contractVersion": asset_set_data["contractVersion"],
        "sourceRecord": _relative(asset_set_data["_path"]),
        "sourceCommit": _source_commit(),
        "recipe": {"module": asset["recipe"], "path": _relative(recipe_path),
                   "sha256": _sha256(recipe_path)},
        "command": sys.argv,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "intendedProducts": asset["products"],
        "states": rows,
    }
    report_path = out_root / asset["id"] / "build.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"kind": report["manifestKind"], "assetId": asset["id"],
                      "report": _relative(report_path)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
