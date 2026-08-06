"""Run the shared Blender core smoke checks inside Blender."""

import builtins
import json
import os
import sys
import types
from pathlib import Path

import bmesh
import bpy


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "blender"))
import second_rite_asset_core as core


def parse_output():
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(values) != 2 or values[0] != "--out":
        raise SystemExit("usage: blender_core_smoke.py -- --out TEMP_DIR")
    output = Path(values[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    return output


def text_fallback_check():
    bpy.data.texts.new("second_rite_contract.json").write(
        (ROOT / "tools/asset-language/contract.json").read_text(encoding="utf-8"))
    bpy.data.texts.new("second_rite_materials.json").write(
        (ROOT / "tools/asset-language/materials.json").read_text(encoding="utf-8"))
    bpy.data.texts.new("second_rite_asset_core.py").write(
        (ROOT / "tools/blender/second_rite_asset_core.py").read_text(encoding="utf-8"))

    original_import = builtins.__import__

    def blocked_import(name, *args, **kwargs):
        if name == "second_rite_asset_core":
            raise ImportError("filesystem import intentionally disabled")
        return original_import(name, *args, **kwargs)

    sys.modules.pop("second_rite_asset_core", None)
    original_path = sys.path[:]
    try:
        sys.path[:] = [entry for entry in sys.path if "tools\\blender" not in entry.lower() and "tools/blender" not in entry.lower()]
        builtins.__import__ = blocked_import
        module = types.ModuleType("second_rite_asset_core")
        module.__file__ = "<Blender Text: second_rite_asset_core.py>"
        sys.modules["second_rite_asset_core"] = module
        text = bpy.data.texts["second_rite_asset_core.py"]
        exec(compile(text.as_string(), module.__file__, "exec"), module.__dict__)
        assert module.CORE_VERSION == 1
        assert module.load_contract()["contractVersion"] == 1
        return True
    finally:
        builtins.__import__ = original_import
        sys.path[:] = original_path


def main():
    output = parse_output()
    core.load_contract()
    core.load_material_registry()
    assert core.CORE_VERSION == 1

    core.reset_scene(factory=True)
    scene = bpy.context.scene
    root = bpy.data.objects.new("SmokeItem", None)
    root.location = (2.0, 3.0, 4.0)
    bpy.context.collection.objects.link(root)
    core.tag_asset_target(
        root,
        asset_id="smoke_item",
        representation="full_model",
        role="item_display",
        authoring_space="item_display",
        placement_frame="item_viewport",
        states=["default"],
        variants=[],
    )
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    child = bpy.context.object
    child.name = "SmokeGeometry"
    core.parent_local(child, root, loc=(0.25, 0.0, 0.0))
    material = core.make_material(
        "SmokeBone", semantic_id="bone", color=(0.72, 0.67, 0.53),
        metallic=0.05, roughness=0.75,
    )
    core.assign_material(child, material)
    core.flat_shade(child)
    core.add_bevel_modifier(child, 0.01, 1)
    core.validate_asset_metadata(root)

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    authored_location = tuple(root.location)
    exported = core.export_asset_root(bpy.context, root, output, center_mode="PIVOT")
    assert len(exported) == 1
    obj_path = Path(exported[0])
    assert obj_path.is_file()
    assert obj_path.with_suffix(".mtl").is_file()
    assert tuple(root.location) == authored_location
    assert root.select_get() and bpy.context.view_layer.objects.active == root
    assert bpy.data.collections.get("__SECOND_RITE_ITEM_EXPORT_TEMP__") is None
    assert material["sr_material_id"] == "bone"

    core.reset_scene(factory=True)
    scene = bpy.context.scene
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=0.5)
    core.mesh_object_from_bmesh("SmokeDepthFixture", bm)
    core.tag_asset_target(
        scene,
        asset_id="smoke_depth",
        representation="plane",
        role="surface_material",
        authoring_space="depth_tile",
        placement_frame="surface_domain",
        states=["default"],
        variants=[],
        extra={
            "sr_surface": "wall", "sr_view": "above", "sr_tile_axes": "x",
            "sr_depth_product": "depth_guide",
            "sr_metric_depth_deferred": True,
            "sr_default_metric_range_cells": 0.25,
        },
    )
    assert scene["sr_depth_product"] == "depth_guide"
    assert scene["sr_metric_depth_deferred"] is True
    fallback = text_fallback_check()

    print("BLENDER_CORE_SMOKE " + json.dumps({
        "coreVersion": core.CORE_VERSION,
        "contractVersion": core.contract_value("contractVersion"),
        "obj": obj_path.name,
        "mtl": obj_path.with_suffix(".mtl").name,
        "rootUnmoved": True,
        "selectionRestored": True,
        "temporaryCollectionDeleted": True,
        "objAxisSettingsAccepted": True,
        "itemMetadataValid": True,
        "materialMetadataValid": True,
        "depthProduct": scene["sr_depth_product"],
        "metricDepthDeferred": scene["sr_metric_depth_deferred"],
        "textFallback": fallback,
        "productionWrites": 0,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
