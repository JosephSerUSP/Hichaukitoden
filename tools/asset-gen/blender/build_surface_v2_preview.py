#!/usr/bin/env python3
"""Build a Blender inspection mesh/render from a V2 surface baseline recipe.

Run with Blender, for example:

    blender --background --factory-startup --python \
      tools/asset-gen/blender/build_surface_v2_preview.py -- \
      --asset wall_ritual_pilasters --out-dir /tmp/surface-preview

The preview is a derivative. The canonical field and PNGs are produced by
``surface_baselines_v2.py`` without Blender.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
GENERATOR_PATH = ROOT / "tools" / "asset-gen" / "surface_baselines_v2.py"
CORE_DIR = ROOT / "tools" / "blender"
if str(CORE_DIR) not in sys.path:
    sys.path.insert(0, str(CORE_DIR))
import second_rite_asset_core as asset_core  # noqa: E402


def load_generator():
    spec = importlib.util.spec_from_file_location("second_rite_surface_v2", GENERATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load generator from {GENERATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def parse_args() -> argparse.Namespace:
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", required=True)
    parser.add_argument("--baseline-root", type=Path,
                        default=ROOT / "assets" / "geometry" / "2_procedural_surface_baselines")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--mesh-size", type=int, default=65)
    parser.add_argument("--render-size", type=int, default=768)
    return parser.parse_args(values)


def sample_indices(source_size: int, mesh_size: int) -> list[int]:
    if mesh_size < 3 or mesh_size > source_size:
        raise ValueError("mesh-size must be between 3 and source size")
    return [round(index * (source_size - 1) / (mesh_size - 1))
            for index in range(mesh_size)]


def make_mesh(name: str, field: list[int], source_size: int, mesh_size: int,
              range_cells: float):
    indices = sample_indices(source_size, mesh_size)
    vertices = []
    faces = []
    for row, source_y in enumerate(indices):
        y = row / (mesh_size - 1) - 0.5
        for column, source_x in enumerate(indices):
            x = column / (mesh_size - 1) - 0.5
            value = field[source_y * source_size + source_x]
            z = value / 32767.0 * range_cells
            vertices.append((x, y, z))
    for row in range(mesh_size - 1):
        for column in range(mesh_size - 1):
            a = row * mesh_size + column
            b = a + 1
            c = a + mesh_size + 1
            d = a + mesh_size
            faces.append((a, b, c, d))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def aim_at(obj, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def configure_scene(obj, metadata: dict, output_dir: Path, render_size: int) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = render_size
    scene.render.resolution_y = render_size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False

    world = scene.world or bpy.data.worlds.new("SecondRitePreviewWorld")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background:
        background.inputs["Color"].default_value = (0.018, 0.017, 0.015, 1.0)
        background.inputs["Strength"].default_value = 0.35

    material = asset_core.make_material(
        "SurfacePreviewMaterial",
        semantic_id=metadata["materialId"],
        roughness=0.92,
        metallic=0.0,
    )
    asset_core.assign_material(obj, material)
    asset_core.flat_shade(obj)

    bpy.ops.object.light_add(type="AREA", location=(-1.5, -1.8, 2.6))
    key = bpy.context.object
    key.name = "PreviewKey"
    key.data.energy = 700
    key.data.shape = "DISK"
    key.data.size = 2.2
    aim_at(key, Vector((0.0, 0.0, 0.0)))

    bpy.ops.object.light_add(type="AREA", location=(1.8, 0.8, 1.2))
    fill = bpy.context.object
    fill.name = "PreviewFill"
    fill.data.energy = 210
    fill.data.size = 2.8
    aim_at(fill, Vector((0.0, 0.0, 0.0)))

    bpy.ops.object.camera_add(location=(1.35, -1.55, 1.25))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.42
    aim_at(camera, Vector((0.0, 0.0, 0.0)))
    scene.camera = camera

    output_dir.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(output_dir / "blender_preview.png")


def main() -> None:
    args = parse_args()
    generator = load_generator()
    if args.asset not in generator.RECIPES:
        raise SystemExit(f"unknown V2 surface baseline: {args.asset}")
    baseline_dir = args.baseline_root / args.asset
    metadata_path = baseline_dir / "baseline.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    recipe, field = generator.build_field(args.asset, metadata["size"])
    actual_hash = generator.sha256(generator.field_bytes(field))
    expected_hash = metadata["hashes"]["fieldQ15LeSha256"]
    if actual_hash != expected_hash:
        raise RuntimeError(
            f"recipe field hash differs from baseline: expected {expected_hash}, got {actual_hash}")

    asset_core.reset_scene(factory=True)
    obj = make_mesh(
        args.asset,
        field,
        metadata["size"],
        min(args.mesh_size, metadata["size"]),
        metadata["rangeCells"],
    )
    asset_core.tag_asset_target(
        obj,
        asset_id=recipe.asset_id,
        representation="plane",
        role="surface_material",
        authoring_space="depth_tile",
        placement_frame="surface_domain",
        states=["default"],
        variants=[],
        extra={
            "sr_surface": metadata["surface"],
            "sr_tile_axes": metadata["tileAxes"],
            "sr_baseline_schema_version": metadata["schemaVersion"],
            "sr_recipe_version": metadata["recipeVersion"],
            "sr_field_q15_sha256": expected_hash,
            "sr_range_cells": metadata["rangeCells"],
            "sr_preview_only": True,
        },
    )
    configure_scene(obj, metadata, args.out_dir, args.render_size)
    blend_path = args.out_dir / f"{args.asset}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.render.render(write_still=True)
    print("SURFACE_V2_PREVIEW " + json.dumps({
        "assetId": args.asset,
        "blend": str(blend_path),
        "render": str(args.out_dir / "blender_preview.png"),
        "fieldQ15LeSha256": expected_hash,
        "meshVertices": len(obj.data.vertices),
        "meshFaces": len(obj.data.polygons),
        "canonical": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
