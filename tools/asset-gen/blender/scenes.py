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


def wall_blind_arcade():
    """A Romanesque blind arcade: engaged shafts carrying round arches on a
    solid wall, arcading a face that has nothing behind it.

    The device is worth having because it is ARCHITECTURE rather than masonry.
    Every other wall preset here varies how stones are cut and stacked; this one
    varies what the wall is pretending to be, and gives a corridor a rhythm and
    a skyline instead of a texture.

    Bays are cut, shafts are added. A recess made by adding two piers leaves the
    "wall" behind them at the same depth as the piers' own faces, so nothing
    reads as sunk; cutting the bay first puts a real floor and real jambs behind
    the arcade.
    """
    wall = slab("wall", (0.5, 0.5, -0.080), (4.0, 4.0, 0.240))
    objects = [backplane(z=-0.20), wall]

    bays = 4
    spring = 0.60                       # where the arch leaves the impost
    half = 0.5 / bays - 0.026           # bay half-width, the rest becomes pier

    for index in range(bays):
        cx = (index + 0.5) / bays
        # The straight part of the bay, from plinth to springing.
        panel = slab(f"bay_{index}", (cx, (spring + 0.10) / 2.0, 0.060),
                     (half * 2.0, spring - 0.10, 0.120))
        boolean(wall, panel)
        objects.append(panel)
        # The semicircular head. Axis Z, so the CIRCLE lies in the wall face --
        # an X or Y axis here would bore a tunnel through the wall instead of
        # describing an arch on it.
        head = cylinder(f"head_{index}", (cx, spring, 0.060), half, 0.120,
                        axis="Z", segments=64)
        boolean(wall, head)
        objects.append(head)

    # Shafts sit ON the boundary as well as between bays, so the wrap has to
    # prove itself on the most legible feature in the picture -- the same test
    # wall_pilasters sets, and the one that caught the niche going missing.
    for index in range(bays):
        x = index / bays
        objects.append(cylinder(f"shaft_{index}", (x, 0.34, 0.040), 0.034, 0.56,
                                axis="Y", segments=24))
        # Cushion capital and a spreading base, both wider than the shaft.
        objects.append(bevel(slab(f"cap_{index}", (x, 0.625, 0.048),
                                  (0.105, 0.055, 0.096)), 0.012))
        objects.append(bevel(slab(f"base_{index}", (x, 0.075, 0.044),
                                  (0.100, 0.050, 0.088)), 0.010))

    # NO continuous impost band. The first version ran one across the whole
    # face at the springing, which drew a rail straight over every arch head:
    # the arches stopped reading as arches and became bumps above a line. The
    # capitals already give the arch something to spring from, which is what the
    # band was reaching for.
    objects.append(bevel(slab("plinth", (0.5, 0.030, 0.052), (4.0, 0.060, 0.104)),
                         0.012))
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
    """Irregular slabs, each at its own level, dished by wear.

    The layout is a fixed table rather than a random one: a floor that changes
    between runs cannot be used to attribute a difference in the generated art
    to anything but chance.

    Rebuilt 04.08 on the owner's reading, and the first version is worth stating
    because every fault was deliberate and every one was wrong. It gave all
    twelve slabs the SAME height (0.032), a flat top, an axis-aligned rectangle,
    a 0.009 bevel too small to survive the sample, and a joint that fell all the
    way to the backplane. The result was a waffle iron: identical grey tiles
    separated by black cliffs, "harsh and pointy".

    Four changes, three of them already proven by the presets that outscore it
    (`floor_slabs_varied` 4.33 and `floor_cobbles`, against this one's 2.67):

      per-stone height   -- the ankle-turning unevenness is what makes it stone
                            rather than a printed pattern.
      a shallow bed      -- the joint is mortar between stones that touch, not a
                            void they float over. Straight from floor_cobbles.
      arrises that read  -- bevel by an order of magnitude more; worn edges are
                            the difference between a cut slab and a walked-on one.
      a dished top       -- new here, and the thing no existing preset had: the
                            surface itself is worn, not merely placed at a
                            different height.
    """
    rng = _rng()
    # ONE field for the whole floor, not one per stone: a floor is worn as a
    # floor, so the grain has to run across the joints rather than restart at
    # every stone. noise_at is period-1 by construction and sampled in world
    # space, which is what keeps the wear tiling through the wrap copies.
    wear = noise_field(rng, terms=18, max_frequency=9)
    # Just below the lowest crown, for the reason floor_cobbles gives: a deep
    # bed drops the joints to the bottom of the tonal range and the stones read
    # as loose bubbles over a void.
    objects = [backplane(z=0.070),
               slab("bed", (0.5, 0.5, 0.020), (4.0, 4.0, 0.100))]
    # SCALE, not shape, was the remaining fault. The tile is one square metre of
    # floor, and twelve stones across it makes each one a 30 cm slab -- but the
    # eye reads scale from the stone, not from the tile, so a metre of floor
    # came back looking like a 20 cm sample of something. Six courses of five
    # puts a stone at roughly 18 cm, which is a paving unit a person would
    # actually walk on, and the tile then reads at the size it really is.
    #
    # Generated on a jittered running bond rather than kept as a hand table:
    # thirty entries written out by hand is a table nobody will ever adjust
    # again, and the jitter is seeded so the floor is still identical run to run.
    rows, cols = 6, 5
    slabs = []
    for row in range(rows):
        stagger = (0.5 if row % 2 else 0.0) / cols
        for col in range(cols):
            width = (1.0 / cols) * rng.uniform(0.86, 1.0)
            height = (1.0 / rows) * rng.uniform(0.84, 1.0)
            slabs.append(((col / cols + stagger) % 1.0, row / rows, width, height))

    joint = 0.013
    for index, (x, y, w, h) in enumerate(slabs):
        height = rng.uniform(0.105, 0.190)
        stone = slab(f"flag_{index}", (x + w / 2.0, y + h / 2.0, height / 2.0),
                     (w - joint, h - joint, height),
                     spin=rng.uniform(-0.030, 0.030))
        # Sampled per stone, so neighbours are not dished in step. The amount is
        # a large fraction of the height SPREAD rather than of the height: what
        # has to be visible is the wear against its neighbours' crowns, and at a
        # third of that spread it reads as a worn surface instead of a gradient.
        # This is what separates the preset from `floor_slabs_varied`, which is
        # otherwise now the same floor.
        displace(stone, wear, rng.uniform(0.020, 0.032), cuts=4, along="z")
        objects.append(bevel(stone, min(0.020, height * 0.28), segments=5))
    return objects, "xy"


