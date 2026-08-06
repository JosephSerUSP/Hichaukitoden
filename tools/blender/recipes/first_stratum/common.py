"""Small deterministic modeling helpers shared by First Stratum recipes."""
from __future__ import annotations


def material(core, semantic_id):
    return core.make_material(f"sr_{semantic_id}", semantic_id=semantic_id)


def box(name, parent, size, location, material_value, core, *, rotation=(0, 0, 0), bevel=0.0):
    import bpy
    sx, sy, sz = (float(value) for value in size)
    vertices = [
        (-sx / 2, -sy / 2, -sz / 2), (sx / 2, -sy / 2, -sz / 2),
        (sx / 2, sy / 2, -sz / 2), (-sx / 2, sy / 2, -sz / 2),
        (-sx / 2, -sy / 2, sz / 2), (sx / 2, -sy / 2, sz / 2),
        (sx / 2, sy / 2, sz / 2), (-sx / 2, sy / 2, sz / 2),
    ]
    faces = [
        (0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
        (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7),
    ]
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    core.parent_local(obj, parent, loc=location, rot=rotation)
    core.assign_material(obj, material_value)
    core.flat_shade(obj)
    core.add_bevel_modifier(obj, width=float(bevel), segments=1)
    return obj


def empty(name, parent, location, core, *, rotation=(0, 0, 0), socket_kind=None):
    import bpy
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    core.parent_local(obj, parent, loc=location, rot=rotation)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.05
    if socket_kind:
        obj["sr_socket_kind"] = socket_kind
    return obj


def socket_row(name, kind, location):
    return {"name": name, "kind": kind, "location": [round(float(v), 6) for v in location]}
