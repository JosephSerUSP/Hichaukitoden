import bpy
import math
import os
import sys
import importlib.util
from pathlib import Path
from mathutils import Vector

OUT_DIR = Path(os.environ.get("SECOND_RITE_OUT", "/tmp/second_rite_item_library"))
OUT_DIR.mkdir(parents=True, exist_ok=True)
EXPORT_DIR = OUT_DIR / "exports"
EXPORT_DIR.mkdir(parents=True, exist_ok=True)
SCRIPT_DIR = Path(__file__).resolve().parent
EXPORTER_PATH = SCRIPT_DIR / "second_rite_item_exporter.py"
BLEND_PATH = OUT_DIR / "second_rite_item_model_library_expanded.blend"
PREVIEW_PATH = OUT_DIR / "second_rite_item_model_library_expanded_preview.png"
MANIFEST_PATH = OUT_DIR / "ITEM_MODEL_MANIFEST.md"

# -----------------------------------------------------------------------------
# Scene and data helpers
# -----------------------------------------------------------------------------

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != "Collection":
            bpy.data.collections.remove(collection)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def ensure_collection(name, parent=None):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(col)
    return col


def move_to_collection(obj, collection):
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    collection.objects.link(obj)


def make_material(name, color, metallic=0.0, roughness=0.55, emission=None, alpha=1.0):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, alpha)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, alpha)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission is not None:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
                bsdf.inputs["Emission Strength"].default_value = 1.2
            elif "Emission" in bsdf.inputs:
                bsdf.inputs["Emission"].default_value = (*emission, 1.0)
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        mat.surface_render_method = 'DITHERED'
    return mat


def assign_material(obj, material):
    if obj.data and hasattr(obj.data, "materials"):
        obj.data.materials.append(material)


def flat_shade(obj):
    if obj.type == 'MESH':
        for poly in obj.data.polygons:
            poly.use_smooth = False


def add_bevel(obj, width=0.06, segments=1):
    if width <= 0:
        return
    mod = obj.modifiers.new("LowPolyBevel", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'


def parent_local(obj, root, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.parent = root
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale
    return obj


def create_root(name, export_name, location, category, description=""):
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = 'PLAIN_AXES'
    root.empty_display_size = 0.35
    root.location = location
    root["item_export"] = True
    root["item_export_name"] = export_name
    root["item_display_name"] = name
    root["item_category"] = category
    root["item_description"] = description
    ITEM_COLLECTION.objects.link(root)
    ROOTS.append(root)
    return root


def add_cube(root, name, loc, scale, material, rot=(0,0,0), bevel=0.05):
    bpy.ops.mesh.primitive_cube_add(size=2, location=(0,0,0))
    obj = bpy.context.object
    obj.name = name
    parent_local(obj, root, loc, rot, scale)
    assign_material(obj, material)
    add_bevel(obj, bevel, 1)
    flat_shade(obj)
    return obj


def add_cylinder(root, name, loc, radius, depth, material, vertices=10, rot=(0,0,0), bevel=0.03):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, end_fill_type='NGON', location=(0,0,0))
    obj = bpy.context.object
    obj.name = name
    parent_local(obj, root, loc, rot)
    assign_material(obj, material)
    add_bevel(obj, bevel, 1)
    flat_shade(obj)
    return obj


def add_cone(root, name, loc, r1, r2, depth, material, vertices=10, rot=(0,0,0), bevel=0.02):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=depth, location=(0,0,0))
    obj = bpy.context.object
    obj.name = name
    parent_local(obj, root, loc, rot)
    assign_material(obj, material)
    add_bevel(obj, bevel, 1)
    flat_shade(obj)
    return obj