def floor_hypocaust():
    """A broken floor over a Roman hypocaust: pilae stacks in the void below.

    Nothing else in the set has a floor with a HOLE in it, and that is the
    reason for the preset. Every other floor is a continuous surface varying in
    texture; this one is a plane you can fall through, which is a different
    thing for a dungeon to offer and a much harder thing to fake in a prompt.

    The suspended pavement survives at the edges and has collapsed across the
    middle, so the map carries both the intact surface and the columns holding
    it up. Depth range is deliberately wide: the difference between floor level
    and the bottom of the void is the whole idea.
    """
    rng = _rng()
    decay = noise_field(rng, terms=14, max_frequency=8)
    # The bottom of the hypocaust, far below the walking surface.
    objects = [backplane(z=-0.205)]

    # Pilae on a lattice: square brick stacks, each a few courses tall. On a
    # 5x5 grid they wrap without a copy, and every one of them is visible only
    # because the floor above has gone.
    for row in range(5):
        for col in range(5):
            cx, cy = (col + 0.5) / 5.0, (row + 0.5) / 5.0
            courses = rng.randint(3, 4)
            for course in range(courses):
                z = -0.180 + course * 0.050
                # Alternating course sizes give the stack its brick reading.
                extent = 0.086 if course % 2 else 0.098
                objects.append(bevel(
                    slab(f"pila_{row}_{col}_{course}", (cx, cy, z),
                         (extent, extent, 0.046)), 0.006))

    # The surviving pavement, cut away over the middle. Modelled as four margin
    # slabs rather than one slab with a hole, because a boolean hole here would
    # have to be bigger than the tile to reach the edges and would take the
    # whole floor with it.
    lip = 0.185
    for name, centre, size in (
        ("north", (0.5, 1.0 - lip / 2.0, 0.0), (4.0, lip, 0.070)),
        ("south", (0.5, lip / 2.0, 0.0), (4.0, lip, 0.070)),
        ("east", (1.0 - lip / 2.0, 0.5, 0.0), (lip, 4.0, 0.070)),
        ("west", (lip / 2.0, 0.5, 0.0), (lip, 4.0, 0.070)),
    ):
        deck = slab(f"deck_{name}", centre, size)
        # Broken edges, not sawn ones. Along z, never along the normal: these
        # decks are open sheets four units wide, and `displace` records that
        # normal-displacing a sheet is the worst seam this pipeline has made.
        displace(deck, decay, 0.014, cuts=5, along="z")
        objects.append(bevel(deck, 0.012, segments=4))

    # A few slabs that fell in and are lying across the pilae.
    for index, (x, y) in enumerate(_scatter(rng, 3, 3, 0.30)):
        objects.append(bevel(
            slab(f"rubble_{index}", (x, y, -0.070 + rng.uniform(0.0, 0.04)),
                 (rng.uniform(0.10, 0.17), rng.uniform(0.09, 0.15), 0.038),
                 spin=rng.uniform(-0.6, 0.6)), 0.010))
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


