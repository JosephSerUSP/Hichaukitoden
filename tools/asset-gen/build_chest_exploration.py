"""Blender 5.1 script to generate 3 high-quality Chest model variants & comparison renders.

Run via Blender:
  & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background --python tools/asset-gen/build_chest_exploration.py
"""

import bpy
import math
import os
from mathutils import Vector, Matrix, Euler

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
        "wood_body": ((0.38, 0.24, 0.13), 0.0, 0.6),
        "iron_trim": ((0.20, 0.22, 0.25), 0.8, 0.3),
        "gold_lock": ((0.85, 0.68, 0.18), 0.9, 0.2),
        "stone_base": ((0.32, 0.32, 0.35), 0.0, 0.8),
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

# --- VARIANT A: Classic High-Relief PSX Barrel Chest ---
def build_variant_a():
    reset_blend()
    mats = get_materials()
    objs = []

    # Main Body Base (Wood)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
    body = bpy.context.active_object
    body.name = "ChestA_Body"
    body.scale = (0.64, 0.44, 0.28)
    bpy.ops.object.transform_apply(scale=True)
    body.data.materials.append(mats["wood_body"])
    objs.append(body)

    bev = body.modifiers.new(name="Bevel", type='BEVEL')
    bev.width = 0.015
    bev.segments = 2
    bpy.ops.object.modifier_apply(modifier="Bevel")

    # Domed Lid (Barrel Vault)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.22, depth=0.64, location=(0, 0, 0.28))
    lid = bpy.context.active_object
    lid.name = "ChestA_Lid"
    lid.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    lid.data.materials.append(mats["wood_body"])
    objs.append(lid)

    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    for v in lid.data.vertices:
        if v.co.z < 0.28:
            v.select = True
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.delete(type='VERT')
    bpy.ops.object.mode_set(mode='OBJECT')

    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.edge_face_add()
    bpy.ops.object.mode_set(mode='OBJECT')

    # Iron Rim Lip on Lid Base
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.28))
    rim = bpy.context.active_object
    rim.name = "ChestA_LidRim"
    rim.scale = (0.66, 0.46, 0.03)
    bpy.ops.object.transform_apply(scale=True)
    rim.data.materials.append(mats["iron_trim"])
    objs.append(rim)

    # Corner Brackets
    for x in (-0.31, 0.31):
        for y in (-0.21, 0.21):
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.14))
            c = bpy.context.active_object
            c.scale = (0.06, 0.06, 0.29)
            bpy.ops.object.transform_apply(scale=True)
            c.data.materials.append(mats["iron_trim"])
            objs.append(c)

    # Center Iron Strap
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.14))
    strap = bpy.context.active_object
    strap.scale = (0.08, 0.46, 0.29)
    bpy.ops.object.transform_apply(scale=True)
    strap.data.materials.append(mats["iron_trim"])
    objs.append(strap)

    # Ornate Gold Shield Lock Plate
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.07, depth=0.02, location=(0, 0.23, 0.15))
    lock = bpy.context.active_object
    lock.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    lock.data.materials.append(mats["gold_lock"])
    objs.append(lock)

    # Side Handles
    for x_pos in (-0.33, 0.33):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.04, minor_radius=0.01, location=(x_pos, 0, 0.14))
        h = bpy.context.active_object
        h.rotation_euler = (0, math.pi / 2, 0)
        bpy.ops.object.transform_apply(rotation=True)
        h.data.materials.append(mats["iron_trim"])
        objs.append(h)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "dungeon_chest_variant_a"

    export_obj(body, f"{OUT_DIR}/dungeon_chest_variant_a.obj")
    return body

# --- VARIANT B: Sacred Ironbound Reliquary Chest ---
def build_variant_b():
    reset_blend()
    mats = get_materials()
    objs = []

    for x in (-0.28, 0.28):
        for y in (-0.18, 0.18):
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, 0.03))
            foot = bpy.context.active_object
            foot.scale = (0.10, 0.10, 0.06)
            bpy.ops.object.transform_apply(scale=True)
            foot.data.materials.append(mats["iron_trim"])
            objs.append(foot)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.18))
    body = bpy.context.active_object
    body.scale = (0.62, 0.42, 0.24)
    bpy.ops.object.transform_apply(scale=True)
    body.data.materials.append(mats["wood_body"])
    objs.append(body)

    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.22, depth=0.62, location=(0, 0, 0.35))
    lid = bpy.context.active_object
    lid.scale = (1.0, 0.95, 1.0)
    lid.rotation_euler = (0, math.pi / 2, math.pi / 8)
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    lid.data.materials.append(mats["wood_body"])
    objs.append(lid)

    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    for v in lid.data.vertices:
        if v.co.z < 0.30:
            v.select = True
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.delete(type='VERT')
    bpy.ops.object.mode_set(mode='OBJECT')

    for z_strap in (0.10, 0.24):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, z_strap))
        s = bpy.context.active_object
        s.scale = (0.63, 0.43, 0.04)
        bpy.ops.object.transform_apply(scale=True)
        s.data.materials.append(mats["iron_trim"])
        objs.append(s)

    for y_front in (-0.22, 0.22):
        for x_stud in (-0.24, -0.12, 0.0, 0.12, 0.24):
            for z_stud in (0.10, 0.24):
                bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.02, depth=0.02, location=(x_stud, y_front, z_stud))
                stud = bpy.context.active_object
                stud.rotation_euler = (math.pi / 2 if y_front > 0 else -math.pi / 2, 0, 0)
                bpy.ops.object.transform_apply(rotation=True)
                stud.data.materials.append(mats["gold_lock"])
                objs.append(stud)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.22, 0.20))
    hasp = bpy.context.active_object
    hasp.scale = (0.10, 0.03, 0.12)
    bpy.ops.object.transform_apply(scale=True)
    hasp.data.materials.append(mats["gold_lock"])
    objs.append(hasp)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "dungeon_chest_variant_b"

    export_obj(body, f"{OUT_DIR}/dungeon_chest_variant_b.obj")
    return body

