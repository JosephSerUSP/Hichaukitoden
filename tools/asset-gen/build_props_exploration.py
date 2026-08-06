"""Blender 5.1 script for exploratory dungeon prop generation.
Generates 3 distinct design variants for:
1. Altar (Colonnaded, Octagonal Reliquary, Monolithic Slab)
2. Brazier (Wrought Iron Tripod, Columnar Stone Censer, Heavy Square Cage)
3. Sarcophagus (Gothic Vault Sepulchre, Relief Panel Tomb, Monolithic Coffin)

Exports OBJ+MTL models and renders side-by-side comparison sheets.

Run via Blender:
  & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background --python tools/asset-gen/build_props_exploration.py
"""

import bpy
import math
import os
from mathutils import Vector, Euler

OUT_DIR = os.path.abspath("assets/models/dungeon")
PREVIEW_DIR = os.path.abspath("tools/asset-gen/out")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)

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

def export_obj(obj, filepath):
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
    print(f"Exported OBJ: {filepath}")

# ==========================================
# 1. ALTAR VARIANTS
# ==========================================

def build_altar_a():
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
    base.name = "dungeon_altar_variant_a"
    export_obj(base, f"{OUT_DIR}/dungeon_altar_variant_a.obj")
    return base

def build_altar_b():
    reset_blend()
    mats = get_materials()
    objs = []
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.42, depth=0.12, location=(0, 0, 0.06))
    ped = bpy.context.active_object
    ped.data.materials.append(mats["stone_dark"])
    objs.append(ped)

    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.36, depth=0.40, location=(0, 0, 0.32))
    body = bpy.context.active_object
    body.data.materials.append(mats["stone_dark"])
    objs.append(body)

    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.46, depth=0.10, location=(0, 0, 0.57))
    top = bpy.context.active_object
    top.data.materials.append(mats["stone_light"])
    objs.append(top)

    for i in range(8):
        angle = i * (math.pi / 4)
        x = 0.44 * math.cos(angle)
        y = 0.44 * math.sin(angle)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.57))
        corner = bpy.context.active_object
        corner.scale = (0.04, 0.04, 0.11)
        bpy.ops.object.transform_apply(scale=True)
        corner.data.materials.append(mats["bronze_gold"])
        objs.append(corner)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = ped
    bpy.ops.object.join()
    ped.name = "dungeon_altar_variant_b"
    export_obj(ped, f"{OUT_DIR}/dungeon_altar_variant_b.obj")
    return ped

def build_altar_c():
    reset_blend()
    mats = get_materials()
    objs = []
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.28))
    block = bpy.context.active_object
    block.scale = (1.0, 0.60, 0.56)
    bpy.ops.object.transform_apply(scale=True)
    block.data.materials.append(mats["stone_dark"])
    objs.append(block)

    for x in (-0.46, 0.46):
        for y in (-0.26, 0.26):
            bpy.ops.mesh.primitive_torus_add(major_radius=0.04, minor_radius=0.01, location=(x, y, 0.56))
            ring = bpy.context.active_object
            ring.data.materials.append(mats["iron_dark"])
            objs.append(ring)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = block
    bpy.ops.object.join()
    block.name = "dungeon_altar_variant_c"
    export_obj(block, f"{OUT_DIR}/dungeon_altar_variant_c.obj")
    return block

# ==========================================
# 2. BRAZIER VARIANTS
# ==========================================

def build_brazier_a():
    reset_blend()
    mats = get_materials()
    objs = []
    for i in range(3):
        angle = i * (2 * math.pi / 3)
        x = 0.22 * math.cos(angle)
        y = 0.22 * math.sin(angle)
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.02, depth=0.55, location=(x, y, 0.26))
        leg = bpy.context.active_object
        leg.rotation_euler = (math.sin(angle) * 0.2, -math.cos(angle) * 0.2, 0)
        bpy.ops.object.transform_apply(rotation=True)
        leg.data.materials.append(mats["iron_dark"])
        objs.append(leg)

    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.28, depth=0.12, location=(0, 0, 0.54))
    bowl = bpy.context.active_object
    bowl.data.materials.append(mats["iron_dark"])
    objs.append(bowl)

    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.25, depth=0.06, location=(0, 0, 0.58))
    coals = bpy.context.active_object
    coals.data.materials.append(mats["coal_fire"])
    objs.append(coals)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = bowl
    bpy.ops.object.join()
    bowl.name = "dungeon_brazier_variant_a"
    export_obj(bowl, f"{OUT_DIR}/dungeon_brazier_variant_a.obj")
    return bowl

def build_brazier_b():
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
    base.name = "dungeon_brazier_variant_b"
    export_obj(base, f"{OUT_DIR}/dungeon_brazier_variant_b.obj")
    return base