def add_uv_sphere(root, name, loc, scale, material, segments=12, rings=6, rot=(0,0,0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=(0,0,0))
    obj = bpy.context.object
    obj.name = name
    parent_local(obj, root, loc, rot, scale)
    assign_material(obj, material)
    flat_shade(obj)
    return obj


def add_ico(root, name, loc, scale, material, subdivisions=1, rot=(0,0,0)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=(0,0,0))
    obj = bpy.context.object
    obj.name = name
    parent_local(obj, root, loc, rot, scale)
    assign_material(obj, material)
    flat_shade(obj)
    return obj


def add_torus(root, name, loc, major_radius, minor_radius, material, major_segments=12, minor_segments=4, rot=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major_radius, minor_radius=minor_radius,
                                    major_segments=major_segments, minor_segments=minor_segments,
                                    location=(0,0,0))
    obj = bpy.context.object
    obj.name = name
    parent_local(obj, root, loc, rot)
    assign_material(obj, material)
    flat_shade(obj)
    return obj


def add_cylinder_between(root, name, p1, p2, radius, material, vertices=8):
    p1 = Vector(p1); p2 = Vector(p2)
    direction = p2 - p1
    length = direction.length
    if length <= 1e-6:
        return None
    midpoint = (p1 + p2) * 0.5
    obj = add_cylinder(root, name, midpoint, radius, length, material, vertices=vertices, bevel=0.015)
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = direction.to_track_quat('Z', 'Y')
    return obj


def add_prism(root, name, outline_xz, depth, material, loc=(0,0,0), rot=(0,0,0), bevel=0.03):
    # Convex polygon in XZ, extruded along Y.
    n = len(outline_xz)
    verts = []
    for y in (-depth/2, depth/2):
        verts.extend([(x, y, z) for x, z in outline_xz])
    faces = []
    # front/back fans
    for i in range(1, n-1):
        faces.append((0, i+1, i))
        faces.append((n, n+i, n+i+1))
    for i in range(n):
        j = (i+1) % n
        faces.append((i, j, n+j, n+i))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    ITEM_COLLECTION.objects.link(obj)
    parent_local(obj, root, loc, rot)
    assign_material(obj, material)
    add_bevel(obj, bevel, 1)
    flat_shade(obj)
    return obj


def add_rivet_ring(root, radius, z, count, rivet_radius, material, y=-0.16):
    for i in range(count):
        a = 2 * math.pi * i / count
        add_ico(root, f"Rivet_{z}_{i}", (radius*math.cos(a), y, z + radius*math.sin(a)),
                (rivet_radius, rivet_radius, rivet_radius), material, subdivisions=1)


def add_helix(root, name, center, radius, height, turns, segments, tube_radius, material):
    pts = []
    for i in range(segments+1):
        t = i / segments
        a = t * turns * 2 * math.pi
        pts.append((center[0] + radius*math.cos(a), center[1] + radius*math.sin(a), center[2] + height*(t-0.5)))
    for i in range(segments):
        add_cylinder_between(root, f"{name}_{i:02d}", pts[i], pts[i+1], tube_radius, material, vertices=6)


def add_bead_string(root, points, bead_indices, material_string, material_bead, bead_scale=0.14):
    for i in range(len(points)-1):
        add_cylinder_between(root, f"Cord_{i}", points[i], points[i+1], 0.035, material_string, vertices=6)
    for i in bead_indices:
        p = points[i]
        add_ico(root, f"Bead_{i}", p, (bead_scale, bead_scale, bead_scale), material_bead, subdivisions=1)


def add_sword(root, prefix, blade_mat, guard_mat, grip_mat, gem_mat=None,
              length=3.3, blade_width=0.42, thickness=0.14, guard_width=1.35,
              broken=False, wing_guard=False, sun_guard=False, asym=False):
    blade_z0 = -0.45
    blade_z1 = blade_z0 + length
    if broken:
        outline = [(-blade_width*0.5, blade_z0), (blade_width*0.48, blade_z0),
                   (blade_width*0.34, blade_z0+length*0.55), (0.08, blade_z0+length*0.63),
                   (-0.12, blade_z0+length*0.58), (-blade_width*0.36, blade_z0+length*0.48)]
    elif asym:
        outline = [(-blade_width*0.45, blade_z0), (blade_width*0.58, blade_z0),
                   (blade_width*0.26, blade_z1-0.28), (0.04, blade_z1),
                   (-blade_width*0.22, blade_z1-0.18)]
    else:
        outline = [(-blade_width*0.5, blade_z0), (blade_width*0.5, blade_z0),
                   (blade_width*0.28, blade_z1-0.35), (0, blade_z1),
                   (-blade_width*0.28, blade_z1-0.35)]
    add_prism(root, prefix+"_Blade", outline, thickness, blade_mat, bevel=0.025)
    # fuller/ridge
    if not broken:
        add_prism(root, prefix+"_Fuller", [(-0.045, blade_z0+0.12),(0.045,blade_z0+0.12),(0.028,blade_z1-0.42),(-0.028,blade_z1-0.42)],
                  thickness+0.035, guard_mat, loc=(0,-0.01,0), bevel=0.01)
    if wing_guard:
        add_prism(root, prefix+"_GuardL", [(-0.1,-0.06),(-guard_width*0.55,0.15),(-guard_width*0.72,0.42),(-0.12,0.22)],
                  0.18, guard_mat, loc=(0,0,blade_z0), bevel=0.025)
        add_prism(root, prefix+"_GuardR", [(0.1,-0.06),(guard_width*0.55,0.15),(guard_width*0.72,0.42),(0.12,0.22)],
                  0.18, guard_mat, loc=(0,0,blade_z0), bevel=0.025)
    else:
        add_cube(root, prefix+"_Guard", (0,0,blade_z0), (guard_width*0.5,0.12,0.10), guard_mat,
                 rot=(0,0,math.radians(8 if asym else 0)), bevel=0.07)
    if sun_guard:
        add_torus(root, prefix+"_SunRing", (0,0,blade_z0+0.02), 0.38, 0.055, guard_mat, 12, 4, rot=(math.radians(90),0,0))
        for i in range(8):
            a = 2*math.pi*i/8
            p1=(0.36*math.cos(a),0,blade_z0+0.02+0.36*math.sin(a))
            p2=(0.58*math.cos(a),0,blade_z0+0.02+0.58*math.sin(a))
            add_cylinder_between(root,prefix+f"_Ray{i}",p1,p2,0.045,guard_mat,6)
    add_cylinder(root, prefix+"_Grip", (0,0,blade_z0-0.58), 0.16, 0.95, grip_mat, vertices=8, bevel=0.025)
    for i in range(4):
        add_torus(root, prefix+f"_GripBand{i}", (0,0,blade_z0-0.28-i*0.18), 0.17, 0.025, guard_mat, 8, 4)
    add_ico(root, prefix+"_Pommel", (0,0,blade_z0-1.12), (0.22,0.18,0.25), guard_mat, subdivisions=1)
    if gem_mat:
        add_ico(root, prefix+"_Gem", (0,-0.15,blade_z0+0.02), (0.16,0.09,0.16), gem_mat, subdivisions=1)


# -----------------------------------------------------------------------------
# Materials
# -----------------------------------------------------------------------------
clear_scene()
ROOTS = []
ITEM_COLLECTION = ensure_collection("Second Rite Items")
PREVIEW_COLLECTION = ensure_collection("Preview Only")

MAT = {}
def M(key, color, metallic=0.0, roughness=0.55, emission=None, alpha=1.0):
    MAT[key] = make_material("MAT_" + key, color, metallic, roughness, emission, alpha)

M("SilverSteel", (0.58,0.66,0.74), 0.82, 0.28)
M("Iron", (0.23,0.27,0.30), 0.72, 0.48)
M("DarkIron", (0.08,0.09,0.11), 0.82, 0.34)
M("OldGold", (0.56,0.34,0.09), 0.72, 0.38)
M("BrightGold", (0.92,0.65,0.16), 0.78, 0.24)
M("Bone", (0.72,0.67,0.53), 0.05, 0.75)
M("Leather", (0.22,0.09,0.045), 0.0, 0.82)
M("Wood", (0.28,0.12,0.05), 0.0, 0.78)
M("Paper", (0.72,0.64,0.45), 0.0, 0.92)
M("ClothGreen", (0.12,0.33,0.22), 0.0, 0.74)
M("ClothRed", (0.45,0.08,0.06), 0.0, 0.74)
M("Ruby", (0.62,0.035,0.025), 0.12, 0.24, emission=(0.5,0.01,0.005))
M("Cinder", (0.92,0.18,0.03), 0.08, 0.32, emission=(0.85,0.06,0.005))
M("Emerald", (0.03,0.48,0.22), 0.12, 0.22, emission=(0.01,0.25,0.08))
M("Sapphire", (0.025,0.20,0.68), 0.10, 0.20, emission=(0.005,0.07,0.50))
M("Teal", (0.02,0.46,0.49), 0.10, 0.22, emission=(0.005,0.24,0.25))
M("Amethyst", (0.32,0.04,0.52), 0.10, 0.22, emission=(0.12,0.005,0.30))
M("Pearl", (0.72,0.78,0.86), 0.16, 0.16)
M("Obsidian", (0.035,0.03,0.055), 0.18, 0.18)
M("Verdigris", (0.08,0.37,0.31), 0.55, 0.58)
M("Wax", (0.78,0.48,0.12), 0.0, 0.70)
M("Ectoplasm", (0.25,0.78,0.68), 0.0, 0.18, emission=(0.06,0.45,0.34), alpha=0.78)
M("GlassRed", (0.42,0.04,0.04), 0.0, 0.18, alpha=0.76)
M("GlassBlue", (0.05,0.18,0.38), 0.0, 0.18, alpha=0.76)
M("GlassGreen", (0.04,0.28,0.16), 0.0, 0.18, alpha=0.76)
M("GlassClear", (0.58,0.68,0.72), 0.0, 0.16, alpha=0.62)
M("LiquidRed", (0.58,0.02,0.025), 0.0, 0.28, emission=(0.25,0.005,0.005))
M("LiquidBlue", (0.02,0.16,0.55), 0.0, 0.24, emission=(0.005,0.06,0.28))
M("LiquidGreen", (0.04,0.30,0.09), 0.0, 0.36)
M("Ale", (0.68,0.26,0.035), 0.0, 0.55)
M("Stout", (0.12,0.035,0.012), 0.0, 0.68)
M("Wine", (0.34,0.015,0.035), 0.0, 0.42)
M("Foam", (0.86,0.76,0.56), 0.0, 0.95)
M("Char", (0.055,0.04,0.03), 0.0, 0.96)
M("Sludge", (0.18,0.27,0.08), 0.0, 0.92)
M("WhiteHoly", (0.78,0.82,0.86), 0.30, 0.22, emission=(0.15,0.17,0.2))
M("Backdrop", (0.018,0.022,0.035), 0.0, 0.95)
M("Slot", (0.045,0.055,0.075), 0.0, 0.88)
M("Text", (0.72,0.76,0.84), 0.0, 0.75)

# -----------------------------------------------------------------------------
# Item constructors
# -----------------------------------------------------------------------------

def bottle_family(root):
    segments = 12
    # ring index, z, radius
    profile = [(-1.35,0.56),(-1.15,0.70),(-0.25,0.78),(0.55,0.66),(0.88,0.42),(1.10,0.34),(1.42,0.34)]
    verts=[]
    for z,r in profile:
        for i in range(segments):
            a=2*math.pi*i/segments
            verts.append((r*math.cos(a), r*math.sin(a), z))
    faces=[]
    for ri in range(len(profile)-1):
        for i in range(segments):
            j=(i+1)%segments
            a=ri*segments+i; b=ri*segments+j; c=(ri+1)*segments+j; d=(ri+1)*segments+i
            faces.append((a,b,c,d))
    faces.append(tuple(reversed(range(segments))))
    top_start=(len(profile)-1)*segments
    faces.append(tuple(top_start+i for i in range(segments)))
    mesh=bpy.data.meshes.new("BottleFamilyBodyMesh")
    mesh.from_pydata(verts,[],faces); mesh.update()
    body=bpy.data.objects.new("BottleFamily_Body",mesh); ITEM_COLLECTION.objects.link(body)
    parent_local(body,root)
    assign_material(body,MAT["GlassGreen"]); add_bevel(body,0.035,1); flat_shade(body)
    basis=body.shape_key_add(name="Basis")
    tall=body.shape_key_add(name="Tall")
    round_key=body.shape_key_add(name="Round")
    angular=body.shape_key_add(name="Angular")
    molten=body.shape_key_add(name="Molten")
    for idx,v in enumerate(basis.data):
        x,y,z=v.co
        radial=math.sqrt(x*x+y*y)
        ang=math.atan2(y,x)
        # Tall: narrow and vertically stretched
        tall.data[idx].co=(x*0.78,y*0.78,z*1.25)
        # Round: squat, broad belly
        belly=1.0+0.28*math.exp(-((z+0.15)/0.8)**2)
        round_key.data[idx].co=(x*belly,y*belly,z*0.82)
        # Angular: quantize angle into eight broad facets and shoulder harder
        qa=round(ang/(math.pi/4))*(math.pi/4)
        rr=radial*(0.92 if z>0.6 else 1.0)
        angular.data[idx].co=(rr*math.cos(qa),rr*math.sin(qa),z)
        # Molten: collapsed, asymmetrical, low
        wobble=1+0.22*math.sin(ang*3+z*1.7)
        molten.data[idx].co=(x*wobble+0.13*(z+1.2),y*(0.9+0.18*math.cos(ang*2)),z*0.52-0.55)
    add_cylinder(root,"BottleFamily_Cork",(0,0,1.58),0.30,0.38,MAT["Wood"],vertices=10,bevel=0.04)
    add_torus(root,"BottleFamily_Collar",(0,0,1.38),0.37,0.055,MAT["OldGold"],12,4)
    add_cylinder(root,"BottleFamily_Liquid",(0,0,-0.45),0.60,1.25,MAT["LiquidRed"],vertices=12,bevel=0.02)
    add_ico(root,"BottleFamily_Seal",(0,-0.76,0.18),(0.22,0.08,0.27),MAT["Ruby"],1)


def wind_charm(root):
    add_torus(root,"WindCharm_Ring",(0,0,0.62),0.62,0.09,MAT["OldGold"],16,5,rot=(math.radians(90),0,0))
    add_prism(root,"WindCharm_Pendant",[(-0.48,0.35),(0,1.05),(0.48,0.35),(0.26,-0.18),(0,-0.48),(-0.26,-0.18)],0.14,MAT["Teal"],loc=(0,-0.08,-0.15),bevel=0.045)
    add_prism(root,"WindCharm_Cutout",[(-0.16,0.20),(0,0.50),(0.16,0.20),(0,-0.02)],0.17,MAT["OldGold"],loc=(0,-0.11,-0.12),bevel=0.025)
    pts=[(-0.45,0,0.55),(-0.72,0,0.18),(-0.60,0,-0.42),(-0.82,0,-0.95)]
    add_bead_string(root,pts,[2],MAT["Leather"],MAT["Teal"],0.12)
    pts2=[(0.45,0,0.55),(0.72,0,0.18),(0.60,0,-0.42),(0.82,0,-0.95)]
    add_bead_string(root,pts2,[2],MAT["Leather"],MAT["Teal"],0.12)


def crystal_cluster(root, main_mat=None):
    mat=main_mat or MAT["Amethyst"]
    for i,(x,y,z,s,h,tilt) in enumerate([
        (0,0,0,0.42,2.3,0),(-0.48,0.12,-0.35,0.30,1.55,-16),(0.46,0.08,-0.42,0.34,1.75,15),
        (-0.18,-0.28,-0.55,0.24,1.25,9),(0.28,-0.25,-0.58,0.22,1.10,-10)]):
        add_cone(root,f"Crystal_{i}",(x,y,z),s,s*0.72,h,mat,vertices=6,rot=(0,math.radians(tilt),0),bevel=0.015)
        add_cone(root,f"CrystalTip_{i}",(x,y,z+h*0.58),s*0.72,0,h*0.35,mat,vertices=6,rot=(0,math.radians(tilt),0),bevel=0.01)
    add_ico(root,"Crystal_Base",(0,0,-1.05),(0.95,0.62,0.35),MAT["Obsidian"],1)


def question_mark(root):
    # Blocky 3D question mark with readable silhouette.
    blocks=[(-0.44,0,0.90,0.22,0.18,0.22),(0,0,1.12,0.50,0.18,0.20),(0.48,0,0.86,0.20,0.18,0.30),
            (0.32,0,0.40,0.22,0.18,0.22),(0.02,0,0.16,0.26,0.18,0.18),(0,0,-0.22,0.18,0.18,0.18)]
    for i,(x,y,z,sx,sy,sz) in enumerate(blocks):
        add_cube(root,f"Question_Block{i}",(x,y,z),(sx,sy,sz),MAT["BrightGold"],bevel=0.07)
    add_ico(root,"Question_Dot",(0,0,-0.82),(0.22,0.18,0.22),MAT["Ruby"],1)
    add_torus(root,"Question_Halo",(0,0,0.20),1.05,0.07,MAT["OldGold"],16,4,rot=(math.radians(90),0,0))


def bone_plate(root):
    add_prism(root,"BonePlate_Core",[(-0.80,0.90),(-1.00,0.15),(-0.65,-1.05),(0,-1.35),(0.65,-1.05),(1.0,0.15),(0.80,0.90),(0,1.20)],0.26,MAT["Leather"],bevel=0.08)
    add_prism(root,"BonePlate_Sternum",[(-0.18,1.05),(0.18,1.05),(0.28,-1.0),(0,-1.28),(-0.28,-1.0)],0.34,MAT["Bone"],loc=(0,-0.08,0),bevel=0.06)
    for side in (-1,1):
        for i,z in enumerate([0.72,0.35,-0.02,-0.39,-0.74]):
            add_cylinder_between(root,f"BonePlate_Rib_{side}_{i}",(0.10*side,-0.18,z),(0.82*side,-0.12,z-0.20),0.095,MAT["Bone"],8)
        add_prism(root,f"BonePlate_Shoulder_{side}",[(0,0.28),(0.72,0.42),(0.95,0.05),(0.54,-0.22)],0.30,MAT["Bone"],loc=(0.70*side,0,0.82),rot=(0,0,0 if side==1 else math.pi),bevel=0.07)
    add_ico(root,"BonePlate_Heart",(0,-0.27,0.10),(0.22,0.12,0.26),MAT["Ruby"],1)


def rear_mirror(root):
    add_torus(root,"RearMirror_Frame",(0,0,0.40),0.78,0.12,MAT["OldGold"],18,5,rot=(math.radians(90),0,0))
    add_uv_sphere(root,"RearMirror_Glass",(0,0.07,0.40),(0.67,0.08,0.86),MAT["Pearl"],12,6)
    add_cylinder(root,"RearMirror_Handle",(0,0,-0.70),0.16,1.15,MAT["Wood"],8,bevel=0.04)
    add_ico(root,"RearMirror_Pommel",(0,0,-1.38),(0.24,0.19,0.26),MAT["OldGold"],1)
    for i in range(8):
        a=2*math.pi*i/8
        add_ico(root,f"RearMirror_Rivet{i}",(0.82*math.cos(a),-0.10,0.40+0.82*math.sin(a)),(0.07,0.05,0.07),MAT["BrightGold"],1)


def egg(root, golden=False):
    body_mat=MAT["BrightGold"] if golden else MAT["Amethyst"]
    add_uv_sphere(root,"Egg_Body",(0,0,0),(0.78,0.70,1.18),body_mat,segments=12,rings=8)
    add_torus(root,"Egg_Band",(0,0,-0.08),0.70,0.065,MAT["OldGold"],16,4)
    add_torus(root,"Egg_Band2",(0,0,0.43),0.56,0.05,MAT["OldGold"],16,4)
    if golden:
        for i in range(6):
            a=2*math.pi*i/6
            add_cylinder_between(root,f"Egg_Filigree{i}",(0.42*math.cos(a),0.42*math.sin(a),-0.58),(0.34*math.cos(a),0.34*math.sin(a),0.72),0.035,MAT["Ruby"],6)
        add_ico(root,"Egg_Crown",(0,0,1.12),(0.17,0.15,0.20),MAT["Ruby"],1)
    else:
        add_ico(root,"Egg_Pulse",(0,-0.70,0.05),(0.18,0.08,0.24),MAT["Teal"],1)
        for i in range(4):
            a=2*math.pi*i/4
            add_ico(root,f"Egg_Node{i}",(0.55*math.cos(a),0.55*math.sin(a),0.12),(0.11,0.11,0.11),MAT["Teal"],1)


def vitality_seal(root, tier):
    add_torus(root,"Seal_Outer",(0,0,0),0.84,0.10,MAT["OldGold"],18,5,rot=(math.radians(90),0,0))
    add_cylinder(root,"Seal_Disc",(0,0,0),0.68,0.16,MAT["Ruby"],vertices=18,rot=(math.radians(90),0,0),bevel=0.04)
    for ring in range(tier):
        add_torus(root,f"Seal_Ring{ring}",(0,-0.10-ring*0.02,0),0.28+ring*0.16,0.035,MAT["BrightGold"],16,4,rot=(math.radians(90),0,0))
    spikes=4+tier*2
    for i in range(spikes):
        a=2*math.pi*i/spikes
        p1=(0.82*math.cos(a),0,0.82*math.sin(a)); p2=(1.06*math.cos(a),0,1.06*math.sin(a))
        add_cylinder_between(root,f"Seal_Ray{i}",p1,p2,0.045,MAT["BrightGold"],6)
    add_ico(root,"Seal_Heart",(0,-0.18,0),(0.22,0.10,0.22),MAT["Pearl"],1)


def wind_dancer(root):
    for side in (-1,1):
        rr=(0,math.radians(side*10),math.radians(side*16))
        x=0.48*side
        add_prism(root,f"WindDancer_Blade{side}",[(-0.26,-0.55),(0,-0.90),(0.26,-0.55),(0.38,0.42),(0,1.55),(-0.38,0.42)],0.12,MAT["SilverSteel"],loc=(x,0,0.30),rot=rr,bevel=0.025)
        add_cube(root,f"WindDancer_Grip{side}",(x,0,-0.72),(0.13,0.11,0.44),MAT["Leather"],rot=rr,bevel=0.04)
        add_cube(root,f"WindDancer_Guard{side}",(x,0,-0.28),(0.43,0.12,0.08),MAT["OldGold"],rot=rr,bevel=0.05)
        pts=[(x,0,-1.10),(x+0.28*side,0,-1.38),(x+0.08*side,0,-1.72)]
        add_bead_string(root,pts,[1],MAT["ClothGreen"],MAT["Emerald"],0.10)


def water_scepter(root):
    add_cylinder(root,"WaterScepter_Shaft",(0,0,-0.20),0.15,3.4,MAT["SilverSteel"],8,bevel=0.035)
    add_ico(root,"WaterScepter_Orb",(0,0,1.65),(0.48,0.42,0.48),MAT["Sapphire"],2)
    add_torus(root,"WaterScepter_Crescent",(0,0,1.65),0.82,0.11,MAT["OldGold"],18,5,rot=(math.radians(90),0,0))
    add_prism(root,"WaterScepter_FinL",[(-0.10,-0.05),(-0.90,0.30),(-0.52,-0.35)],0.16,MAT["Teal"],loc=(-0.32,-0.02,1.62),bevel=0.04)
    add_prism(root,"WaterScepter_FinR",[(0.10,-0.05),(0.90,0.30),(0.52,-0.35)],0.16,MAT["Teal"],loc=(0.32,-0.02,1.62),bevel=0.04)
    add_ico(root,"WaterScepter_Pommel",(0,0,-1.98),(0.26,0.22,0.30),MAT["Sapphire"],1)


def dark_scepter(root):
    add_cylinder(root,"DarkScepter_Shaft",(0,0,-0.15),0.16,3.5,MAT["DarkIron"],8,bevel=0.035)
    add_ico(root,"DarkScepter_Core",(0,0,1.65),(0.44,0.38,0.50),MAT["Amethyst"],2)
    for i in range(5):
        a=2*math.pi*i/5
        add_cylinder_between(root,f"DarkScepter_Claw{i}",(0.24*math.cos(a),0.24*math.sin(a),1.36),(0.62*math.cos(a),0.62*math.sin(a),2.05),0.075,MAT["DarkIron"],7)
        add_cone(root,f"DarkScepter_Tip{i}",(0.68*math.cos(a),0.68*math.sin(a),2.14),0.11,0,0.36,MAT["DarkIron"],7,rot=(0,math.radians(55),a),bevel=0.01)
    add_torus(root,"DarkScepter_Crown",(0,0,1.72),0.64,0.07,MAT["OldGold"],15,4)


def emblem(root, planet="mars"):
    if planet=="mars":
        add_cylinder(root,"Mars_Disc",(0,0,0),0.72,0.18,MAT["Ruby"],18,rot=(math.radians(90),0,0),bevel=0.04)
        add_torus(root,"Mars_Ring",(0,0,0),0.76,0.09,MAT["OldGold"],18,4,rot=(math.radians(90),0,0))
        add_cylinder_between(root,"Mars_Arrow",(0.25,0,0.25),(1.05,0,1.05),0.08,MAT["BrightGold"],7)
        add_prism(root,"Mars_ArrowHead",[(0,0.30),(0.28,-0.22),(-0.28,-0.22)],0.14,MAT["BrightGold"],loc=(1.05,0,1.05),rot=(0,0,math.radians(-45)),bevel=0.025)
    else:
        add_cylinder(root,"Mercury_Disc",(0,0,0),0.68,0.18,MAT["Sapphire"],18,rot=(math.radians(90),0,0),bevel=0.04)
        add_torus(root,"Mercury_Ring",(0,0,0.10),0.72,0.085,MAT["OldGold"],18,4,rot=(math.radians(90),0,0))
        add_torus(root,"Mercury_Horns",(0,0,0.55),0.46,0.07,MAT["BrightGold"],16,4,rot=(math.radians(90),0,0))
        add_cylinder_between(root,"Mercury_Stem",(0,0,-0.58),(0,0,-1.10),0.07,MAT["BrightGold"],7)
        add_cylinder_between(root,"Mercury_Cross",(-0.28,0,-0.85),(0.28,0,-0.85),0.07,MAT["BrightGold"],7)
        for side in (-1,1):
            add_prism(root,f"Mercury_Wing{side}",[(0,0),(0.45*side,0.24),(0.34*side,-0.10)],0.12,MAT["Pearl"],loc=(0.56*side,0,0.12),bevel=0.025)


def hermes_boots(root):
    for side in (-1,1):
        x=0.48*side
        add_prism(root,f"Boot{side}_Sole",[(-0.34,-0.35),(0.42,-0.35),(0.58,-0.15),(0.46,0.08),(-0.32,0.08)],0.42,MAT["Leather"],loc=(x,0,-0.68),bevel=0.08)
        add_prism(root,f"Boot{side}_Upper",[(-0.32,-0.60),(0.32,-0.60),(0.32,0.48),(0.08,0.88),(-0.30,0.72)],0.38,MAT["ClothGreen"],loc=(x,0,0.10),bevel=0.07)
        for i in range(3):
            add_cylinder_between(root,f"Boot{side}_Lace{i}",(x-0.24, -0.24, 0.22+i*0.20),(x+0.24,-0.24,0.22+i*0.20),0.035,MAT["BrightGold"],6)
        for wing in range(3):
            add_prism(root,f"Boot{side}_Wing{wing}",[(0,0),(0.60*side,0.18),(0.44*side,-0.16)],0.12,MAT["Pearl"],loc=(x+0.26*side,0,0.55-wing*0.18),rot=(0,0,math.radians(side*(8+wing*8))),bevel=0.025)


def teardrop(root):
    add_cone(root,"Teardrop_Body",(0,0,-0.05),0.62,0.18,1.55,MAT["Sapphire"],vertices=8,bevel=0.015)
    add_ico(root,"Teardrop_Crown",(0,0,0.72),(0.32,0.28,0.34),MAT["Sapphire"],1)
    add_torus(root,"Teardrop_Frame",(0,0,0.10),0.76,0.065,MAT["BrightGold"],16,4,rot=(math.radians(90),0,0))
    add_ico(root,"Teardrop_Hook",(0,0,1.18),(0.15,0.12,0.16),MAT["OldGold"],1)


def signet(root):
    add_torus(root,"Signet_Band",(0,0,-0.25),0.60,0.16,MAT["BrightGold"],16,6,rot=(math.radians(90),0,0))
    add_prism(root,"Signet_Face",[(-0.48,-0.28),(0.48,-0.28),(0.56,0.30),(0.32,0.58),(-0.32,0.58),(-0.56,0.30)],0.32,MAT["BrightGold"],loc=(0,-0.10,0.38),bevel=0.08)
    add_prism(root,"Signet_Inset",[(-0.26,-0.12),(0.26,-0.12),(0.31,0.18),(0,0.38),(-0.31,0.18)],0.35,MAT["Ruby"],loc=(0,-0.18,0.42),bevel=0.04)


def shattered_blade(root, reforged=False):
    if reforged:
        add_sword(root,"ShatteredEdge",MAT["SilverSteel"],MAT["OldGold"],MAT["Leather"],MAT["Teal"],length=3.5,blade_width=0.52,asym=True)
        for z in [0.25,0.82,1.38,1.92]:
            add_prism(root,f"ShatteredEdge_Seam{z}",[(-0.22,z),(0.22,z),(0.18,z+0.10),(-0.16,z+0.05)],0.19,MAT["Teal"],bevel=0.01)
    else:
        add_sword(root,"ShatteredBlade",MAT["Iron"],MAT["DarkIron"],MAT["Leather"],None,length=3.1,blade_width=0.46,broken=True)
        add_prism(root,"ShatteredBlade_TipFragment",[(-0.24,-0.24),(0.20,-0.28),(0.10,0.36),(-0.12,0.62),(-0.28,0.22)],0.14,MAT["Iron"],loc=(0.72,0,1.48),rot=(0,0,math.radians(-28)),bevel=0.02)
        add_prism(root,"ShatteredBlade_Chip",[(-0.12,-0.12),(0.16,-0.08),(0.05,0.22)],0.12,MAT["Iron"],loc=(-0.58,0,0.72),rot=(0,0,math.radians(18)),bevel=0.015)


def meteorite_plate(root):
    add_prism(root,"MeteorPlate_Core",[(-0.92,0.92),(-1.08,0.10),(-0.74,-1.12),(0,-1.42),(0.74,-1.12),(1.08,0.10),(0.92,0.92),(0,1.28)],0.34,MAT["DarkIron"],bevel=0.09)
    add_prism(root,"MeteorPlate_Star",[(0,0.72),(0.18,0.20),(0.72,0.18),(0.28,-0.12),(0.44,-0.70),(0,-0.34),(-0.44,-0.70),(-0.28,-0.12),(-0.72,0.18),(-0.18,0.20)],0.40,MAT["SilverSteel"],loc=(0,-0.12,0),bevel=0.04)
    for i in range(10):
        a=2*math.pi*i/10
        add_ico(root,f"MeteorPlate_Rivet{i}",(0.86*math.cos(a),-0.24,0.06+0.92*math.sin(a)),(0.07,0.05,0.07),MAT["OldGold"],1)
    add_ico(root,"MeteorPlate_CoreGem",(0,-0.30,0),(0.18,0.10,0.18),MAT["Teal"],1)


def drink(root, kind):
    if kind in ("ale","stout"):
        liquid=MAT["Ale"] if kind=="ale" else MAT["Stout"]
        height=1.6 if kind=="ale" else 1.9
        radius=0.66 if kind=="ale" else 0.58
        add_cylinder(root,"Drink_MugBody",(0,0,0),radius,height,MAT["Wood"],10,bevel=0.06)
        add_cylinder(root,"Drink_Liquid",(0,0,height*0.46),radius*0.88,0.12,liquid,10,bevel=0.01)
        for i in range(5 if kind=="stout" else 3):
            a=2*math.pi*i/(5 if kind=="stout" else 3)
            add_ico(root,f"Drink_Foam{i}",(radius*0.48*math.cos(a),radius*0.48*math.sin(a),height*0.56),(0.28,0.24,0.18),MAT["Foam"],1)
        # angular U handle
        add_cylinder_between(root,"Drink_HandleTop",(radius,0,0.42),(radius+0.50,0,0.42),0.09,MAT["Wood"],8)
        add_cylinder_between(root,"Drink_HandleSide",(radius+0.50,0,0.42),(radius+0.50,0,-0.38),0.09,MAT["Wood"],8)
        add_cylinder_between(root,"Drink_HandleBottom",(radius+0.50,0,-0.38),(radius,0,-0.38),0.09,MAT["Wood"],8)
        add_torus(root,"Drink_Rim",(0,0,height*0.50),radius,0.06,MAT["OldGold"],14,4)
    else:
        add_cylinder(root,"Wine_Stem",(0,0,-0.55),0.08,0.88,MAT["GlassClear"],8,bevel=0.015)
        add_cylinder(root,"Wine_Base",(0,0,-1.02),0.50,0.10,MAT["GlassClear"],12,bevel=0.025)
        add_cone(root,"Wine_Bowl",(0,0,0.20),0.54,0.36,1.25,MAT["GlassClear"],12,bevel=0.025)
        add_cone(root,"Wine_Liquid",(0,0,0.16),0.45,0.31,0.62,MAT["Wine"],12,bevel=0.01)
        add_torus(root,"Wine_Rim",(0,0,0.82),0.36,0.035,MAT["OldGold"],14,4)


def scrap_plating(root):
    plates=[(-0.50,0.30,0.80,0.55,12),(0.36,0.16,0.72,0.50,-10),(-0.12,-0.56,0.82,0.42,6)]
    for i,(x,z,sx,sz,ang) in enumerate(plates):
        add_cube(root,f"Scrap_Plate{i}",(x,0,z),(sx,0.15,sz),MAT["Iron"],rot=(0,0,math.radians(ang)),bevel=0.07)
        for k in (-1,1):
            add_ico(root,f"Scrap_Rivet{i}_{k}",(x+k*sx*0.68,-0.18,z+k*sz*0.60),(0.07,0.05,0.07),MAT["OldGold"],1)
    add_cube(root,"Scrap_Strap1",(0,-0.24,0.42),(1.05,0.06,0.10),MAT["Leather"],rot=(0,0,math.radians(18)),bevel=0.03)
    add_cube(root,"Scrap_Strap2",(0,-0.24,-0.26),(1.05,0.06,0.10),MAT["Leather"],rot=(0,0,math.radians(-14)),bevel=0.03)


def food_bowl(root, burnt=False):
    add_cone(root,"Bowl",(0,0,-0.40),0.85,0.58,0.50,MAT["Iron"],12,bevel=0.05)
    mat=MAT["Char"] if burnt else MAT["Sludge"]
    for i,(x,y,z,s) in enumerate([(-0.35,0.12,-0.08,0.45),(0.28,-0.12,-0.02,0.52),(0.05,0.18,0.20,0.38),(-0.10,-0.22,0.35,0.30)]):
        add_ico(root,f"Food_Lump{i}",(x,y,z),(s,s*0.76,s*0.62),mat,1)
    if burnt:
        add_cylinder_between(root,"Burnt_Utensil",(-0.75,0,-0.05),(0.82,0,0.75),0.055,MAT["Wood"],7)
    else:
        add_ico(root,"Sludge_Bubble",(0.32,-0.25,0.32),(0.18,0.14,0.18),MAT["Ectoplasm"],1)


def ambrosia(root):
    add_cone(root,"Ambrosia_Bowl",(0,0,-0.42),0.92,0.62,0.52,MAT["BrightGold"],14,bevel=0.06)
    add_torus(root,"Ambrosia_Rim",(0,0,-0.12),0.78,0.07,MAT["Pearl"],16,4)
    colors=[MAT["Ruby"],MAT["Emerald"],MAT["Sapphire"],MAT["Pearl"]]
    for i in range(9):
        a=2*math.pi*i/9
        r=0.46 if i<6 else 0.20
        add_ico(root,f"Ambrosia_Fruit{i}",(r*math.cos(a),r*math.sin(a),0.12+(i%3)*0.18),(0.24,0.22,0.24),colors[i%4],1)
    add_prism(root,"Ambrosia_Leaf",[(-0.12,-0.45),(0,0.52),(0.12,-0.45)],0.08,MAT["ClothGreen"],loc=(0.58,-0.18,0.50),rot=(0,0,math.radians(-28)),bevel=0.02)


def philosopher_stone(root):
    add_ico(root,"Philosopher_Core",(0,0,0),(0.72,0.62,0.84),MAT["Ruby"],2)
    add_torus(root,"Philosopher_RingX",(0,0,0),0.98,0.07,MAT["BrightGold"],18,4,rot=(math.radians(90),0,0))
    add_torus(root,"Philosopher_RingY",(0,0,0),0.98,0.07,MAT["BrightGold"],18,4,rot=(0,math.radians(90),0))
    add_torus(root,"Philosopher_RingZ",(0,0,0),0.98,0.07,MAT["OldGold"],18,4)
    for i in range(4):
        a=2*math.pi*i/4
        add_ico(root,f"Philosopher_Node{i}",(0.98*math.cos(a),0,0.98*math.sin(a)),(0.12,0.10,0.12),MAT["Pearl"],1)


def chrysalis_sigil(root):
    add_prism(root,"Chrysalis_Core",[(0,1.10),(0.46,0.46),(0.34,-0.72),(0,-1.16),(-0.34,-0.72),(-0.46,0.46)],0.24,MAT["Pearl"],bevel=0.07)
    add_torus(root,"Chrysalis_Frame",(0,0,0),0.92,0.09,MAT["BrightGold"],18,4,rot=(math.radians(90),0,0))
    for side in (-1,1):
        add_prism(root,f"Chrysalis_Wing{side}",[(0,0.52),(0.78*side,0.94),(0.56*side,0.10),(0.88*side,-0.64),(0,-0.30)],0.14,MAT["OldGold"],loc=(0,-0.05,0),bevel=0.04)
    add_ico(root,"Chrysalis_Gem",(0,-0.20,0.12),(0.20,0.10,0.25),MAT["Emerald"],1)


def obsidian_shard(root):
    add_prism(root,"ObsidianShard_Main",[(-0.36,-1.02),(0.12,-0.82),(0.52,-0.18),(0.28,0.94),(-0.08,1.42),(-0.30,0.56),(-0.56,-0.12)],0.34,MAT["Obsidian"],rot=(0,0,math.radians(-8)),bevel=0.02)
    add_prism(root,"ObsidianShard_Edge",[(-0.10,-0.80),(0.10,-0.56),(0.22,0.62),(0.02,1.08)],0.38,MAT["Amethyst"],loc=(0,-0.04,0),bevel=0.01)
    add_ico(root,"ObsidianShard_Base",(0,0,-1.05),(0.52,0.34,0.24),MAT["DarkIron"],1)


def melted_wax(root):
    for i,(x,y,sx,sy,sz) in enumerate([(-0.38,0.10,0.62,0.42,0.16),(0.35,-0.12,0.70,0.50,0.14),(0.02,0.28,0.52,0.40,0.20)]):
        add_ico(root,f"Wax_Puddle{i}",(x,y,-0.72),(sx,sy,sz),MAT["Wax"],1)
    add_cylinder(root,"Wax_Stub",(0,0,-0.10),0.34,1.15,MAT["Wax"],10,bevel=0.05)
    add_cone(root,"Wax_Flame",(0,0,0.72),0.16,0,0.55,MAT["Cinder"],8,bevel=0.01)
    for i,z in enumerate([0.24,-0.10,-0.42]):
        add_ico(root,f"Wax_Drip{i}",(0.31,-0.16,z),(0.10,0.07,0.18),MAT["Wax"],1)


def ectoplasm(root):
    add_cylinder(root,"Ecto_Jar",(0,0,-0.05),0.68,1.65,MAT["GlassClear"],12,bevel=0.05)
    add_torus(root,"Ecto_Rim",(0,0,0.82),0.69,0.07,MAT["OldGold"],14,4)
    add_cylinder(root,"Ecto_Lid",(0,0,0.94),0.52,0.18,MAT["OldGold"],12,bevel=0.04)
    for i,(x,y,z,s) in enumerate([(-0.22,0,0.18,0.40),(0.24,0.10,-0.18,0.46),(0,-0.12,-0.50,0.36),(0.05,0.05,0.56,0.28)]):
        add_ico(root,f"Ecto_Blob{i}",(x,y,z),(s,s*0.72,s*0.85),MAT["Ectoplasm"],1)
    add_ico(root,"Ecto_EyeL",(-0.16,-0.48,0.28),(0.05,0.03,0.06),MAT["Obsidian"],1)
    add_ico(root,"Ecto_EyeR",(0.16,-0.48,0.28),(0.05,0.03,0.06),MAT["Obsidian"],1)


def warding_charm(root):
    add_prism(root,"Warding_Shield",[(-0.78,0.72),(0,1.02),(0.78,0.72),(0.64,-0.42),(0,-1.14),(-0.64,-0.42)],0.22,MAT["OldGold"],bevel=0.07)
    add_prism(root,"Warding_Inset",[(-0.52,0.54),(0,0.76),(0.52,0.54),(0.40,-0.30),(0,-0.84),(-0.40,-0.30)],0.28,MAT["Pearl"],loc=(0,-0.10,0),bevel=0.05)
    add_ico(root,"Warding_Eye",(0,-0.22,0.05),(0.26,0.10,0.18),MAT["Sapphire"],1)
    add_torus(root,"Warding_Loop",(0,0,1.15),0.24,0.055,MAT["BrightGold"],12,4,rot=(math.radians(90),0,0))


def second_breath_vial(root):
    add_cone(root,"SecondBreath_Bottle",(0,0,-0.15),0.48,0.30,1.65,MAT["GlassBlue"],12,bevel=0.04)
    add_cylinder(root,"SecondBreath_Liquid",(0,0,-0.34),0.36,0.88,MAT["LiquidBlue"],12,bevel=0.02)
    add_cylinder(root,"SecondBreath_Stopper",(0,0,0.82),0.28,0.36,MAT["Pearl"],10,bevel=0.035)
    add_torus(root,"SecondBreath_Band",(0,0,0.52),0.34,0.055,MAT["OldGold"],12,4)
    for i in range(2):
        a=(-1 if i==0 else 1)*0.48
        add_helix(root,f"BreathSpiral{i}",(a*0.35,-0.10,0.05),0.18,1.3,1.4,14,0.035,MAT["BrightGold"])


def thrice_bead(root):
    pts=[(-0.78,0,0.56),(-0.42,0,0.84),(0,0,0.94),(0.42,0,0.84),(0.78,0,0.56),(0.58,0,0.08),(0.28,0,-0.42),(0,0,-0.78)]
    add_bead_string(root,pts,[1,2,3],MAT["Leather"],MAT["Pearl"],0.18)
    for i,p in enumerate([(-0.42,0,0.84),(0,0,0.94),(0.42,0,0.84)]):
        add_torus(root,f"BlessedHalo{i}",p,0.24,0.035,MAT["BrightGold"],12,4,rot=(math.radians(90),0,0))
    for side in (-1,1):
        add_cylinder_between(root,f"Bead_Tassel{side}",(0,0,-0.78),(0.22*side,0,-1.38),0.04,MAT["ClothRed"],6)


def tome(root):
    add_cube(root,"Tome_Pages",(0,0,0),(0.90,0.26,1.16),MAT["Paper"],bevel=0.06)
    add_cube(root,"Tome_CoverFront",(0,-0.34,0),(0.98,0.08,1.24),MAT["ClothGreen"],bevel=0.07)
    add_cube(root,"Tome_CoverBack",(0,0.34,0),(0.98,0.08,1.24),MAT["ClothGreen"],bevel=0.07)
    add_cube(root,"Tome_Spine",(-0.96,0,0),(0.08,0.34,1.24),MAT["OldGold"],bevel=0.04)
    add_torus(root,"Tome_Emblem",(0,-0.44,0.08),0.46,0.06,MAT["BrightGold"],14,4,rot=(math.radians(90),0,0))
    add_prism(root,"Tome_WindMark",[(-0.42,0.05),(-0.08,0.32),(0.26,0.14),(0.46,0.36),(0.24,-0.10),(-0.18,-0.28)],0.16,MAT["Teal"],loc=(0,-0.52,0),bevel=0.025)
    for z in (-0.76,0.78):
        add_cube(root,f"Tome_Corner{z}",(0.76,-0.44,z),(0.16,0.08,0.16),MAT["OldGold"],bevel=0.035)


def whetstone_draught(root):
    add_cone(root,"Whetstone_Bottle",(0,0,-0.18),0.56,0.34,1.72,MAT["GlassRed"],12,bevel=0.04)
    add_cylinder(root,"Whetstone_Liquid",(0,0,-0.38),0.42,0.88,MAT["LiquidRed"],12,bevel=0.02)
    add_cylinder(root,"Whetstone_Stopper",(0,0,0.84),0.30,0.36,MAT["Iron"],10,bevel=0.035)
    add_torus(root,"Whetstone_Ring",(0,0,0.16),0.62,0.13,MAT["Iron"],14,5,rot=(math.radians(90),0,0))
    add_ico(root,"Whetstone_Chip",(0.56,-0.22,0.12),(0.24,0.12,0.28),MAT["SilverSteel"],1)


def black_hinge(root):
    for side in (-1,1):
        add_cube(root,f"Hinge_Plate{side}",(0.58*side,0,0),(0.55,0.18,0.92),MAT["DarkIron"],bevel=0.08)
        for z in (-0.58,0.58):
            add_ico(root,f"Hinge_Rivet{side}_{z}",(0.58*side,-0.22,z),(0.10,0.06,0.10),MAT["OldGold"],1)
    add_cylinder(root,"Hinge_Pin",(0,0,0),0.18,2.2,MAT["Iron"],10,bevel=0.05)
    add_ico(root,"Hinge_PinTop",(0,0,1.16),(0.28,0.22,0.18),MAT["Obsidian"],1)
    add_ico(root,"Hinge_PinBottom",(0,0,-1.16),(0.28,0.22,0.18),MAT["Obsidian"],1)


def ember_bit(root):
    add_ico(root,"Ember_Core",(0,0,0),(0.62,0.48,0.72),MAT["Cinder"],2)
    for i in range(4):
        a=2*math.pi*i/4
        add_cylinder_between(root,f"Ember_Bridle{i}",(0.44*math.cos(a),0.44*math.sin(a),-0.50),(0.44*math.cos(a),0.44*math.sin(a),0.55),0.07,MAT["DarkIron"],7)
    add_torus(root,"Ember_RingTop",(0,0,0.56),0.50,0.07,MAT["OldGold"],14,4)
    add_torus(root,"Ember_RingBottom",(0,0,-0.54),0.50,0.07,MAT["OldGold"],14,4)


def qilin_bell(root):
    add_cone(root,"QilinBell_Body",(0,0,-0.14),0.72,0.38,1.15,MAT["BrightGold"],12,bevel=0.055)
    add_torus(root,"QilinBell_Rim",(0,0,-0.72),0.72,0.08,MAT["OldGold"],14,4)
    add_torus(root,"QilinBell_Handle",(0,0,0.72),0.36,0.075,MAT["OldGold"],14,4,rot=(math.radians(90),0,0))
    add_cylinder(root,"QilinBell_Clapper",(0,0,-0.82),0.07,0.74,MAT["DarkIron"],7,bevel=0.02)
    add_ico(root,"QilinBell_ClapperBall",(0,0,-1.22),(0.18,0.16,0.18),MAT["DarkIron"],1)
    for side in (-1,1):
        add_prism(root,f"QilinBell_Horn{side}",[(0,-0.10),(0.68*side,0.24),(0.42*side,-0.22)],0.14,MAT["Teal"],loc=(0.42*side,0,0.22),bevel=0.03)


def cinder_ruby(root):
    add_ico(root,"CinderRuby_Core",(0,0,0),(0.64,0.52,0.84),MAT["Ruby"],2)
    for i in range(5):
        a=2*math.pi*i/5
        add_cylinder_between(root,f"CinderRuby_Cage{i}",(0.50*math.cos(a),0.50*math.sin(a),-0.72),(0.38*math.cos(a),0.38*math.sin(a),0.78),0.055,MAT["Char"],7)
    add_torus(root,"CinderRuby_Crown",(0,0,0.78),0.42,0.06,MAT["Cinder"],12,4)
    add_ico(root,"CinderRuby_Coal",(0,-0.56,-0.08),(0.16,0.09,0.20),MAT["Char"],1)


def abyssal_pearl(root):
    add_ico(root,"AbyssalPearl",(0,0,0),(0.68,0.62,0.68),MAT["Pearl"],2)
    add_prism(root,"AbyssalShellL",[(-0.18,-0.86),(-0.82,-0.22),(-0.72,0.72),(-0.16,0.42)],0.22,MAT["Obsidian"],loc=(-0.42,0,0),rot=(0,0,math.radians(-8)),bevel=0.06)
    add_prism(root,"AbyssalShellR",[(0.18,-0.86),(0.82,-0.22),(0.72,0.72),(0.16,0.42)],0.22,MAT["Obsidian"],loc=(0.42,0,0),rot=(0,0,math.radians(8)),bevel=0.06)
    add_torus(root,"AbyssalHalo",(0,0,0),1.02,0.055,MAT["Sapphire"],16,4,rot=(math.radians(90),0,0))


def verdigris_coin(root):
    add_cylinder(root,"VerdigrisCoin_Body",(0,0,0),0.92,0.22,MAT["Verdigris"],18,rot=(math.radians(90),0,0),bevel=0.055)
    add_torus(root,"VerdigrisCoin_Rim",(0,-0.14,0),0.78,0.08,MAT["OldGold"],18,4,rot=(math.radians(90),0,0))
    add_torus(root,"VerdigrisCoin_Inner",(0,-0.18,0),0.42,0.05,MAT["BrightGold"],16,4,rot=(math.radians(90),0,0))
    add_prism(root,"VerdigrisCoin_Mark",[(-0.12,-0.48),(0.18,-0.18),(0.06,0.04),(0.32,0.40),(0.02,0.62),(-0.24,0.24)],0.28,MAT["Pearl"],loc=(0,-0.18,0),bevel=0.025)
    add_prism(root,"VerdigrisCoin_Notch",[(-0.16,-0.12),(0.16,-0.12),(0.10,0.22),(-0.10,0.22)],0.30,MAT["DarkIron"],loc=(0.70,-0.16,0.40),rot=(0,0,math.radians(-35)),bevel=0.02)

# -----------------------------------------------------------------------------
# Build all roots in a 7x7 gallery
# -----------------------------------------------------------------------------
items=[]
def add_item(display, export_name, category, builder, description=""):
    idx=len(items)
    cols=7
    spacing_x=5.0; spacing_z=4.55
    col=idx%cols; row=idx//cols
    x=(col-(cols-1)/2)*spacing_x
    z=((6-row)-3)*spacing_z
    root=create_root(display,export_name,(x,0,z),category,description)
    builder(root)
    items.append((display,export_name,category,root))

add_item("Bottle Family", "bottle_family", "Consumables", bottle_family, "Basis plus Tall, Round, Angular and Molten shape keys")
add_item("Silver Blade", "silver_blade", "Weapons", lambda r:add_sword(r,"SilverBlade",MAT["SilverSteel"],MAT["OldGold"],MAT["Leather"],MAT["Ruby"],3.15,0.44,0.14,1.30))
add_item("Wind Charm", "wind_charm", "Accessories", wind_charm)
add_item("Crystal Cluster", "crystal", "Relics", crystal_cluster)
add_item("Question Mark", "placeholder_question", "Placeholder", question_mark)
add_item("Bone Plate", "bone_plate", "Armor", bone_plate)
add_item("Rear Mirror", "rear_mirror", "Accessories", rear_mirror)
add_item("Mystic Egg", "mystic_egg", "Relics", lambda r:egg(r,False))
add_item("Golden Egg", "golden_egg", "Relics", lambda r:egg(r,True))
add_item("Vitality Seal I", "vitality_seal_1", "Accessories", lambda r:vitality_seal(r,1))
add_item("Vitality Seal II", "vitality_seal_2", "Accessories", lambda r:vitality_seal(r,2))
add_item("Vitality Seal III", "vitality_seal_3", "Accessories", lambda r:vitality_seal(r,3))
add_item("Radiant Blade Flavio", "radiant_blade_flavio", "Weapons", lambda r:add_sword(r,"RadiantBlade",MAT["WhiteHoly"],MAT["BrightGold"],MAT["ClothRed"],MAT["Ruby"],3.55,0.54,0.15,1.55,sun_guard=True))
add_item("Wind Dancer", "wind_dancer", "Weapons", wind_dancer)
add_item("Water Scepter", "water_scepter", "Weapons", water_scepter)
add_item("Holy Sword Gram", "holy_sword_gram", "Weapons", lambda r:add_sword(r,"HolyGram",MAT["WhiteHoly"],MAT["BrightGold"],MAT["Leather"],MAT["Sapphire"],3.85,0.58,0.16,1.55,wing_guard=True))
add_item("Dark Scepter Lucille", "dark_scepter_lucille", "Weapons", dark_scepter)
add_item("Mars Emblem", "mars_emblem", "Accessories", lambda r:emblem(r,"mars"))
add_item("Mercury Crest", "mercury_crest", "Accessories", lambda r:emblem(r,"mercury"))
add_item("Hermes' Boots", "hermes_boots", "Accessories", hermes_boots)
add_item("Glittering Teardrop", "glittering_teardrop", "Quest", teardrop)
add_item("Untarnished Signet", "untarnished_signet", "Quest", signet)
add_item("Shattered Blade", "shattered_blade", "Quest", lambda r:shattered_blade(r,False))
add_item("Shattered Edge", "shattered_edge", "Weapons", lambda r:shattered_blade(r,True))
add_item("Meteorite Plate", "meteorite_plate", "Armor", meteorite_plate)
add_item("Mug of Ale", "mug_of_ale", "Consumables", lambda r:drink(r,"ale"))
add_item("Pint of Stout", "pint_of_stout", "Consumables", lambda r:drink(r,"stout"))
add_item("Glass of Wine", "glass_of_wine", "Consumables", lambda r:drink(r,"wine"))
add_item("Scrap Plating", "scrap_plating", "Armor", scrap_plating)
add_item("Sludge", "sludge", "Consumables", lambda r:food_bowl(r,False))
add_item("Burnt Slop", "burnt_slop", "Consumables", lambda r:food_bowl(r,True))
add_item("Broken Spring", "broken_spring", "Accessories", lambda r:add_helix(r,"BrokenSpring",(0,0,0),0.62,2.35,2.6,28,0.095,MAT["Iron"]))
add_item("Ambrosia", "ambrosia", "Consumables", ambrosia)
add_item("Philosopher's Stone", "philosophers_stone", "Relics", philosopher_stone)
add_item("Chrysalis Sigil", "chrysalis_sigil", "Quest", chrysalis_sigil)
add_item("Obsidian Shard", "obsidian_shard", "Materials", obsidian_shard)
add_item("Melted Wax", "melted_wax", "Materials", melted_wax)
add_item("Ectoplasm", "ectoplasm", "Materials", ectoplasm)
add_item("Warding Charm", "warding_charm", "Accessories", warding_charm)
add_item("Vial of Second Breath", "vial_of_second_breath", "Accessories", second_breath_vial)
add_item("Thrice-Blessed Bead", "thrice_blessed_bead", "Accessories", thrice_bead)
add_item("Tome: Wind Blade", "tome_wind_blade", "Consumables", tome)
add_item("Whetstone Draught", "whetstone_draught", "Consumables", whetstone_draught)
add_item("Black Hinge", "black_hinge", "Promotion Keys", black_hinge)
add_item("Ember Bit", "ember_bit", "Promotion Keys", ember_bit)
add_item("Qilin Bell", "qilin_bell", "Promotion Keys", qilin_bell)
add_item("Cinder Ruby", "cinder_ruby", "Promotion Keys", cinder_ruby)
add_item("Abyssal Pearl", "abyssal_pearl", "Promotion Keys", abyssal_pearl)
add_item("Verdigris Coin", "verdigris_coin", "Promotion Keys", verdigris_coin)

assert len(items)==49, len(items)

# -----------------------------------------------------------------------------
# Preview scene
# -----------------------------------------------------------------------------
# Slot backings and labels are not children of item roots, so the exporter ignores them.
for display, export_name, category, root in items:
    bpy.ops.mesh.primitive_cube_add(size=2, location=(root.location.x, 0.92, root.location.z))
    panel=bpy.context.object
    panel.name="PreviewSlot_"+export_name
    panel.scale=(2.28,0.06,1.94)
    assign_material(panel,MAT["Slot"])
    add_bevel(panel,0.12,2)
    move_to_collection(panel,PREVIEW_COLLECTION)

    bpy.ops.object.text_add(location=(root.location.x,-0.48,root.location.z-1.88), rotation=(math.radians(90),0,0))
    txt=bpy.context.object
    txt.name="Label_"+export_name
    txt.data.body=display
    txt.data.align_x='CENTER'
    txt.data.align_y='CENTER'
    txt.data.size=0.30 if len(display)<20 else 0.24
    txt.data.extrude=0.006
    txt.data.bevel_depth=0.003
    txt.data.materials.append(MAT["Text"])
    move_to_collection(txt,PREVIEW_COLLECTION)

# Large backdrop
bpy.ops.mesh.primitive_cube_add(size=2, location=(0,2.4,0))
back=bpy.context.object
back.name="PreviewBackdrop"
back.scale=(18.7,0.10,16.5)
assign_material(back,MAT["Backdrop"])
move_to_collection(back,PREVIEW_COLLECTION)

scene=bpy.context.scene
scene.render.engine='BLENDER_WORKBENCH'
scene.display.shading.light='STUDIO'
scene.display.shading.color_type='MATERIAL'
scene.display.shading.show_shadows=True
scene.display.shading.show_cavity=True
scene.display.shading.cavity_type='WORLD'
scene.render.resolution_x=2100
scene.render.resolution_y=2100
scene.render.resolution_percentage=70
scene.render.image_settings.file_format='PNG'
scene.render.image_settings.color_mode='RGBA'
scene.render.film_transparent=False
scene.render.filepath=str(PREVIEW_PATH)
scene.world.color=(0.008,0.010,0.018)

# Camera slightly off-axis for depth readability.
bpy.ops.object.camera_add(location=(4.0,-56.0,2.5))
cam=bpy.context.object
cam.name="PreviewCamera"
target=Vector((0,0,0))
cam.rotation_euler=(target-Vector(cam.location)).to_track_quat('-Z','Y').to_euler()
cam.data.type='ORTHO'
cam.data.ortho_scale=34.0
cam.data.lens=52
scene.camera=cam
move_to_collection(cam,PREVIEW_COLLECTION)

# Broad three-point-ish lighting.
def area_light(name, loc, energy, size, color):
    bpy.ops.object.light_add(type='AREA', location=loc)
    light=bpy.context.object
    light.name=name
    light.data.energy=energy
    light.data.shape='DISK'
    light.data.size=size
    light.data.color=color
    light.rotation_euler=(Vector((0,0,0))-Vector(loc)).to_track_quat('-Z','Y').to_euler()
    move_to_collection(light,PREVIEW_COLLECTION)

area_light("Preview_Key",(-12,-18,18),2100,12,(1.0,0.88,0.72))
area_light("Preview_Fill",(14,-12,6),1450,14,(0.54,0.68,1.0))
area_light("Preview_Rim",(0,6,16),1800,10,(0.42,0.72,1.0))

# Add embedded scripts and readme.
exporter_text=EXPORTER_PATH.read_text(encoding='utf-8')
text=bpy.data.texts.get("second_rite_item_exporter.py") or bpy.data.texts.new("second_rite_item_exporter.py")
text.clear(); text.write(exporter_text)
readme=bpy.data.texts.get("README_ITEM_MODEL_LIBRARY.md") or bpy.data.texts.new("README_ITEM_MODEL_LIBRARY.md")
readme.write("""# Second Rite Expanded Item Model Library\n\n"
"Blender 5.0+ procedural low-poly item library.\n\n"
"- 49 top-level export roots\n"
"- 53 expected static OBJ outputs because Bottle Family exports Basis + 4 shape keys\n"
"- Each root is placed in a 7x7 gallery but exports with its pivot at 0,0,0\n"
"- Select one or more top-level roots, run second_rite_item_exporter.py, and use View3D > Sidebar > Second Rite\n"
"- Export All Marked Items exports every root with item_export=true\n"
"- Preview labels and backings are not parented to roots and are never exported\n"
"- Materials use simple MTL-compatible diffuse colors suitable for the current LÖVE OBJ loader\n"
"""
)

# Set useful scene metadata.
scene["second_rite_library_version"]="2.0"
scene["item_root_count"]=len(items)
scene["expected_obj_count"]=53
scene["blender_minimum_version"]="5.0"
scene["exporter_text_block"]="second_rite_item_exporter.py"

# Save before export so the artifact survives even if validation later fails.
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

# Register exporter and export all marked roots.
spec=importlib.util.spec_from_file_location("second_rite_item_exporter",EXPORTER_PATH)
exporter=importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)
exporter.register()
outputs=exporter.export_roots(bpy.context, ROOTS, EXPORT_DIR,
                              export_shape_keys=True, include_basis=True, center_mode="PIVOT")

