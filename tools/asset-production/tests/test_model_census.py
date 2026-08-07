"""Contract, geometry and staged-export checks for the 100-model census."""
from __future__ import annotations

import importlib.util
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSET_SET_PATH = ROOT / "assets/authoring/second_rite_census/asset-set.json"
sys.path.insert(0, str(ROOT / "tools/asset-production"))

import mesh_recipe  # noqa: E402


def _load_builder():
    path = ROOT / "tools/asset-production/build_model_census.py"
    spec = importlib.util.spec_from_file_location("build_model_census", path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


BUILDER = _load_builder()


def _obj_problems(text: str) -> list[str]:
    """Return loud interchange errors; valid polygon complexity is not a problem."""
    vertices = []
    problems = []
    for line_number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if line.startswith("v "):
            fields = line.split()
            if len(fields) != 4:
                problems.append(f"line {line_number}: malformed vertex")
                continue
            try:
                vertex = tuple(float(value) for value in fields[1:])
            except ValueError:
                problems.append(f"line {line_number}: malformed vertex")
                continue
            if not all(math.isfinite(value) for value in vertex):
                problems.append(f"line {line_number}: non-finite vertex")
            vertices.append(vertex)
        elif line.startswith("f "):
            refs = []
            for token in line.split()[1:]:
                try:
                    refs.append(int(token.split("/")[0]))
                except ValueError:
                    problems.append(f"line {line_number}: malformed face index")
            if len(refs) < 3 or len(set(refs)) < 3:
                problems.append(f"line {line_number}: degenerate face")
            if any(index == 0 or abs(index) > len(vertices) for index in refs):
                problems.append(f"line {line_number}: face index out of range")
    if not vertices:
        problems.append("OBJ has no vertices")
    return problems


class CensusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(ASSET_SET_PATH.read_text(encoding="utf-8"))
        cls.assets = BUILDER.assert_catalogue(cls.data)

    def test_exactly_100_distinct_concepts(self):
        self.assertEqual(len(self.assets), 100)
        self.assertEqual(len({asset["id"] for asset in self.assets}), 100)
        self.assertEqual(
            sum(len(asset["states"]) for asset in self.assets),
            157,
            "semantic state exports must not be confused with concept count",
        )

    def test_states_are_not_variants(self):
        self.assertTrue(all(asset["variants"] == [] for asset in self.assets))
        self.assertTrue(
            all(
                set(asset["products"]["states"]) == set(asset["states"])
                for asset in self.assets
            )
        )

    def test_all_use_shared_recipe(self):
        self.assertTrue(
            all(
                asset["recipe"] == "recipes.second_rite_census.catalogue"
                for asset in self.assets
            )
        )

    def test_every_declared_state_builds_finite_nonempty_geometry_before_failure_injection(self):
        for asset in self.assets:
            for state in asset["states"]:
                with self.subTest(asset=asset["id"], state=state):
                    mesh = mesh_recipe.make_model(asset, state)
                    self.assertGreater(len(mesh.vertices), 0)
                    self.assertGreater(len(mesh.faces), 0)
                    self.assertTrue(
                        all(
                            math.isfinite(value)
                            for vertex in mesh.vertices
                            for value in vertex
                        )
                    )
                    self.assertTrue(
                        all(
                            0 <= index < len(mesh.vertices)
                            for face, _ in mesh.faces
                            for index in face
                        )
                    )

    def test_multistate_concepts_have_distinct_geometry(self):
        for asset in self.assets:
            if len(asset["states"]) < 2:
                continue
            hashes = {
                BUILDER.canonical_hash(mesh_recipe.make_model(asset, state))
                for state in asset["states"]
            }
            with self.subTest(asset=asset["id"]):
                self.assertEqual(len(hashes), len(asset["states"]))

    def test_failure_injections_are_explicit_and_closed(self):
        expected = {
            "census_door_bronze_iris": "invalid_face_index",
            "census_trap_chain_pendulum": "degenerate_face",
            "census_wall_rose_window": "nan_vertex",
            "census_npc_oracle": "below_floor",
            "census_architecture_ritual_machine": "overscale",
        }
        actual = {
            asset["id"]: asset["census"]["failureInjection"]
            for asset in self.assets
            if "failureInjection" in asset["census"]
        }
        self.assertEqual(actual, expected)

    def test_only_three_injected_concepts_export_malformed_obj(self):
        malformed = {}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for asset in self.assets:
                injection = asset["census"].get("failureInjection")
                for state in asset["states"]:
                    mesh = mesh_recipe.make_model(asset, state)
                    if injection == "below_floor":
                        mesh.vertices = [(x, y, z - 0.08) for x, y, z in mesh.vertices]
                    elif injection == "overscale":
                        mesh.vertices = [(x * 1.3, y * 1.3, z) for x, y, z in mesh.vertices]
                    path = root / f"{asset['id']}_{state}.obj"
                    BUILDER.export_obj(path, asset, state, mesh, injection)
                    text = path.read_text(encoding="utf-8")
                    self.assertEqual(
                        sum(line.startswith("vt ") for line in text.splitlines()),
                        sum(len(face) for face, _ in mesh.faces),
                    )
                    regular_faces = [
                        line for line in text.splitlines() if line.startswith("f ")
                    ][: len(mesh.faces)]
                    self.assertTrue(
                        all(
                            "/" in token
                            for line in regular_faces
                            for token in line.split()[1:]
                        )
                    )
                    problems = _obj_problems(text)
                    if problems:
                        malformed[f"{asset['id']}:{state}"] = problems
        self.assertEqual(
            set(malformed),
            {
                "census_door_bronze_iris:sealed",
                "census_door_bronze_iris:open",
                "census_trap_chain_pendulum:inactive",
                "census_trap_chain_pendulum:active",
                "census_trap_chain_pendulum:spent",
                "census_wall_rose_window:default",
            },
        )
        self.assertTrue(all(malformed.values()))

    def test_manual_judgments_live_with_content_not_tool_code(self):
        judgments = [
            asset["census"]["manualJudgment"]
            for asset in self.assets
            if asset["census"].get("manualJudgment")
        ]
        self.assertEqual(len(judgments), 16)
        source = (ROOT / "tools/asset-production/build_model_census.py").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("MANUAL_REJECT", source)
        self.assertNotIn("CORRUPTIONS", source)

    def test_materials_come_from_registry_and_textures_are_deterministic(self):
        registry = json.loads(
            (ROOT / "tools/asset-language/materials.json").read_text(encoding="utf-8")
        )
        expected = {
            row["id"]: tuple(float(value) for value in row["legacyMtl"]["kd"])
            for row in registry["materials"]
        }
        self.assertEqual(mesh_recipe.MATERIALS, expected)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            texture_dir = root / "models/materials"
            report_dir = root / "report"
            report_dir.mkdir(parents=True)
            BUILDER.write_material_textures(texture_dir, report_dir)
            first_hashes = {
                path.name: path.read_bytes()
                for path in sorted(texture_dir.glob("*.png"))
            }
            self.assertEqual(len(first_hashes), len(expected))
            BUILDER.write_material_textures(texture_dir, report_dir)
            second_hashes = {
                path.name: path.read_bytes()
                for path in sorted(texture_dir.glob("*.png"))
            }
            self.assertEqual(first_hashes, second_hashes)
            self.assertTrue((report_dir / "material-swatches.png").is_file())

    def test_score_adjustments_live_in_asset_data(self):
        adjusted = [
            asset for asset in self.assets if asset["census"].get("scoreAdjustments")
        ]
        self.assertEqual(len(adjusted), 12)
        source = (ROOT / "tools/asset-production/mesh_recipe.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("scoreAdjustments", source)
        self.assertNotIn("census_architecture_ritual_machine': efficiency", source)


if __name__ == "__main__":
    unittest.main()
