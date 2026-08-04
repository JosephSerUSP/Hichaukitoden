"""Procedural bpy scenes whose orthographic depth becomes a height map.

Runs inside Blender only. Each builder fills the unit tile x,y in [0,1] with
real geometry and returns the axes that must wrap; `render_depth.py` samples it.

Two rules make the output usable downstream, and both are structural rather
than cosmetic:

  1. THE TILE IS A PERIOD, NOT A CROP. A shape that crosses x=1 has to come
     back at x=0 or the wall shows a seam every 64 pixels. Builders never place
     a straddling shape by hand; they declare the wrap axes and let
     `wrap_copies` link the offset duplicates, so the period is enforced by
     construction instead of by care.

  2. THE CAMERA IS THE VIEWER, AND A CEILING IS SEEN FROM BELOW. Walls and
     floors are sampled looking down -Z; ceilings are sampled looking up +Z,
     declared per preset in `VIEW`. Sampling a ceiling from above returns the
     flat back of the slab -- the extrados nobody in the corridor can see --
     and the coffers, which are cut into the underside, vanish entirely. The
     builder always models the surface the eye meets; `VIEW` says which eye.
"""

import math

import bmesh
import bpy


# Geometry sits between these two planes. The base surface is the wall/floor
# face itself; relief rises toward the camera and recesses fall away from it.
BASE_Z = 0.0
DEPTH_RANGE = 0.25


def _clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _mesh_from_bmesh(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def slab(name, centre, size, spin=0.0):
    """A box, given as centre and full extent, optionally spun about its own Z.

    The spin is applied to the mesh rather than to `rotation_euler` because the
    object origin stays at the world origin here; setting the object rotation
    would swing the box around the corner of the tile instead of its own axis.
    """
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if spin:
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=_rotation_matrix("Z", spin))
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    return _mesh_from_bmesh(name, bm)


def cylinder(name, centre, radius, depth, axis="Z", segments=48, rise=None):
    """A cylinder, optionally flattened to an elliptical section.

    `rise` replaces the radius in Z after the axis rotation, which is what turns
    a barrel into a shallow vault: a true circular barrel wide enough to reach
    the springing at both tile edges is also half a tile deep, so subtracting it
    punches through the ceiling slab instead of carving a soffit.
    """
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius, radius2=radius, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts,
                         matrix=_rotation_matrix("Y", math.pi / 2))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts,
                         matrix=_rotation_matrix("X", math.pi / 2))
    if rise is not None:
        bmesh.ops.scale(bm, vec=(1.0, 1.0, rise / radius), verts=bm.verts)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    return _mesh_from_bmesh(name, bm)


def cone(name, centre, radius_bottom, radius_top, depth, segments=32):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius_bottom, radius2=radius_top, depth=depth)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    return _mesh_from_bmesh(name, bm)


def sphere(name, centre, radius, segments=32):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2,
                              radius=radius)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    return _mesh_from_bmesh(name, bm)


def _rotation_matrix(axis, angle):
    from mathutils import Matrix
    return Matrix.Rotation(angle, 4, axis)


