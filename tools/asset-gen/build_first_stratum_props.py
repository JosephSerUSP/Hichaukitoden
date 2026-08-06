#!/usr/bin/env python3
"""Generator for First Stratum 3D Props and Replacement Treasure Chest.

Produces clean, low-poly OBJ + MTL models for dungeon fixtures and props:
  - dungeon_chest.obj / .mtl (Replacement Treasure Chest - hero prop)
  - dungeon_altar.obj / .mtl (Sacred stone altar)
  - shrine_table.obj / .mtl (Carved shrine table)
  - ceremonial_pedestal.obj / .mtl (Stepped octagonal pedestal)
  - dungeon_brazier.obj / .mtl (Tripodal iron brazier)
  - wall_sconce.obj / .mtl (Cast bronze wall sconce)
  - funerary_urn.obj / .mtl (Ceramic funerary urn)
  - reliquary_fixture.obj / .mtl (Reliquary box on pillar)
  - stone_bench.obj / .mtl (Civic/funerary stone bench)
  - sarcophagus.obj / .mtl (Carved stone tomb chest)
  - column_fragment.obj / .mtl (Broken fluted column piece)
  - niche_fixture.obj / .mtl (Arched shrine niche frame)
  - cistern_basin.obj / .mtl (Carved stone water basin)

Conventions:
  - Engine Z is UP. In emitted OBJ: X_obj = X_eng, Y_obj = Z_eng, Z_obj = -Y_eng.
  - Cell centered at (0,0,0) floor level.
"""

import math
import os

OUT_DIR = "assets/models/dungeon"