def build_brazier_c():
    reset_blend()
    mats = get_materials()
    objs = []
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.06))
    base = bpy.context.active_object
    base.scale = (0.44, 0.44, 0.12)
    bpy.ops.object.transform_apply(scale=True)
    base.data.materials.append(mats["stone_dark"])
    objs.append(base)

    for x in (-0.18, 0.18):
        for y in (-0.18, 0.18):
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.36))
            p = bpy.context.active_object
            p.scale = (0.04, 0.04, 0.48)
            bpy.ops.object.transform_apply(scale=True)
            p.data.materials.append(mats["iron_dark"])
            objs.append(p)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.36))
    box = bpy.context.active_object
    box.scale = (0.34, 0.34, 0.30)
    bpy.ops.object.transform_apply(scale=True)
    box.data.materials.append(mats["iron_dark"])
    objs.append(box)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    base.name = "dungeon_brazier_variant_c"
    export_obj(base, f"{OUT_DIR}/dungeon_brazier_variant_c.obj")
    return base

# ==========================================
# 3. SARCOPHAGUS VARIANTS
# ==========================================

def build_sarcophagus_a():
    reset_blend()
    mats = get_materials()
    objs = []
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.22))
    body = bpy.context.active_object
    body.scale = (1.20, 0.58, 0.44)
    bpy.ops.object.transform_apply(scale=True)
    body.data.materials.append(mats["stone_dark"])
    objs.append(body)

    bpy.ops.mesh.primitive_cylinder_add(vertices=3, radius=0.34, depth=1.22, location=(0, 0, 0.52))
    lid = bpy.context.active_object
    lid.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    lid.data.materials.append(mats["stone_light"])
    objs.append(lid)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "sarcophagus_variant_a"
    export_obj(body, f"{OUT_DIR}/sarcophagus_variant_a.obj")
    return body

def build_sarcophagus_b():
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
    base.name = "sarcophagus_variant_b"
    export_obj(base, f"{OUT_DIR}/sarcophagus_variant_b.obj")
    return base

def build_sarcophagus_c():
    reset_blend()
    mats = get_materials()
    objs = []
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.40, depth=1.16, location=(0, 0, 0.22))
    body = bpy.context.active_object
    body.rotation_euler = (0, math.pi / 2, 0)
    body.scale = (1.0, 0.65, 0.50)
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    body.data.materials.append(mats["stone_dark"])
    objs.append(body)

    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.42, depth=1.18, location=(0, 0, 0.48))
    lid = bpy.context.active_object
    lid.rotation_euler = (0, math.pi / 2, 0)
    lid.scale = (1.0, 0.65, 0.12)
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    lid.data.materials.append(mats["stone_light"])
    objs.append(lid)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "sarcophagus_variant_c"
    export_obj(body, f"{OUT_DIR}/sarcophagus_variant_c.obj")
    return body

# ==========================================
# 4. RENDERING COMPARISON SHEET
# ==========================================

def render_comparison_sheet():
    reset_blend()
    mats = get_materials()
    
    categories = [
        ("Altars", [f"{OUT_DIR}/dungeon_altar_variant_a.obj", f"{OUT_DIR}/dungeon_altar_variant_b.obj", f"{OUT_DIR}/dungeon_altar_variant_c.obj"], 1.5),
        ("Braziers", [f"{OUT_DIR}/dungeon_brazier_variant_a.obj", f"{OUT_DIR}/dungeon_brazier_variant_b.obj", f"{OUT_DIR}/dungeon_brazier_variant_c.obj"], 0.0),
        ("Sarcophagi", [f"{OUT_DIR}/sarcophagus_variant_a.obj", f"{OUT_DIR}/sarcophagus_variant_b.obj", f"{OUT_DIR}/sarcophagus_variant_c.obj"], -1.5),
    ]

    for cat_name, files, y_pos in categories:
        for idx, file_path in enumerate(files):
            x_pos = (idx - 1) * 1.5
            bpy.ops.wm.obj_import(filepath=file_path)
            imported = bpy.context.selected_objects
            for o in imported:
                o.location.x += x_pos
                o.location.y += y_pos

    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.data.materials.append(mats["stone_dark"])

    bpy.ops.object.light_add(type='SUN', location=(5, -6, 8))
    key_light = bpy.context.active_object
    key_light.data.energy = 3.5

    bpy.ops.object.light_add(type='SUN', location=(-5, -3, 5))
    fill_light = bpy.context.active_object
    fill_light.data.energy = 1.2

    bpy.ops.object.camera_add(location=(0, -6.5, 4.5))
    cam = bpy.context.active_object
    cam.rotation_euler = (math.radians(48), 0, 0)
    bpy.context.scene.camera = cam

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 64
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.filepath = f"{PREVIEW_DIR}/props_exploration_preview.png"
    
    bpy.ops.render.render(write_still=True)
    print(f"Rendered props exploration sheet: {scene.render.filepath}")

def main():
    print("Building Altars...")
    build_altar_a()
    build_altar_b()
    build_altar_c()

    print("Building Braziers...")
    build_brazier_a()
    build_brazier_b()
    build_brazier_c()

    print("Building Sarcophagi...")
    build_sarcophagus_a()
    build_sarcophagus_b()
    build_sarcophagus_c()

    print("Rendering Props Exploration Comparison Sheet...")
    render_comparison_sheet()
    print("All prop exploration variants generated!")

if __name__ == "__main__":
    main()