def ceiling_fan_vault():
    """Perpendicular fan vaulting: conoids opening from each springer.

    The most ornamental ceiling in the set, and structurally the opposite of the
    groin vault beside it. A groin is two barrels intersecting; a fan is four
    cones of revolution flaring from the corners until they meet, leaving a flat
    spandrel between their rims and a pendant where they touch.

    The four cutters sit at the four CORNERS of the tile rather than one at the
    centre, and that is what makes it wrap. `boolean` marks a cutter hidden and
    `wrap_copies` skips hidden objects, so a cut is never duplicated across the
    period -- a single corner fan would be carved on one side of the tile and
    missing on the other. Four identical corner cones make the carving periodic
    by construction instead of by copy.
    """
    objects = [backplane(z=0.42, facing="down")]
    mass = slab("mass", (0.5, 0.5, 0.160), (4.0, 4.0, 0.320))
    objects.append(mass)

    # A DOME, not four cones, and the difference is a boolean mistake worth
    # recording. A fan is four conoids springing from the corners, so the first
    # version removed the inside of an upward-flaring cone at each corner --
    # which deletes material NEAR the springer and leaves it everywhere else.
    # The soffit stayed flat across the whole bay and the ceiling rendered as a
    # grey plate with four holes punched in the corners. The volume that has to
    # go is the one BELOW the vault surface: tall over the middle where the
    # fans have risen, pinching to nothing at each springer. That volume is a
    # dome, and one ellipsoid states it exactly.
    #
    # The rim reaches past the tile diagonal (0.707) so the surface arrives at
    # z=0 at the corners and nowhere earlier; a smaller rim leaves a flat
    # margin around the springers that reads as a ceiling with a dish in it.
    canopy = ellipsoid("canopy", (0.5, 0.5, 0.0), (0.760, 0.760, 0.235),
                       segments=64)
    boolean(mass, canopy)
    objects.append(canopy)

    # Transverse ribs on the soffit where the vault meets the wall head.
    for offset in (0.0, 1.0):
        objects.append(bevel(cylinder(f"wallrib_x_{offset}", (0.5, offset, -0.010),
                                      0.034, 4.0, axis="X"), 0.008))
        objects.append(bevel(cylinder(f"wallrib_y_{offset}", (offset, 0.5, -0.010),
                                      0.034, 4.0, axis="Y"), 0.008))

    objects.append(sphere("pendant", (0.5, 0.5, 0.030), 0.075))
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


# --------------------------------------------------- organic set (2026-08-03)
#
# Requested after the first six landed: rounder, steeper, more organic, and
# floors whose stones sit at DIFFERENT heights rather than on one plane. These
# are additions, not revisions -- the first six are the baseline the ratings
# from 03.08 are attached to, and editing them would invalidate that comparison.
#
# Relief here runs roughly 0.20-0.35 against the original set's 0.03-0.14. That
# is the "steeper" part, and it is worth watching: the style-depth sweep found
# depth weight 0.85 already over-constrains at the SHALLOW reliefs, so these may
# want a weight below 0.60 rather than above it.

