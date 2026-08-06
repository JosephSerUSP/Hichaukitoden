"""Blender inspection adapter for the shared Second Rite census mesh recipe.

The direct compiler and Blender consume the same backend-neutral geometry. Faces
are grouped by semantic material so inspection remains practical; Blender does
not re-model or reinterpret the catalogue.
"""
from __future__ import annotations

import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tools" / "asset-production"))
import mesh_recipe  # noqa: E402


def _material_mesh(result, semantic_id):
    source_faces = [indices for indices, material in result.faces if material == semantic_id]
    used = sorted({index for face in source_faces for index in face})
    remap = {old: new for new, old in enumerate(used)}
    vertices = [result.vertices[index] for index in used]
    faces = [tuple(remap[index] for index in face) for face in source_faces]
    return vertices, faces


def build(*, root, asset, state, core):
    result = mesh_recipe.make_model(asset, state)
    for semantic_id in sorted({material for _, material in result.faces}):
        vertices, faces = _material_mesh(result, semantic_id)
        mesh = bpy.data.meshes.new(f"{asset['id']}_{state}_{semantic_id}_mesh")
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        obj = bpy.data.objects.new(f"part_{semantic_id}", mesh)
        bpy.context.scene.collection.objects.link(obj)
        core.parent_local(obj, root)
        material = core.make_material(f"sr_{semantic_id}", semantic_id=semantic_id)
        core.assign_material(obj, material)
        core.flat_shade(obj)

    for socket in result.sockets:
        obj = bpy.data.objects.new(socket["name"], None)
        bpy.context.scene.collection.objects.link(obj)
        core.parent_local(obj, root, loc=socket["location"])
        obj["sr_socket_kind"] = socket["kind"]

    return {"materials": asset["materials"], "sockets": result.sockets}