# Render preview after export.
bpy.ops.render.render(write_still=True)

# Write manifest.
lines=[
    "# Second Rite Expanded Item Model Library",
    "",
    f"Generated with Blender {bpy.app.version_string}.",
    "",
    f"- Export roots: **{len(items)}**",
    f"- Static OBJ outputs: **{len(outputs)}**",
    "- Pivot export mode: **root pivot to 0,0,0**",
    "- Bottle Family variants: **basis, tall, round, angular, molten**",
    "",
    "## Models",
    "",
]
for display, export_name, category, root in items:
    lines.append(f"- `{export_name}` — {display} ({category})")
lines += ["", "## Exported files", ""]
for out in sorted(outputs):
    lines.append(f"- `{Path(out).name}`")
MANIFEST_PATH.write_text("\n".join(lines)+"\n",encoding='utf-8')

# Basic assertions.
assert BLEND_PATH.exists() and BLEND_PATH.stat().st_size > 100_000
assert PREVIEW_PATH.exists() and PREVIEW_PATH.stat().st_size > 10_000
assert len(outputs)==53, f"Expected 53 OBJ outputs, got {len(outputs)}"
for output in outputs:
    p=Path(output)
    assert p.exists() and p.stat().st_size>100, output

print(f"BUILT_BLEND={BLEND_PATH}")
print(f"BUILT_PREVIEW={PREVIEW_PATH}")
print(f"ROOT_COUNT={len(items)}")
print(f"OBJ_COUNT={len(outputs)}")