# Seeded rather than tabulated. The first six use fixed coordinate tables so a
# layout can be diffed; at fifty-odd stones that stops being readable, and a
# fixed seed gives the same reproducibility with none of the noise.
ORGANIC_SEED = 20260803


def _rng():
    import random
    return random.Random(ORGANIC_SEED)


def ellipsoid(name, centre, radii, segments=24):
    """A sphere scaled per axis -- the workhorse for rounded, organic mass."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2,
                              radius=1.0)
    bmesh.ops.scale(bm, vec=radii, verts=bm.verts)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    return _mesh_from_bmesh(name, bm)


# ------------------------------------------------------- displacement (03.08)
#
# Primitives give silhouette; displacement gives surface. A boulder built from
# an ellipsoid is a perfect ovoid no matter how it is scaled, and reads as a
# bubble; the same ellipsoid pushed around by a noise field reads as rock.
#
# The noise is a sum of sinusoids on INTEGER wavevectors, which is not the most
# fashionable way to make noise but is the only cheap one that is exactly
# periodic over the tile. That matters more than it sounds: displacement is
# baked into the mesh, and the wrap copies are the same mesh translated by
# exactly one period, so unless noise(x+1,y) == noise(x,y) to the last bit,
# every displaced preset grows a seam that the flat ones did not have. Blender's
# own CLOUDS and NOISE textures are not periodic, which is why they are not used
# here despite being the obvious tool.


def noise_field(rng, terms=16, max_frequency=7):
    """A period-1 2D noise field, as a list of sinusoid terms."""
    field = []
    while len(field) < terms:
        u = rng.randint(-max_frequency, max_frequency)
        v = rng.randint(-max_frequency, max_frequency)
        if u == 0 and v == 0:
            continue
        # 1/|k| falloff: low frequencies carry the form, high ones the grain.
        field.append((u, v, 1.0 / math.hypot(u, v), rng.uniform(0.0, math.tau)))
    return field


def noise_at(field, x, y):
    total = sum(amp * math.sin(math.tau * (u * x + v * y) + phase)
                for u, v, amp, phase in field)
    return total / sum(amp for _, _, amp, _ in field)


def displace(obj, field, amplitude, cuts=2, along="normal"):
    """Push every vertex by the noise sampled at its x,y.

    Sampling in WORLD x,y rather than in the object's own space is deliberate:
    neighbouring stones then share one continuous rock grain instead of each
    carrying its own copy of the same pattern, and the period-1 guarantee is
    preserved through the wrap copies, which are translations in world space.

    `along` picks the direction, and the choice is not cosmetic:

      "normal" is what a closed shape wants -- a boulder has to bulge outward
      in every direction or it just gets taller.

      "z" is what an open SHEET must have. Displacing a plane along its normals
      moves vertices sideways as well as up, and a vertex on the tile edge has
      neighbours on one side only, so its normal differs from its counterpart's
      on the far edge and the two edges stop lining up. Measured at 113x the
      interior gradient on the first eroded wall -- by far the worst seam this
      pipeline has produced.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    if cuts:
        # Displacement can only be as fine as the mesh carrying it; an
        # undisplaced primitive has nowhere near enough vertices for grain.
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts,
                                  use_grid_fill=True)
    bm.normal_update()
    for vert in bm.verts:
        offset = amplitude * noise_at(field, vert.co.x, vert.co.y)
        if along == "z":
            vert.co.z += offset
        else:
            vert.co += vert.normal * offset
    bm.to_mesh(mesh)
    bm.free()
    return obj


def noise_plane(name, amplitude, field, resolution=96, z=0.0):
    """A subdivided unit plane displaced into a continuous eroded surface.

    Pure displacement with no primitive underneath -- the technique on its own,
    for surfaces that have no discrete stones to build from.
    """
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=resolution, y_segments=resolution,
                          size=0.5)
    bmesh.ops.translate(bm, vec=(0.5, 0.5, z), verts=bm.verts)
    for vert in bm.verts:
        vert.co.z += amplitude * noise_at(field, vert.co.x, vert.co.y)
    return _mesh_from_bmesh(name, bm)