def bevel(obj, width, segments=3):
    """Round an edge so depth-to-image reads it as stone, not as a cut."""
    modifier = obj.modifiers.new(name="bevel", type="BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(30)
    return obj


def boolean(target, cutter, operation="DIFFERENCE"):
    """Carve `cutter` out of `target` and hide the cutter from sampling."""
    modifier = target.modifiers.new(name="bool", type="BOOLEAN")
    modifier.operation = operation
    modifier.object = cutter
    modifier.solver = "EXACT"
    # Deliberately left visible: a hidden object drops out of the depsgraph and
    # the boolean has nothing to evaluate against. `_bake_modifiers` deletes
    # cutters after baking, which is what keeps them out of the depth raycast.
    cutter["is_cutter"] = True
    cutter["cut_target"] = target.name
    cutter["cut_operation"] = operation
    return target


def _wrap_cutters(axes):
    """Give every edge-crossing cutter its counterpart on the opposite edge.

    Wrapping the solids is only half the period. A groove centred on x=0 removes
    stone at the left edge and nothing at the right, so the tile stops matching
    itself -- measured as a seam eleven times the interior gradient on the first
    version of the niche wall. Cutters wrap for the same reason and by the same
    rule as the shapes they cut into.
    """
    for cutter in [o for o in list(bpy.context.collection.objects)
                   if o.get("is_cutter")]:
        target = bpy.data.objects.get(cutter["cut_target"])
        if target is None:
            continue
        steps = {axis: ((-1.0, 0.0, 1.0) if axis in axes and _extent(cutter, axis) < 1.0
                        else (0.0,))
                 for axis in ("x", "y")}
        for dx in steps["x"]:
            for dy in steps["y"]:
                if dx == 0.0 and dy == 0.0:
                    continue
                copy = cutter.copy()
                copy.data = cutter.data
                copy.location = (cutter.location.x + dx, cutter.location.y + dy,
                                 cutter.location.z)
                bpy.context.collection.objects.link(copy)
                boolean(target, copy, cutter["cut_operation"])


def _extent(obj, axis):
    index = "xyz".index(axis)
    from mathutils import Vector
    values = [(obj.matrix_world @ Vector(corner))[index] for corner in obj.bound_box]
    return max(values) - min(values)


def wrap_copies(objects, axes):
    """Link duplicates one period away so shapes re-enter on the far side.

    A shape already WIDER than the period is skipped on that axis, and this is
    load-bearing rather than an optimisation. The base slabs are modelled four
    units across so a wall never runs out before the tile edge; duplicating one
    of those puts a second, full-thickness copy over the whole tile, and since
    the copy carries its relief a period away, every recess in the original is
    filled in by solid stone. That is precisely how the arched niche and all
    four ceiling coffers went missing while the flat courses -- which look the
    same under a shift -- appeared to survive.
    """
    made = []
    for obj in list(objects):
        if obj.get("is_cutter"):
            continue
        steps = {axis: ((-1.0, 0.0, 1.0) if axis in axes and _extent(obj, axis) < 1.0
                        else (0.0,))
                 for axis in ("x", "y")}
        for dx in steps["x"]:
            for dy in steps["y"]:
                if dx == 0.0 and dy == 0.0:
                    continue
                copy = obj.copy()
                copy.data = obj.data
                copy.location = (obj.location.x + dx, obj.location.y + dy,
                                 obj.location.z)
                bpy.context.collection.objects.link(copy)
                made.append(copy)
    return made


def backplane(z=BASE_Z, margin=2.0, facing="up"):
    """The surface everything else stands on, wide enough to never end.

    It exists so no ray can miss. `facing` puts its mass on the far side of the
    viewer's plane -- below for a wall or floor, above for a ceiling -- so it
    can never occlude the geometry it is backing.
    """
    direction = -0.5 if facing == "up" else 0.5
    return slab("backplane", (0.5, 0.5, z + direction),
                (1.0 + margin * 2, 1.0 + margin * 2, 1.0))


# ---------------------------------------------------------------- walls (x)

def wall_pilasters():
    """Plain ashlar wall broken by engaged pilasters and two string courses.

    The pilaster is placed ON the tile boundary as well as at the centre. That
    is the whole point of the preset: it forces the wrap machinery to prove
    itself on the most visible feature in the image.
    """
    objects = [backplane()]

    for row in range(6):
        y = (row + 0.5) / 6.0
        stagger = 0.5 if row % 2 else 0.0
        for col in range(4):
            x = (col + 0.5) / 4.0 + stagger / 4.0
            block = slab(f"block_{row}_{col}", (x, y, 0.018),
                         (0.235, 0.150, 0.036))
            objects.append(bevel(block, 0.008))

    for y in (0.30, 0.86):
        course = slab(f"course_{y}", (0.5, y, 0.040), (3.0, 0.055, 0.080))
        objects.append(bevel(course, 0.012))

    for x in (0.0, 0.5):
        shaft = slab(f"pilaster_{x}", (x, 0.5, 0.060), (0.150, 3.0, 0.120))
        objects.append(bevel(shaft, 0.014))
        for y, extent in ((0.075, 0.190), (0.945, 0.200)):
            block = slab(f"pilaster_cap_{x}_{y}", (x, y, 0.072),
                         (extent, 0.090, 0.144))
            objects.append(bevel(block, 0.010))

    return objects, "x"


def wall_niche():
    """Ashlar wall carrying a round-arched recess with an archivolt moulding.

    The niche is a boolean cut rather than a modelled cavity so its floor and
    jambs meet the wall at a true edge; a modelled shell leaves a hairline the
    depth sampler reads as noise.
    """
    # Deep enough that a cut can be a RECESS rather than a hole. The first
    # version of this preset used a 0.04 slab, so the niche boolean punched
    # straight through to the backplane and the cavity read as a flat cut-out
    # with no floor.
    wall = slab("wall", (0.5, 0.5, -0.080), (4.0, 4.0, 0.240))
    objects = [backplane(z=-0.20), wall]

    for row in range(7):
        y = (row + 0.5) / 7.0
        stagger = 0.5 if row % 2 else 0.0
        for col in range(5):
            x = ((col + 0.5) / 5.0 + stagger / 5.0) % 1.0
            groove = slab(f"joint_v_{row}_{col}", (x, y, 0.046),
                          (0.009, 1.0 / 7.0, 0.058))
            boolean(wall, groove)
            objects.append(groove)
        groove = slab(f"joint_h_{row}", (0.5, y - 0.5 / 7.0, 0.046),
                      (4.0, 0.009, 0.058))
        boolean(wall, groove)
        objects.append(groove)

    # The cavity has to break the FRONT FACE at z=0.040, not float inside the
    # slab. A cutter whose top sits below the face carves a sealed void the
    # raycast can never see and the wall reads as untouched.
    cavity_box = slab("niche_box", (0.5, 0.36, 0.0525), (0.30, 0.44, 0.095))
    boolean(wall, cavity_box)
    objects.append(cavity_box)
    cavity_arch = cylinder("niche_arch", (0.5, 0.58, 0.0525), 0.150, 0.095,
                           axis="Z")
    boolean(wall, cavity_arch)
    objects.append(cavity_arch)

    surround = cylinder("archivolt", (0.5, 0.58, 0.048), 0.196, 0.052, axis="Z")
    objects.append(bevel(surround, 0.012))
    inner = cylinder("archivolt_cut", (0.5, 0.58, 0.048), 0.152, 0.090, axis="Z")
    boolean(surround, inner)
    objects.append(inner)
    for x in (0.5 - 0.174, 0.5 + 0.174):
        jamb = slab(f"jamb_{x:.2f}", (x, 0.30, 0.048), (0.044, 0.56, 0.052))
        objects.append(bevel(jamb, 0.010))

    keystone = slab("keystone", (0.5, 0.762, 0.056), (0.070, 0.090, 0.068))
    objects.append(bevel(keystone, 0.010))

    plinth = slab("plinth", (0.5, 0.045, 0.052), (4.0, 0.090, 0.064))
    objects.append(bevel(plinth, 0.012))

    return objects, "x"


# --------------------------------------------------------------- floors (xy)

def floor_flagstones():
    """Irregular slabs with worn, rounded arrises and open joints.

    The layout is a fixed table rather than a random one: a floor that changes
    between runs cannot be used to attribute a difference in the generated art
    to anything but chance.
    """
    objects = [backplane()]
    slabs = [
        (0.00, 0.00, 0.34, 0.26), (0.36, 0.00, 0.30, 0.26),
        (0.68, 0.00, 0.32, 0.26),
        (0.00, 0.28, 0.22, 0.30), (0.24, 0.28, 0.40, 0.30),
        (0.66, 0.28, 0.34, 0.30),
        (0.00, 0.60, 0.38, 0.18), (0.40, 0.60, 0.26, 0.18),
        (0.68, 0.60, 0.32, 0.18),
        (0.00, 0.80, 0.28, 0.20), (0.30, 0.80, 0.34, 0.20),
        (0.66, 0.80, 0.34, 0.20),
    ]
    joint = 0.014
    for index, (x, y, w, h) in enumerate(slabs):
        stone = slab(f"flag_{index}",
                     (x + w / 2.0, y + h / 2.0, 0.016),
                     (w - joint, h - joint, 0.032))
        objects.append(bevel(stone, 0.009, segments=4))
    return objects, "xy"


def floor_inlay():
    """A flat pavement carrying a raised concentric medallion and a border.

    The border runs along the tile edge, so four tiles meet in a continuous
    frame rather than four separate panels -- the reason the border is here and
    not centred.
    """
    objects = [backplane()]
    field = slab("field", (0.5, 0.5, 0.010), (4.0, 4.0, 0.020))
    objects.append(field)

    for offset in (0.0, 1.0):
        objects.append(bevel(slab(f"border_h_{offset}", (0.5, offset, 0.022),
                                  (4.0, 0.070, 0.044)), 0.010))
        objects.append(bevel(slab(f"border_v_{offset}", (offset, 0.5, 0.022),
                                  (0.070, 4.0, 0.044)), 0.010))

    for radius, height in ((0.330, 0.030), (0.250, 0.040), (0.120, 0.052)):
        ring = cylinder(f"ring_{radius}", (0.5, 0.5, height / 2.0),
                        radius, height)
        objects.append(bevel(ring, 0.008))
    for index in range(8):
        angle = index * math.pi / 4.0
        spoke = slab(f"spoke_{index}",
                     (0.5 + math.cos(angle) * 0.290,
                      0.5 + math.sin(angle) * 0.290, 0.036),
                     (0.090, 0.052, 0.030), spin=angle)
        objects.append(bevel(spoke, 0.008))
    objects.append(bevel(cone("boss", (0.5, 0.5, 0.062), 0.075, 0.030, 0.036),
                         0.008))
    return objects, "xy"


# ------------------------------------------------------------- ceilings (xy)

def ceiling_coffers():
    """Beams crossing over sunk coffers, each with a small pendant boss.

    Modelled as seen from below: the beam soffits are the near surface and the
    coffer sinks away, which is exactly the depth an eye in the corridor reads.
    """
    objects = [backplane(z=0.30, facing="down")]
    # The ceiling mass sits ABOVE its soffit: the plane at z=0 is the surface
    # facing the corridor, and every coffer is cut upward into the mass from
    # there. Cutting downward would put the pockets in mid-air below the
    # ceiling, which is how the first version of this preset produced a flat
    # slab speckled with boolean noise.
    mass = slab("mass", (0.5, 0.5, 0.110), (4.0, 4.0, 0.220))
    objects.append(mass)

    for row in range(2):
        for col in range(2):
            cx, cy = (col + 0.5) / 2.0, (row + 0.5) / 2.0
            # Two stacked pockets of decreasing width make the stepped
            # architrave a real coffer has; each stops short of the one above.
            for top, extent in ((0.060, 0.400), (0.105, 0.330)):
                pocket = slab(f"coffer_{row}_{col}_{extent}",
                              (cx, cy, top / 2.0 - 0.010),
                              (extent, extent, top + 0.020))
                boolean(mass, pocket)
                objects.append(pocket)
            # The pendant hangs DOWN out of the coffer toward the corridor. Sunk
            # into the pocket it would be buried in the mass and invisible.
            objects.append(sphere(f"boss_{row}_{col}", (cx, cy, 0.086), 0.058))
    for offset in (0.0, 1.0):
        objects.append(bevel(slab(f"beam_x_{offset}", (0.5, offset, -0.014),
                                  (4.0, 0.090, 0.028)), 0.008))
        objects.append(bevel(slab(f"beam_y_{offset}", (offset, 0.5, -0.014),
                                  (0.090, 4.0, 0.028)), 0.008))
    return objects, "xy"


def ceiling_vault():
    """A groin vault: two barrel vaults meeting on ribs along the diagonals.

    The barrels are carved out of the slab rather than modelled as shells so
    the groin -- where the two intersections meet -- is a genuine surface
    intersection instead of two coincident faces fighting for the same pixel.
    """
    objects = [backplane(z=0.40, facing="down")]
    mass = slab("mass", (0.5, 0.5, 0.150), (4.0, 4.0, 0.300))
    objects.append(mass)

    # Two elliptical barrels carved UP into the mass, each exactly one tile
    # wide so it springs from z=0 at both edges and crowns 0.14 above the
    # soffit at the centre. Where they meet, the intersection of the two cuts
    # IS the groin, rather than two shells fighting for the same pixel -- and
    # because each spans the full period it needs no wrap copy to be seamless.
    for axis in ("X", "Y"):
        barrel = cylinder(f"barrel_{axis}", (0.5, 0.5, 0.0), 0.500, 4.0,
                          axis=axis, segments=96, rise=0.140)
        boolean(mass, barrel, operation="DIFFERENCE")
        objects.append(barrel)

    for offset in (0.0, 1.0):
        objects.append(bevel(cylinder(f"rib_x_{offset}", (0.5, offset, -0.012),
                                      0.040, 4.0, axis="X"), 0.008))
        objects.append(bevel(cylinder(f"rib_y_{offset}", (offset, 0.5, -0.012),
                                      0.040, 4.0, axis="Y"), 0.008))
    for x in (0.0, 1.0):
        for y in (0.0, 1.0):
            objects.append(bevel(slab(f"corbel_{x}_{y}", (x, y, -0.022),
                                      (0.140, 0.140, 0.044)), 0.010))
    # Sits at the crown of the groin, hanging just below it into the void.
    objects.append(sphere("keystone", (0.5, 0.5, 0.140), 0.050))
    return objects, "xy"


PRESETS = {
    "wall_pilasters": wall_pilasters,
    "wall_niche": wall_niche,
    "floor_flagstones": floor_flagstones,
    "floor_inlay": floor_inlay,
    "ceiling_coffers": ceiling_coffers,
    "ceiling_vault": ceiling_vault,
}

# Which asset-gen class each preset is depth guidance for. Walls tile on one
# axis only because their top and bottom are authored, floors and ceilings on
# both because they repeat in every direction underfoot and overhead.
SURFACE = {
    "wall_pilasters": "wall",
    "wall_niche": "wall",
    "floor_flagstones": "floor",
    "floor_inlay": "floor",
    "ceiling_coffers": "ceiling",
    "ceiling_vault": "ceiling",
}


def _bake_modifiers():
    """Freeze every modifier into mesh data, then drop the cutters.

    This has to happen BEFORE the wrap duplicates are made. `obj.copy()` copies
    the modifier stack, and a copied boolean still points at the cutter sitting
    at the original coordinates -- so an unbaked wall duplicated one period to
    the left arrives carrying a niche cut out of open air, and the seam the
    duplicates exist to prevent appears anyway.
    """
    # Two passes, and the order is the whole point. Baking and deleting in one
    # loop destroys a cutter before the target further down the collection has
    # been evaluated against it, so that boolean silently becomes a no-op -- the
    # symptom being a coffered ceiling that renders as a flat slab with none of
    # its coffers, which is exactly how this was found.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    survivors = []
    for obj in list(bpy.context.collection.objects):
        if obj.get("is_cutter") or not obj.modifiers:
            if not obj.get("is_cutter"):
                survivors.append(obj)
            continue
        baked = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
        baked.transform(obj.matrix_world)
        obj.matrix_world.identity()
        obj.data = baked
        obj.modifiers.clear()
        survivors.append(obj)
    for obj in list(bpy.context.collection.objects):
        if obj.get("is_cutter"):
            bpy.data.objects.remove(obj, do_unlink=True)
    return survivors


# Which side the viewer stands on. Walls and floors are met from above the
# modelled surface, ceilings from below it.
VIEW = {name: ("below" if surface == "ceiling" else "above")
        for name, surface in SURFACE.items()}


def build(preset):
    _clear()
    _, axes = PRESETS[preset]()
    _wrap_cutters(axes)
    wrap_copies(_bake_modifiers(), axes)
    return axes
