"""Blender 5.1 script to build and export the winning 3D prop models:
- Altar Variant A -> assets/models/dungeon/dungeon_altar.obj & .mtl
- Brazier Variant B -> assets/models/dungeon/dungeon_brazier.obj & .mtl
- Sarcophagus Variant B -> assets/models/dungeon/sarcophagus.obj & .mtl
"""

import bpy
import math
import os

OUT_DIR = os.path.normpath(os.path.abspath("assets/models/dungeon"))
os.makedirs(OUT_DIR, exist_ok=True)

def reset_blend():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if "Collection" not in bpy.data.collections:
        coll = bpy.data.collections.new("Collection")
        bpy.context.scene.collection.children.link(coll)

def get_materials():
    mats = {}
    defs = {
        "stone_dark": ((0.28, 0.28, 0.30), 0.0, 0.75),
        "stone_light": ((0.45, 0.43, 0.40), 0.0, 0.70),
        "iron_dark": ((0.18, 0.20, 0.23), 0.8, 0.35),
        "bronze_gold": ((0.75, 0.58, 0.20), 0.85, 0.25),
        "coal_fire": ((0.12, 0.10, 0.08), 0.0, 0.90),
    }
    for name, (color, metallic, roughness) in defs.items():
        mat = bpy.data.materials.new(name=name)
        nodes = mat.node_tree.nodes
        bsdf = nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (*color, 1.0)
            if "Metallic" in bsdf.inputs:
                bsdf.inputs["Metallic"].default_value = metallic
            if "Roughness" in bsdf.inputs:
                bsdf.inputs["Roughness"].default_value = roughness
        mats[name] = mat
    return mats

def export_obj(obj, name):
    filepath = os.path.normpath(os.path.join(OUT_DIR, f"{name}.obj"))
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    kwargs = {
        "filepath": filepath,
        "export_selected_objects": True,
        "export_uv": True,
        "export_normals": True,
        "export_materials": True,
        "export_triangulated_mesh": True,
        "forward_axis": "NEGATIVE_Z",
        "up_axis": "Y",
    }
    bpy.ops.wm.obj_export(**kwargs)
    print(f"Successfully exported: {filepath}")

# Altar Variant A (Colonnaded Ritual Altar)
def build_altar():
    reset_blend()
    mats = get_materials()
    objs = []
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.05))
    base = bpy.context.active_object
    base.scale = (0.90, 0.50, 0.10)
    bpy.ops.object.transform_apply(scale=True)
    base.data.materials.append(mats["stone_dark"])
    objs.append(base)

    for x in (-0.35, 0.35):
        for y in (-0.16, 0.16):
            bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.06, depth=0.40, location=(x, y, 0.30))
            col = bpy.context.active_object
            col.data.materials.append(mats["stone_light"])
            objs.append(col)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.54))
    top = bpy.context.active_object
    top.scale = (0.96, 0.56, 0.10)
    bpy.ops.object.transform_apply(scale=True)
    top.data.materials.append(mats["stone_light"])
    objs.append(top)

    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.14, depth=0.03, location=(0, 0, 0.59))
    basin = bpy.context.active_object
    basin.data.materials.append(mats["bronze_gold"])
    objs.append(basin)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    base.name = "dungeon_altar"
    export_obj(base, "dungeon_altar")

# Brazier Variant B (Columnar Stone Censer)
def build_brazier():
    reset_blend()
    mats = get_materials()
    objs = []
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.24, depth=0.10, location=(0, 0, 0.05))
    base = bpy.context.active_object
    base.data.materials.append(mats["stone_dark"])
    objs.append(base)

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.15, depth=0.45, location=(0, 0, 0.32))
    pil = bpy.context.active_object
    pil.data.materials.append(mats["stone_light"])
    objs.append(pil)

    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.25, depth=0.14, location=(0, 0, 0.61))
    bowl = bpy.context.active_object
    bowl.data.materials.append(mats["bronze_gold"])
    objs.append(bowl)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    base.name = "dungeon_brazier"
    export_obj(base, "dungeon_brazier")

# Sarcophagus Variant B (Reliquary Panel Tomb)
def build_sarcophagus():
    reset_blend()
    mats = get_materials()
    objs = []
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.05))
    base = bpy.context.active_object
    base.scale = (1.24, 0.62, 0.10)
    bpy.ops.object.transform_apply(scale=True)
    base.data.materials.append(mats["stone_dark"])
    objs.append(base)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.26))
    body = bpy.context.active_object
    body.scale = (1.18, 0.56, 0.32)
    bpy.ops.object.transform_apply(scale=True)
    body.data.materials.append(mats["stone_dark"])
    objs.append(body)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.46))
    lid = bpy.context.active_object
    lid.scale = (1.20, 0.58, 0.08)
    bpy.ops.object.transform_apply(scale=True)
    lid.data.materials.append(mats["stone_light"])
    objs.append(lid)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    base.name = "sarcophagus"
    export_obj(base, "sarcophagus")

def main():
    build_altar()
    build_brazier()
    build_sarcophagus()
    print("Winning props exported successfully!")

if __name__ == "__main__":
    main()