def _scatter(rng, rows, cols, jitter):
    """Jittered lattice: irregular, but with no gaps and no pile-ups.

    Pure random placement leaves bald patches and overlaps that read as noise
    rather than as masonry. Displacing a lattice keeps the coverage even while
    losing the grid, which is what a laid cobble floor actually looks like.
    """
    for row in range(rows):
        for col in range(cols):
            yield ((col + 0.5) / cols + rng.uniform(-jitter, jitter) / cols,
                   (row + 0.5) / rows + rng.uniform(-jitter, jitter) / rows)


def floor_cobbles():
    """Rounded cobbles, each set at its own height, packed on a jittered lattice.

    The per-stone height offset is the point of the preset. A cobble floor whose
    stones all crown at the same level reads as a printed pattern; the ankle-
    turning unevenness is what makes it stone, and it is the thing the flat
    first-pass flagstone map could not express.
    """
    rng = _rng()
    # The bed sits just BELOW the lowest crown, not at the bottom of the range.
    # With a deep bed the gaps between stones fall to the floor of the tonal
    # range and the map reads as loose bubbles over a void; a shallow bed makes
    # them what they are, which is mortar between stones that touch.
    objects = [backplane(z=0.085),
               slab("bed", (0.5, 0.5, 0.020), (4.0, 4.0, 0.130))]
    for index, (x, y) in enumerate(_scatter(rng, 7, 7, 0.28)):
        # Radius against a 1/7 lattice pitch, so neighbours meet rather than
        # float. Below about 0.07 they separate and the packing is lost.
        radius = rng.uniform(0.095, 0.125)
        # The stone's crown, independent per stone: some sit proud, some are
        # trodden almost flush into the bed.
        crown = rng.uniform(0.115, 0.215)
        objects.append(ellipsoid(
            f"cobble_{index}", (x, y, crown - radius * 1.15),
            (radius, radius * rng.uniform(0.80, 1.25), radius * 1.35)))
    return objects, "xy"


def floor_slabs_varied():
    """The flagstone idea again, but every slab at its own level and rounded off.

    Heavier bevels than the flat version by an order of magnitude: worn arrises
    are the difference between a cut slab and a walked-on one.
    """
    rng = _rng()
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
    joint = 0.020
    for index, (x, y, w, h) in enumerate(slabs):
        height = rng.uniform(0.090, 0.260)
        stone = slab(f"slab_{index}", (x + w / 2.0, y + h / 2.0, height / 2.0),
                     (w - joint, h - joint, height),
                     spin=rng.uniform(-0.035, 0.035))
        objects.append(bevel(stone, min(0.030, height * 0.34), segments=6))
    return objects, "xy"


def wall_rubble():
    """Undressed rubble walling: rounded boulders of varying protrusion.

    No courses, no joints, no straight lines -- the opposite end of the
    vocabulary from the ashlar and pilaster presets.
    """
    rng = _rng()
    objects = [backplane(z=0.100),
               slab("bed", (0.5, 0.5, 0.030), (4.0, 4.0, 0.140))]
    for index, (x, y) in enumerate(_scatter(rng, 6, 5, 0.32)):
        # Lattice pitch is 1/5 across and 1/6 up; radii are sized to overlap it
        # so the boulders bear on each other the way undressed walling does.
        radius = rng.uniform(0.115, 0.160)
        proud = rng.uniform(0.150, 0.290)
        objects.append(ellipsoid(
            f"boulder_{index}", (x, y, proud - radius * 1.25),
            (radius * rng.uniform(0.85, 1.30), radius, radius * 1.30)))
    return objects, "x"


def wall_cave():
    """Hewn rock face: a few large rounded lobes with smaller nodules between.

    Two scales on purpose. One scale of blob reads as bubbles; a large form
    carrying a finer one is what makes a rock face look cut rather than poured.
    """
    rng = _rng()
    objects = [backplane(z=0.150),
               slab("bed", (0.5, 0.5, 0.060), (4.0, 4.0, 0.180))]
    # Lobes wider than the 1/3 lattice pitch, so they intersect into one
    # continuous face. Lobes that merely sit near each other read as boulders;
    # lobes that overlap read as rock that was cut.
    for index, (x, y) in enumerate(_scatter(rng, 3, 3, 0.40)):
        radius = rng.uniform(0.290, 0.380)
        objects.append(ellipsoid(
            f"lobe_{index}", (x, y, rng.uniform(0.230, 0.360) - radius),
            (radius, radius * rng.uniform(0.70, 1.15), radius * 0.95)))
    # The second scale is a texture ON the rock, not objects in front of it:
    # shallow and mostly buried, so it modulates the large form instead of
    # scattering free-floating balls across it.
    for index, (x, y) in enumerate(_scatter(rng, 7, 7, 0.45)):
        radius = rng.uniform(0.050, 0.090)
        objects.append(ellipsoid(
            f"nodule_{index}", (x, y, rng.uniform(0.180, 0.300) - radius * 0.80),
            (radius, radius, radius * 0.55)))
    return objects, "x"