# --- VARIANT C: Heavy Ancient Civic Iron Vault Chest ---
def build_variant_c():
    reset_blend()
    mats = get_materials()
    objs = []

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.15))
    body = bpy.context.active_object
    body.scale = (0.68, 0.46, 0.30)
    bpy.ops.object.transform_apply(scale=True)
    body.data.materials.append(mats["wood_body"])
    objs.append(body)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.02))
    b_frame = bpy.context.active_object
    b_frame.scale = (0.70, 0.48, 0.04)
    bpy.ops.object.transform_apply(scale=True)
    b_frame.data.materials.append(mats["iron_trim"])
    objs.append(b_frame)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.30))
    t_frame = bpy.context.active_object
    t_frame.scale = (0.70, 0.48, 0.04)
    bpy.ops.object.transform_apply(scale=True)
    t_frame.data.materials.append(mats["iron_trim"])
    objs.append(t_frame)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.34))
    lid = bpy.context.active_object
    lid.scale = (0.68, 0.46, 0.06)
    bpy.ops.object.transform_apply(scale=True)
    lid.data.materials.append(mats["wood_body"])
    objs.append(lid)

    for rot in (math.pi / 6, -math.pi / 6):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.38))
        x_strap = bpy.context.active_object
        x_strap.rotation_euler = (0, 0, rot)
        x_strap.scale = (0.72, 0.06, 0.02)
        bpy.ops.object.transform_apply(rotation=True, scale=True)
        x_strap.data.materials.append(mats["iron_trim"])
        objs.append(x_strap)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.24, 0.20))
    bar = bpy.context.active_object
    bar.scale = (0.40, 0.03, 0.06)
    bpy.ops.object.transform_apply(scale=True)
    bar.data.materials.append(mats["iron_trim"])
    objs.append(bar)

    for x_lock in (-0.12, 0.12):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x_lock, 0.25, 0.18))
        lock = bpy.context.active_object
        lock.scale = (0.06, 0.04, 0.08)
        bpy.ops.object.transform_apply(scale=True)
        lock.data.materials.append(mats["gold_lock"])
        objs.append(lock)

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "dungeon_chest_variant_c"

    export_obj(body, f"{OUT_DIR}/dungeon_chest_variant_c.obj")
    return body

# --- RENDER SIDE-BY-SIDE PREVIEW ---
def render_comparison_preview():
    reset_blend()
    mats = get_materials()
    
    variants = [
        ("A: PSX Barrel Chest", f"{OUT_DIR}/dungeon_chest_variant_a.obj", -1.1),
        ("B: Reliquary Chest", f"{OUT_DIR}/dungeon_chest_variant_b.obj", 0.0),
        ("C: Heavy Iron Vault", f"{OUT_DIR}/dungeon_chest_variant_c.obj", 1.1),
    ]

    for label, obj_file, x_pos in variants:
        bpy.ops.wm.obj_import(filepath=obj_file)
        imported = bpy.context.selected_objects
        for o in imported:
            o.location.x += x_pos

    # Ground Plane
    bpy.ops.mesh.primitive_plane_add(size=10.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.data.materials.append(mats["stone_base"])

    # Lights
    bpy.ops.object.light_add(type='SUN', location=(3, -4, 5))
    key_light = bpy.context.active_object
    key_light.data.energy = 3.5
    key_light.rotation_euler = (math.radians(50), math.radians(20), math.radians(30))

    bpy.ops.object.light_add(type='SUN', location=(-4, -2, 3))
    fill_light = bpy.context.active_object
    fill_light.data.energy = 1.2
    fill_light.rotation_euler = (math.radians(60), math.radians(-30), math.radians(-40))

    bpy.ops.object.light_add(type='SUN', location=(0, 5, 4))
    rim_light = bpy.context.active_object
    rim_light.data.energy = 2.0
    rim_light.rotation_euler = (math.radians(-45), 0, 0)

    # Camera
    bpy.ops.object.camera_add(location=(0, -3.2, 1.6))
    cam = bpy.context.active_object
    cam.rotation_euler = (math.radians(65), 0, 0)
    bpy.context.scene.camera = cam

    # Render Settings
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 64
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 480
    scene.render.filepath = f"{PREVIEW_DIR}/chest_variants_preview.png"
    
    bpy.ops.render.render(write_still=True)
    print(f"Rendered comparison preview: {scene.render.filepath}")

def main():
    print("Building Variant A...")
    build_variant_a()
    print("Building Variant B...")
    build_variant_b()
    print("Building Variant C...")
    build_variant_c()
    
    print("Rendering comparison preview...")
    render_comparison_preview()
    print("All chest exploration variants complete!")

if __name__ == "__main__":
    main()
