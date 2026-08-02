#!/usr/bin/env python3
"""Parametric kit-piece generator: OBJ + MTL for the polygonal world renderer.

WHY A SCRIPT AND NOT A MESH GENERATOR (TRELLIS, Hunyuan3D, Rodin, ...):
the binding constraints for architectural kit pieces are things a generator
guarantees by construction and a neural mesh generator cannot.

  * Pieces must meet cleanly at cell boundaries (roadmap 5.4, "kit tiling
    rules"). Generated geometry is snapped to the cell by construction.
  * UVs must land on the EXISTING 64px atlas cells so a model and the wall
    behind it share texels. Neural output arrives with its own unwrap and its
    own baked texture, which is precisely the mismatch roadmap 5.4 warns about.
  * The budget is tens of triangles, faceted, at a 256x144 framebuffer. Neural
    output is dense and smooth and needs retopo before it is usable.
  * Deterministic, diffable, regenerable -- same shape as gen_tileset.py.

TEXEL DENSITY, the standard roadmap 5.4 asks for and this closes:

    1 map cell = 1 model unit = 64 atlas pixels.

So a face 0.5 units wide spans exactly 32 atlas pixels, and a model's texels
land at the same scale as the wall it stands against. Every face here is
UV-mapped by that rule rather than by an arbitrary unwrap.

CONVENTIONS (SPEC 1.8): OBJ (0,0,0) is the CENTRE of the owning map cell at
floor level; +Z is up; X/Y is the floor plane; one unit is one cell.

UV ORIENTATION: emitted in IMAGE space -- (0,0) is the TOP-LEFT of the atlas --
because presentation/obj_model.lua passes UVs straight through to LOVE, which
samples textures from the top-left. This is NOT the OBJ bottom-left convention;
mixing them up renders every piece vertically mirrored.

Usage:
    python tools/asset-gen/kitgen.py --out assets/models/kit
"""

import argparse
import os

CELL_PX = 64  # one atlas cell, and one model unit


class Mesh:
    """Accumulates quads with flat per-face normals.

    Flat, deliberately: one normal per FACE, not per vertex. Smooth-shaded
    low-poly reads as a soft blob under the world's directional shading, and
    roadmap 8.1 already argued that smooth interpolation is exactly what fights
    hand-authored pixel art. Faceting is the period-correct look and it is also
    what makes a 36-triangle piece legible at 30 pixels tall.
    """

    def __init__(self, atlas_cols, atlas_rows):
        self.v, self.vt, self.vn, self.groups = [], [], [], {}
        self.atlas_cols, self.atlas_rows = atlas_cols, atlas_rows

    def _uv(self, cell, u, v):
        """Map (u,v) in 0..1 within atlas `cell` = (row, col) to whole-atlas UV."""
        row, col = cell
        return ((col + u) / self.atlas_cols, (row + v) / self.atlas_rows)

    def quad(self, material, cell, corners, uv_extent):
        """One quad. `corners` is 4 (x,y,z) in winding order; `uv_extent` is the
        face's (width, height) IN UNITS, converted to atlas span by the texel
        rule above so the texture never stretches with the geometry."""
        w, h = uv_extent
        # Clamp to one cell: a face wider than a cell would sample its
        # neighbour, which is a tiling bug rather than a wrap.
        w, h = min(w, 1.0), min(h, 1.0)
        uvs = [(0, h), (w, h), (w, 0), (0, 0)]

        base = len(self.v) + 1
        ax = (corners[1][0] - corners[0][0], corners[1][1] - corners[0][1],
              corners[1][2] - corners[0][2])
        bx = (corners[2][0] - corners[0][0], corners[2][1] - corners[0][1],
              corners[2][2] - corners[0][2])
        n = (ax[1] * bx[2] - ax[2] * bx[1],
             ax[2] * bx[0] - ax[0] * bx[2],
             ax[0] * bx[1] - ax[1] * bx[0])
        length = (n[0] ** 2 + n[1] ** 2 + n[2] ** 2) ** 0.5 or 1.0
        n = (n[0] / length, n[1] / length, n[2] / length)

        self.vn.append(n)
        ni = len(self.vn)
        refs = []
        for i, corner in enumerate(corners):
            self.v.append(corner)
            self.vt.append(self._uv(cell, *uvs[i]))
            refs.append((base + i, base + i, ni))
        self.groups.setdefault(material, []).append(refs)

    def box(self, center, size, cell, materials=None, skip=()):
        """Axis-aligned box. The workhorse: every piece below is boxes, which is
        what keeps pieces tiling and silhouettes chunky."""
        cx, cy, cz = center
        sx, sy, sz = size
        x0, x1 = cx - sx / 2, cx + sx / 2
        y0, y1 = cy - sy / 2, cy + sy / 2
        z0, z1 = cz, cz + sz
        m = materials or {}

        faces = {
            "north": ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (sx, sz)),
            "south": ([(x1, y0, z0), (x0, y0, z0), (x0, y0, z1), (x1, y0, z1)], (sx, sz)),
            "east":  ([(x1, y1, z0), (x1, y0, z0), (x1, y0, z1), (x1, y1, z1)], (sy, sz)),
            "west":  ([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], (sy, sz)),
            "top":   ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (sx, sy)),
            "bottom": ([(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)], (sx, sy)),
        }
        for name, (corners, extent) in faces.items():
            if name in skip:
                continue   # never emit a face the player cannot see
            self.quad(m.get(name, m.get("all", "stone")),
                      cell, corners, extent)

    def write(self, path, name, mtllib, materials):
        with open(path + ".obj", "w", encoding="utf-8", newline="\n") as fh:
            fh.write("# Generated by tools/asset-gen/kitgen.py -- do not hand-edit.\n")
            fh.write("# Cell-centred, +Y up, -Z forward, 1 unit = 1 cell = %d atlas px.\n" % CELL_PX)
            fh.write("mtllib %s\n" % mtllib)
            fh.write("o %s\n" % name)
            for x, y, z in self.v:
                # The generator works in the engine's Z-up coordinates; OBJ
                # files use the Blender-compatible Y-up convention.
                fh.write("v %g %g %g\n" % (x, z, -y))
            for u, v in self.vt:
                fh.write("vt %g %g\n" % (u, v))
            for x, y, z in self.vn:
                fh.write("vn %g %g %g\n" % (x, z, -y))
            for material, faces in self.groups.items():
                fh.write("usemtl %s\n" % material)
                for refs in faces:
                    fh.write("f " + " ".join("%d/%d/%d" % r for r in refs) + "\n")
        with open(path + ".mtl", "w", encoding="utf-8", newline="\n") as fh:
            fh.write("# Generated by tools/asset-gen/kitgen.py -- do not hand-edit.\n")
            for material, (tint, texture) in materials.items():
                fh.write("\nnewmtl %s\n" % material)
                fh.write("Kd %.4f %.4f %.4f\n" % tint)
                if texture:
                    # The whole point: sample the SAME atlas the walls do, so a
                    # kit piece and the wall behind it share texels and palette.
                    fh.write("map_Kd %s\n" % texture)

    def face_count(self):
        return sum(len(f) for f in self.groups.values())