def ceiling_dripstone():
    """Living cave roof: pendant lumps of varying reach, seen from below.

    Modelled hanging DOWN toward the corridor, which for a ceiling means toward
    the sampler -- see VIEW. The deepest pendants are the steepest relief in the
    whole library.
    """
    rng = _rng()
    objects = [backplane(z=0.45, facing="down"),
               slab("mass", (0.5, 0.5, 0.180), (4.0, 4.0, 0.360))]
    for index, (x, y) in enumerate(_scatter(rng, 5, 5, 0.70)):
        reach = rng.uniform(0.060, 0.330)
        radius = rng.uniform(0.045, 0.095)
        # A cone for the drip and a ball at its root, so the pendant swells
        # where it leaves the roof instead of meeting it at a sharp ring.
        #
        # `radius1` is the -Z end and `radius2` the +Z end. A ceiling is viewed
        # from BELOW, so -Z is the end nearest the eye and must be the POINT:
        # the first version passed the wide radius first and hung fifty stone
        # ice-cream cones from the roof, base-first, which is what the owner
        # spotted.
        objects.append(cone(f"drip_{index}", (x, y, -reach / 2.0),
                            radius * 0.12, radius, reach))
        objects.append(ellipsoid(f"root_{index}", (x, y, 0.0),
                                 (radius * 1.30, radius * 1.30, radius * 0.60)))
    return objects, "xy"


# ------------------------------------------- displaced set (2026-08-03, later)
#
# Same shapes as the organic set, but with the surface itself broken up. Kept as
# new presets rather than edits so the plain-primitive versions stay available
# as the control: "displacement helps" is a claim the ratings should be able to
# test, not an assumption baked in by overwriting the alternative.


def wall_boulders_rough():
    """Large rocks that are no longer spheres.

    The direct answer to the ovoid problem: heavy low-frequency displacement
    changes the SILHOUETTE, and a second lighter pass at higher frequency adds
    the grain. One pass alone gives either smooth blobs or fizz.
    """
    rng = _rng()
    # Three octaves, and the coarse one is deliberately violent. At a third of
    # the radius the displacement only dents an ovoid -- it still reads as a
    # sphere with texture on it. Past about half the radius the silhouette
    # itself stops being an ellipse, which is the thing that was wrong.
    coarse = noise_field(rng, terms=6, max_frequency=2)
    medium = noise_field(rng, terms=12, max_frequency=5)
    fine = noise_field(rng, terms=18, max_frequency=11)
    objects = [backplane(z=0.100),
               displace(slab("bed", (0.5, 0.5, 0.030), (4.0, 4.0, 0.140)),
                        fine, 0.018, cuts=0, along="z")]
    for index, (x, y) in enumerate(_scatter(rng, 5, 4, 0.30)):
        radius = rng.uniform(0.115, 0.170)
        proud = rng.uniform(0.150, 0.300)
        rock = ellipsoid(f"rock_{index}", (x, y, proud - radius * 1.25),
                         (radius * rng.uniform(0.85, 1.30), radius,
                          radius * 1.30), segments=40)
        displace(rock, coarse, radius * 0.55, cuts=1)
        displace(rock, medium, radius * 0.20, cuts=0)
        displace(rock, fine, radius * 0.07, cuts=0)
        objects.append(rock)
    return objects, "x"