class MeshBuilder:
    def __init__(self):
        self.verts = []
        self.uvs = []
        self.normals = []
        self.groups = {}  # material -> list of face tuples

    def _add_vertex(self, x, y, z):
        # Convert engine coords (X, Y floor plane, Z up) to OBJ coords (X, Z_up, -Y)
        self.verts.append((x, z, -y))
        return len(self.verts)

    def _add_uv(self, u, v):
        self.uvs.append((u, v))
        return len(self.uvs)

    def _add_normal(self, nx, ny, nz):
        # Convert engine normal to OBJ normal
        l = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
        self.normals.append((nx / l, nz / l, -ny / l))
        return len(self.normals)

    def quad(self, material, corners, uvs=None):
        """Add a quad given 4 engine-coord points (in CCW winding from outside)."""
        if uvs is None:
            uvs = [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)]
        
        # Calculate normal
        ax, ay, az = corners[1][0] - corners[0][0], corners[1][1] - corners[0][1], corners[1][2] - corners[0][2]
        bx, by, bz = corners[2][0] - corners[0][0], corners[2][1] - corners[0][1], corners[2][2] - corners[0][2]
        nx = ay * bz - az * by
        ny = az * bx - ax * bz
        nz = ax * by - ay * bx

        ni = self._add_normal(nx, ny, nz)
        
        face_refs = []
        for i in range(4):
            vi = self._add_vertex(*corners[i])
            ti = self._add_uv(*uvs[i])
            face_refs.append((vi, ti, ni))
        
        self.groups.setdefault(material, []).append(face_refs)

    def polygon(self, material, corners, uvs=None):
        """Add a convex n-gon by fan triangulation."""
        if len(corners) == 4:
            self.quad(material, corners, uvs)
            return
        
        # Calculate normal from first 3 vertices
        ax, ay, az = corners[1][0] - corners[0][0], corners[1][1] - corners[0][1], corners[1][2] - corners[0][2]
        bx, by, bz = corners[2][0] - corners[0][0], corners[2][1] - corners[0][1], corners[2][2] - corners[0][2]
        nx = ay * bz - az * by
        ny = az * bx - ax * bz
        nz = ax * by - ay * bx
        ni = self._add_normal(nx, ny, nz)

        v_indices = [self._add_vertex(*pt) for pt in corners]
        t_indices = [self._add_uv(*(uvs[i] if uvs else (0.5, 0.5))) for i in range(len(corners))]

        # Fan triangles from vertex 0
        for i in range(1, len(corners) - 1):
            face_refs = [
                (v_indices[0], t_indices[0], ni),
                (v_indices[i], t_indices[i], ni),
                (v_indices[i + 1], t_indices[i + 1], ni)
            ]
            self.groups.setdefault(material, []).append(face_refs)

    def box(self, material, center, size, materials_per_face=None, skip=()):
        cx, cy, cz = center
        sx, sy, sz = size
        x0, x1 = cx - sx / 2, cx + sx / 2
        y0, y1 = cy - sy / 2, cy + sy / 2
        z0, z1 = cz, cz + sz
        m = materials_per_face or {}

        faces = {
            "north": ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]),
            "south": ([(x1, y0, z0), (x0, y0, z0), (x0, y0, z1), (x1, y0, z1)]),
            "east":  ([(x1, y1, z0), (x1, y0, z0), (x1, y0, z1), (x1, y1, z1)]),
            "west":  ([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)]),
            "top":   ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]),
            "bottom": ([(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)]),
        }
        for name, corners in faces.items():
            if name in skip:
                continue
            mat = m.get(name, material)
            self.quad(mat, corners)

    def cylinder(self, material, center, radius, height, sides=8, top=True, bottom=True):
        cx, cy, cz = center
        angle_step = 2 * math.pi / sides
        
        bot_pts = [(cx + radius * math.cos(i * angle_step), cy + radius * math.sin(i * angle_step), cz) for i in range(sides)]
        top_pts = [(cx + radius * math.cos(i * angle_step), cy + radius * math.sin(i * angle_step), cz + height) for i in range(sides)]

        for i in range(sides):
            nxt = (i + 1) % sides
            corners = [bot_pts[i], bot_pts[nxt], top_pts[nxt], top_pts[i]]
            self.quad(material, corners)
        
        if top:
            # Top face (reverse winding for Z up)
            self.polygon(material, list(reversed(top_pts)))
        if bottom:
            self.polygon(material, bot_pts)

    def write(self, path_base, name, mtl_filename, materials_def):
        os.makedirs(os.path.dirname(path_base), exist_ok=True)
        obj_path = path_base + ".obj"
        mtl_path = path_base + ".mtl"

        with open(obj_path, "w", encoding="utf-8", newline="\n") as f:
            f.write("# Generated by tools/asset-gen/build_first_stratum_props.py\n")
            f.write(f"mtllib {mtl_filename}\n")
            f.write(f"o {name}\n\n")
            for vx, vy, vz in self.verts:
                f.write(f"v {vx:.6f} {vy:.6f} {vz:.6f}\n")
            for u, v in self.uvs:
                f.write(f"vt {u:.6f} {v:.6f}\n")
            for nx, ny, nz in self.normals:
                f.write(f"vn {nx:.6f} {ny:.6f} {nz:.6f}\n")
            
            for mat, faces in self.groups.items():
                f.write(f"\nusemtl {mat}\n")
                for face in faces:
                    f.write("f " + " ".join(f"{v}/{t}/{n}" for v, t, n in face) + "\n")

        with open(mtl_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(f"# Material library for {name}.obj\n")
            for mat_name, (r, g, b) in materials_def.items():
                f.write(f"\nnewmtl {mat_name}\n")
                f.write(f"Kd {r:.4f} {g:.4f} {b:.4f}\n")


# --- 1. REPLACEMENT TREASURE CHEST (dungeon_chest) ---
def build_dungeon_chest():
    b = MeshBuilder()
    # Main Body: Wood chest base
    b.box("wood_body", (0, 0, 0), (0.64, 0.44, 0.28))

    # Iron Corner Brackets & Banding
    b.box("iron_trim", (-0.31, 0, 0), (0.04, 0.45, 0.29)) # Left end cap
    b.box("iron_trim", (0.31, 0, 0), (0.04, 0.45, 0.29))  # Right end cap
    b.box("iron_trim", (0, 0.21, 0), (0.65, 0.04, 0.29))  # Front top/bot band
    b.box("iron_trim", (0, -0.21, 0), (0.65, 0.04, 0.29)) # Back band
    b.box("iron_trim", (0, 0, 0.13), (0.65, 0.45, 0.03))  # Rim trim

    # Vaulted/Domed Lid
    lid_h = 0.16
    segments = 6
    for i in range(segments):
        a1 = i * math.pi / segments
        a2 = (i + 1) * math.pi / segments
        y1 = -0.22 * math.cos(a1)
        z1 = 0.14 + lid_h * math.sin(a1)
        y2 = -0.22 * math.cos(a2)
        z2 = 0.14 + lid_h * math.sin(a2)
        
        # Wood lid segments
        b.quad("wood_body", [(-0.31, y1, z1), (0.31, y1, z1), (0.31, y2, z2), (-0.31, y2, z2)])
    
    # Lid end caps (gables)
    gable_left = [(-0.32, -0.22 * math.cos(i * math.pi / segments), 0.14 + lid_h * math.sin(i * math.pi / segments)) for i in range(segments + 1)]
    b.polygon("iron_trim", gable_left)
    gable_right = [(0.32, -0.22 * math.cos(i * math.pi / segments), 0.14 + lid_h * math.sin(i * math.pi / segments)) for i in range(segments + 1)]
    b.polygon("iron_trim", list(reversed(gable_right)))

    # Lid iron spine ribs
    b.box("iron_trim", (0, 0, 0.22), (0.65, 0.05, 0.04))
    b.box("iron_trim", (-0.20, 0, 0.22), (0.04, 0.45, 0.04))
    b.box("iron_trim", (0.20, 0, 0.22), (0.04, 0.45, 0.04))

    # Ornate Lock Plate
    b.box("gold_lock", (0, 0.23, 0.12), (0.12, 0.03, 0.14)) # Lock plate
    b.box("gold_lock", (0, 0.24, 0.10), (0.04, 0.02, 0.06)) # Keyhole protrusion

    # Handles
    b.box("iron_trim", (-0.33, 0, 0.10), (0.03, 0.10, 0.04))
    b.box("iron_trim", (0.33, 0, 0.10), (0.03, 0.10, 0.04))

    mats = {
        "wood_body": (0.38, 0.24, 0.13),
        "iron_trim": (0.20, 0.22, 0.25),
        "gold_lock": (0.85, 0.70, 0.20)
    }
    b.write(f"{OUT_DIR}/dungeon_chest", "dungeon_chest", "dungeon_chest.mtl", mats)


# --- 2. SACRED STONE ALTAR (dungeon_altar) ---
def build_dungeon_altar():
    b = MeshBuilder()
    b.box("stone_base", (0, 0, 0), (0.80, 0.50, 0.10))
    b.box("stone_carved", (0, 0, 0.10), (0.70, 0.42, 0.35))
    b.box("stone_slab", (0, 0, 0.45), (0.86, 0.56, 0.12))
    # Brass corner trim & basin dip
    b.box("brass_accent", (0, 0, 0.56), (0.70, 0.38, 0.02))
    mats = {
        "stone_base": (0.32, 0.32, 0.34),
        "stone_carved": (0.42, 0.40, 0.38),
        "stone_slab": (0.48, 0.46, 0.44),
        "brass_accent": (0.75, 0.60, 0.25)
    }
    b.write(f"{OUT_DIR}/dungeon_altar", "dungeon_altar", "dungeon_altar.mtl", mats)


# --- 3. SHRINE TABLE (shrine_table) ---
def build_shrine_table():
    b = MeshBuilder()
    b.box("carved_stone", (0, 0, 0), (0.60, 0.40, 0.08)) # plinth
    b.cylinder("carved_stone", (-0.22, -0.12, 0.08), 0.06, 0.38, sides=6)
    b.cylinder("carved_stone", (0.22, -0.12, 0.08), 0.06, 0.38, sides=6)
    b.cylinder("carved_stone", (-0.22, 0.12, 0.08), 0.06, 0.38, sides=6)
    b.cylinder("carved_stone", (0.22, 0.12, 0.08), 0.06, 0.38, sides=6)
    b.box("carved_stone", (0, 0, 0.46), (0.64, 0.44, 0.08)) # top
    mats = {"carved_stone": (0.45, 0.43, 0.40)}
    b.write(f"{OUT_DIR}/shrine_table", "shrine_table", "shrine_table.mtl", mats)


# --- 4. CEREMONIAL PEDESTAL (ceremonial_pedestal) ---
def build_ceremonial_pedestal():
    b = MeshBuilder()
    b.cylinder("pedestal_base", (0, 0, 0), 0.32, 0.10, sides=8)
    b.cylinder("pedestal_shaft", (0, 0, 0.10), 0.22, 0.50, sides=8)
    b.cylinder("pedestal_top", (0, 0, 0.60), 0.30, 0.10, sides=8)
    b.cylinder("bronze_ring", (0, 0, 0.33), 0.23, 0.04, sides=8)
    mats = {
        "pedestal_base": (0.35, 0.35, 0.36),
        "pedestal_shaft": (0.42, 0.41, 0.40),
        "pedestal_top": (0.48, 0.47, 0.45),
        "bronze_ring": (0.65, 0.50, 0.22)
    }
    b.write(f"{OUT_DIR}/ceremonial_pedestal", "ceremonial_pedestal", "ceremonial_pedestal.mtl", mats)


# --- 5. TRIPODAL BRAZIER (dungeon_brazier) ---
def build_dungeon_brazier():
    b = MeshBuilder()
    # Legs
    for a in (0, 2.094, 4.188):
        lx, ly = 0.20 * math.cos(a), 0.20 * math.sin(a)
        b.box("wrought_iron", (lx, ly, 0), (0.04, 0.04, 0.35))
    # Bowl
    b.cylinder("wrought_iron", (0, 0, 0.35), 0.26, 0.14, sides=8)
    # Burning Coals
    b.cylinder("glowing_embers", (0, 0, 0.45), 0.22, 0.05, sides=8)
    mats = {
        "wrought_iron": (0.18, 0.19, 0.21),
        "glowing_embers": (0.90, 0.45, 0.10)
    }
    b.write(f"{OUT_DIR}/dungeon_brazier", "dungeon_brazier", "dungeon_brazier.mtl", mats)


# --- 6. CAST BRONZE WALL SCONCE (wall_sconce) ---
def build_wall_sconce():
    b = MeshBuilder()
    b.box("bronze_fixture", (0, -0.45, 0.40), (0.12, 0.04, 0.24)) # backplate
    b.box("bronze_fixture", (0, -0.38, 0.40), (0.04, 0.12, 0.04)) # arm
    b.cylinder("bronze_fixture", (-0.10, -0.32, 0.40), 0.05, 0.08, sides=6) # left socket
    b.cylinder("bronze_fixture", (0.10, -0.32, 0.40), 0.05, 0.08, sides=6)  # right socket
    b.cylinder("wax_candle", (-0.10, -0.32, 0.48), 0.03, 0.12, sides=6)
    b.cylinder("wax_candle", (0.10, -0.32, 0.48), 0.03, 0.12, sides=6)
    mats = {
        "bronze_fixture": (0.55, 0.42, 0.22),
        "wax_candle": (0.85, 0.82, 0.72)
    }
    b.write(f"{OUT_DIR}/wall_sconce", "wall_sconce", "wall_sconce.mtl", mats)


# --- 7. FUNERARY URN / STORAGE JAR (funerary_urn) ---
def build_funerary_urn():
    b = MeshBuilder()
    b.cylinder("terracotta_glaze", (0, 0, 0), 0.12, 0.06, sides=8) # base
    b.cylinder("terracotta_glaze", (0, 0, 0.06), 0.22, 0.26, sides=8) # belly
    b.cylinder("terracotta_glaze", (0, 0, 0.32), 0.14, 0.12, sides=8) # neck
    b.cylinder("bronze_lid", (0, 0, 0.44), 0.16, 0.05, sides=8) # lid
    mats = {
        "terracotta_glaze": (0.52, 0.32, 0.24),
        "bronze_lid": (0.60, 0.48, 0.25)
    }
    b.write(f"{OUT_DIR}/funerary_urn", "funerary_urn", "funerary_urn.mtl", mats)


# --- 8. RELIQUARY FIXTURE (reliquary_fixture) ---
def build_reliquary_fixture():
    b = MeshBuilder()
    b.cylinder("stone_pillar", (0, 0, 0), 0.15, 0.50, sides=8)
    b.box("reliquary_gold", (0, 0, 0.50), (0.24, 0.24, 0.22))
    b.box("reliquary_crystal", (0, 0, 0.58), (0.12, 0.12, 0.12))
    mats = {
        "stone_pillar": (0.40, 0.39, 0.38),
        "reliquary_gold": (0.85, 0.72, 0.22),
        "reliquary_crystal": (0.60, 0.85, 0.90)
    }
    b.write(f"{OUT_DIR}/reliquary_fixture", "reliquary_fixture", "reliquary_fixture.mtl", mats)


# --- 9. STONE BENCH (stone_bench) ---
def build_stone_bench():
    b = MeshBuilder()
    b.box("carved_stone", (-0.28, 0, 0), (0.10, 0.30, 0.28)) # left leg
    b.box("carved_stone", (0.28, 0, 0), (0.10, 0.30, 0.28))  # right leg
    b.box("carved_stone", (0, 0, 0.28), (0.76, 0.36, 0.08))  # seat slab
    mats = {"carved_stone": (0.42, 0.41, 0.40)}
    b.write(f"{OUT_DIR}/stone_bench", "stone_bench", "stone_bench.mtl", mats)


# --- 10. CARVED SARCOPHAGUS (sarcophagus) ---
def build_sarcophagus():
    b = MeshBuilder()
    b.box("tomb_stone", (0, 0, 0), (0.90, 0.46, 0.36)) # chest base
    b.box("tomb_stone", (0, 0, 0.36), (0.94, 0.50, 0.14)) # carved lid
    b.box("bronze_inlay", (0, 0, 0.50), (0.60, 0.20, 0.02)) # lid emblem
    mats = {
        "tomb_stone": (0.38, 0.37, 0.36),
        "bronze_inlay": (0.65, 0.52, 0.25)
    }
    b.write(f"{OUT_DIR}/sarcophagus", "sarcophagus", "sarcophagus.mtl", mats)


# --- 11. BROKEN COLUMN FRAGMENT (column_fragment) ---
def build_column_fragment():
    b = MeshBuilder()
    b.cylinder("fluted_marble", (0, 0, 0), 0.24, 0.45, sides=8) # main broken stump
    b.box("rubble_stone", (0.18, 0.12, 0), (0.20, 0.18, 0.12))  # fallen capital piece
    mats = {
        "fluted_marble": (0.55, 0.53, 0.50),
        "rubble_stone": (0.45, 0.43, 0.40)
    }
    b.write(f"{OUT_DIR}/column_fragment", "column_fragment", "column_fragment.mtl", mats)


# --- 12. ARCHED NICHE FIXTURE (niche_fixture) ---
def build_niche_fixture():
    b = MeshBuilder()
    b.box("niche_frame", (0, -0.44, 0), (0.44, 0.06, 0.60)) # frame
    b.box("niche_frame", (0, -0.38, 0.15), (0.28, 0.08, 0.04)) # shelf
    b.cylinder("bronze_lamp", (0, -0.38, 0.19), 0.06, 0.06, sides=6) # oil lamp
    mats = {
        "niche_frame": (0.36, 0.35, 0.34),
        "bronze_lamp": (0.65, 0.48, 0.20)
    }
    b.write(f"{OUT_DIR}/niche_fixture", "niche_fixture", "niche_fixture.mtl", mats)


# --- 13. CISTERN BASIN / FOUNTAIN (cistern_basin) ---
def build_cistern_basin():
    b = MeshBuilder()
    b.cylinder("basin_stone", (0, 0, 0), 0.35, 0.28, sides=8) # outer basin
    b.cylinder("water_surface", (0, 0, 0.22), 0.28, 0.02, sides=8) # water
    b.box("bronze_spout", (0, 0, 0.28), (0.06, 0.06, 0.16)) # center spout
    mats = {
        "basin_stone": (0.34, 0.35, 0.36),
        "water_surface": (0.20, 0.45, 0.55),
        "bronze_spout": (0.55, 0.42, 0.22)
    }
    b.write(f"{OUT_DIR}/cistern_basin", "cistern_basin", "cistern_basin.mtl", mats)


def main():
    build_dungeon_chest()
    build_dungeon_altar()
    build_shrine_table()
    build_ceremonial_pedestal()
    build_dungeon_brazier()
    build_wall_sconce()
    build_funerary_urn()
    build_reliquary_fixture()
    build_stone_bench()
    build_sarcophagus()
    build_column_fragment()
    build_niche_fixture()
    build_cistern_basin()
    print("Successfully built all 13 First Stratum 3D props!")


if __name__ == "__main__":
    main()