# --- The library ------------------------------------------------------------
# Each piece is deliberately a handful of boxes. Compare the hand/AI-authored
# set: gothic_pillar is 348 faces with 3 UV coordinates (i.e. untextured);
# these are ~20-40 faces, fully textured from the map's own atlas.

WALL = (1, 1)    # dungeon_001 row 1: plain brick
FLOOR = (3, 0)   # row 3: cobbles
DOOR = (2, 0)    # row 2: the arch/door row


def arch(mesh):
    """Structural `opening` frame: two jambs and a lintel, passable between.

    Roadmap 5.2 calls this "the best possible first model" -- the renderer's own
    comment concedes openings currently borrow the door row as a stand-in.
    """
    for sign in (-1, 1):
        mesh.box((sign * 0.4, 0, 0), (0.2, 0.5, 0.78), WALL, {"all": "kit_stone"})
    mesh.box((0, 0, 0.78), (1.0, 0.5, 0.22), WALL,
             {"all": "kit_stone"}, skip=("bottom",))


def pillar(mesh):
    """Base / shaft / capital. Three boxes, and it reads as a pillar because the
    silhouette steps -- which is all a 30px-tall column can convey anyway."""
    mesh.box((0, 0, 0.0), (0.52, 0.52, 0.12), FLOOR, {"all": "kit_floor"})
    mesh.box((0, 0, 0.12), (0.34, 0.34, 0.74), WALL, {"all": "kit_stone"},
             skip=("top", "bottom"))
    mesh.box((0, 0, 0.86), (0.52, 0.52, 0.14), WALL, {"all": "kit_stone"})


def brazier(mesh):
    """Floor fixture with an emissive bowl -- pairs with `emitsLight`."""
    mesh.box((0, 0, 0.0), (0.30, 0.30, 0.06), FLOOR, {"all": "kit_floor"})
    mesh.box((0, 0, 0.06), (0.12, 0.12, 0.26), WALL, {"all": "kit_stone"},
             skip=("top", "bottom"))
    mesh.box((0, 0, 0.32), (0.36, 0.36, 0.14), WALL, {"all": "kit_stone"},
             skip=("bottom",))
    # The coals sit just proud of the bowl rim so they are never z-fighting.
    mesh.box((0, 0, 0.45), (0.26, 0.26, 0.03), DOOR, {"all": "kit_ember"})


PIECES = {
    "kit_arch": arch,
    "kit_pillar": pillar,
    "kit_brazier": brazier,
}

MATERIALS = {
    "kit_stone": ((1.0, 1.0, 1.0), "assets/tilesets/dungeon_001.png"),
    "kit_floor": ((1.0, 1.0, 1.0), "assets/tilesets/dungeon_001.png"),
    # Tinted warm and left textured, so an ember reads as lit without needing a
    # second atlas or an emissive channel the renderer does not have.
    "kit_ember": ((1.0, 0.55, 0.22), "assets/tilesets/dungeon_001.png"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="assets/models/kit")
    parser.add_argument("--atlas-cols", type=int, default=4)
    parser.add_argument("--atlas-rows", type=int, default=4)
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    for name, build in sorted(PIECES.items()):
        mesh = Mesh(args.atlas_cols, args.atlas_rows)
        build(mesh)
        path = os.path.join(args.out, name)
        mesh.write(path, name, name + ".mtl", MATERIALS)
        print("%-14s %3d faces  %3d verts  -> %s.obj"
              % (name, mesh.face_count(), len(mesh.v), path))


if __name__ == "__main__":
    main()