def floor_cobbles_rough():
    """Cobbles with a worn, pitted surface instead of a polished dome."""
    rng = _rng()
    coarse = noise_field(rng, terms=10, max_frequency=4)
    fine = noise_field(rng, terms=20, max_frequency=11)
    objects = [backplane(z=0.085),
               displace(slab("bed", (0.5, 0.5, 0.020), (4.0, 4.0, 0.130)),
                        fine, 0.012, cuts=0, along="z")]
    for index, (x, y) in enumerate(_scatter(rng, 7, 7, 0.28)):
        radius = rng.uniform(0.095, 0.125)
        crown = rng.uniform(0.115, 0.215)
        stone = ellipsoid(f"cobble_{index}", (x, y, crown - radius * 1.15),
                          (radius, radius * rng.uniform(0.80, 1.25),
                           radius * 1.35), segments=28)
        displace(stone, coarse, radius * 0.22, cuts=1)
        displace(stone, fine, radius * 0.09, cuts=0)
        objects.append(stone)
    return objects, "xy"


def wall_eroded():
    """Displacement with no primitive underneath: a weathered rock face.

    Three octaves on one plane. This is the technique at its plainest, and it
    is the preset to look at first when judging whether displacement is pulling
    its weight, because nothing else is contributing to the result.
    """
    rng = _rng()
    objects = [backplane(z=-0.20)]
    for scale, amplitude, resolution in ((3, 0.130, 128),):
        field = noise_field(rng, terms=8, max_frequency=scale)
        plane = noise_plane("face", amplitude, field, resolution=resolution)
        for terms, frequency, amount in ((14, 8, 0.045), (22, 16, 0.016)):
            displace(plane, noise_field(rng, terms=terms, max_frequency=frequency),
                     amount, cuts=0, along="z")
        objects.append(plane)
    return objects, "x"


def ceiling_dripstone_rough():
    """The corrected pendants, roughened, on an uneven cave roof."""
    rng = _rng()
    coarse = noise_field(rng, terms=10, max_frequency=4)
    fine = noise_field(rng, terms=18, max_frequency=10)
    roof = noise_plane("roof", 0.055, coarse, resolution=110, z=0.0)
    objects = [backplane(z=0.45, facing="down"),
               slab("mass", (0.5, 0.5, 0.240), (4.0, 4.0, 0.360)), roof]
    for index, (x, y) in enumerate(_scatter(rng, 5, 5, 0.70)):
        reach = rng.uniform(0.070, 0.330)
        radius = rng.uniform(0.045, 0.095)
        drip = cone(f"drip_{index}", (x, y, -reach / 2.0),
                    radius * 0.12, radius, reach, segments=20)
        displace(drip, fine, radius * 0.30, cuts=1)
        objects.append(drip)
        objects.append(displace(
            ellipsoid(f"root_{index}", (x, y, 0.0),
                      (radius * 1.30, radius * 1.30, radius * 0.60), segments=20),
            coarse, radius * 0.25, cuts=1))
    return objects, "xy"


PRESETS = {
    "wall_pilasters": wall_pilasters,
    "wall_niche": wall_niche,
    "floor_flagstones": floor_flagstones,
    "floor_inlay": floor_inlay,
    "ceiling_coffers": ceiling_coffers,
    "ceiling_vault": ceiling_vault,
    "floor_cobbles": floor_cobbles,
    "floor_slabs_varied": floor_slabs_varied,
    "wall_rubble": wall_rubble,
    "wall_cave": wall_cave,
    "ceiling_dripstone": ceiling_dripstone,
    "wall_boulders_rough": wall_boulders_rough,
    "wall_eroded": wall_eroded,
    "floor_cobbles_rough": floor_cobbles_rough,
    "ceiling_dripstone_rough": ceiling_dripstone_rough,
    "wall_blind_arcade": wall_blind_arcade,
    "ceiling_fan_vault": ceiling_fan_vault,
    "floor_hypocaust": floor_hypocaust,
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
    "floor_cobbles": "floor",
    "floor_slabs_varied": "floor",
    "wall_rubble": "wall",
    "wall_cave": "wall",
    "ceiling_dripstone": "ceiling",
    "wall_boulders_rough": "wall",
    "wall_eroded": "wall",
    "floor_cobbles_rough": "floor",
    "ceiling_dripstone_rough": "ceiling",
    "wall_blind_arcade": "wall",
    "ceiling_fan_vault": "ceiling",
    "floor_hypocaust": "floor",
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
