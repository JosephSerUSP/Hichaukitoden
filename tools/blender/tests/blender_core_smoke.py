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
    def ensure_text(name, content):
        text = bpy.data.texts.get(name)
        if text is None:
            text = bpy.data.texts.new(name)
            text.write(content)
        return text

    exporter_text = ensure_text(
        "second_rite_item_exporter.py",
        (ROOT / "tools/blender/second-rite-item-model-toolkit/"
         "second_rite_item_exporter.py").read_text(encoding="utf-8"))
    ensure_text("second_rite_contract.json",
                (ROOT / "tools/asset-language/contract.json").read_text(encoding="utf-8"))
    ensure_text("second_rite_materials.json",
                (ROOT / "tools/asset-language/materials.json").read_text(encoding="utf-8"))
    ensure_text("second_rite_asset_core.py",
                (ROOT / "tools/blender/second_rite_asset_core.py").read_text(encoding="utf-8"))

    original_import = builtins.__import__
    original_path = sys.path[:]

    def blocked_import(name, *args, **kwargs):
        if name == "second_rite_asset_core":
            raise ImportError("filesystem import intentionally disabled")
        return original_import(name, *args, **kwargs)

    sys.modules.pop("second_rite_asset_core", None)
    sys.modules.pop("second_rite_item_exporter", None)
    try:
        blocked_paths = {
            str((ROOT / "tools/blender").resolve()).lower(),
            str((ROOT / "tools/blender/second-rite-item-model-toolkit/vendor").resolve()).lower(),
        }
        sys.path[:] = [entry for entry in sys.path
                       if str(Path(entry or ".").resolve()).lower() not in blocked_paths]
        builtins.__import__ = blocked_import
        exporter = types.ModuleType("second_rite_item_exporter")
        exporter.__dict__.pop("__file__", None)
        sys.modules["second_rite_item_exporter"] = exporter
        exec(compile(exporter_text.as_string(),
                     "<Blender Text: second_rite_item_exporter.py>", "exec"),
             exporter.__dict__)
        fallback_core = sys.modules.get("second_rite_asset_core")
        assert fallback_core is exporter.asset_core
        assert fallback_core is not None
        assert fallback_core.__file__ == "<Blender Text: second_rite_asset_core.py>"
        assert list(module for module in sys.modules.values()
                     if module is fallback_core).count(fallback_core) == 1
        assert fallback_core.CORE_VERSION == 1
        assert fallback_core.load_contract()["contractVersion"] == 1
        assert fallback_core.load_material_registry()["version"] == 1

        fallback_core.reset_scene(factory=True)
        exporter.register()
        root = bpy.data.objects.new("FallbackItem", None)
        root["item_export"] = True
        root["item_export_name"] = "fallback_item"
        bpy.context.collection.objects.link(root)
        fallback_core.tag_asset_target(
            root,
            asset_id="fallback_item",
            representation="full_model",
            role="item_display",
            authoring_space="item_display",
            placement_frame="item_viewport",
            states=["default"], variants=[],
        )
        bpy.ops.mesh.primitive_cube_add(size=0.5)
        child = bpy.context.object
        fallback_core.parent_local(child, root)
        fallback_core.assign_material(
            child, fallback_core.make_material(
                "FallbackBone", semantic_id="bone",
                color=(0.72, 0.67, 0.53), metallic=0.05, roughness=0.75))
        export_dir = Path(sys.argv[sys.argv.index("--") + 2]) / "text-fallback"
        outputs = exporter.export_item_root(
            bpy.context, root, export_dir, center_mode="PIVOT")
        assert len(outputs) == 1
        obj_path = Path(outputs[0])
        assert obj_path.is_file() and obj_path.with_suffix(".mtl").is_file()
        exporter.unregister()
        return {
            "textFallbackExporterLoaded": True,
            "textFallbackExporterExported": True,
            "textFallbackCoreOrigin": fallback_core.__file__,
            "textFallbackSingleModule": True,
            "registryVersionsAgree": True,
        }
    finally:
        builtins.__import__ = original_import
        sys.path[:] = original_path
        sys.modules.pop("second_rite_item_exporter", None)


def main():
    output = parse_output()
    core.load_contract()
    core.load_material_registry()
    assert core.CORE_VERSION == 1

    core.reset_scene(factory=bpy.data.texts.get("second_rite_asset_core.py") is None)
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

    core.reset_scene(factory=False)
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
    depth_product = scene["sr_depth_product"]
    metric_depth_deferred = scene["sr_metric_depth_deferred"]
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
        "depthProduct": depth_product,
        "metricDepthDeferred": metric_depth_deferred,
        "textFallback": True,
        **fallback,
        "productionWrites": 0,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
