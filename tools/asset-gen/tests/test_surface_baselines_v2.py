import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "tools" / "asset-gen" / "surface_baselines_v2.py"


def load_module():
    spec = importlib.util.spec_from_file_location("surface_baselines_v2_test", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load V2 surface baseline generator")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


surface = load_module()


class SurfaceBaselinesV2Tests(unittest.TestCase):
    def test_expected_recipe_set(self):
        self.assertEqual(
            set(surface.RECIPES),
            {
                "wall_ritual_pilasters",
                "floor_broken_flagstones",
                "ceiling_shallow_coffers",
                "wall_ossuary_boulders",
            },
        )

    def test_all_fields_are_exactly_repeatable(self):
        for asset_id in sorted(surface.RECIPES):
            with self.subTest(asset_id=asset_id):
                first = surface.build_field(asset_id, 65)[1]
                second = surface.build_field(asset_id, 65)[1]
                third = surface.build_field(asset_id, 65)[1]
                self.assertEqual(first, second)
                self.assertEqual(second, third)
                self.assertEqual(
                    surface.sha256(surface.field_bytes(first)),
                    surface.sha256(surface.field_bytes(third)),
                )

    def test_declared_tile_axes_are_exact(self):
        size = 65
        for asset_id, recipe in sorted(surface.RECIPES.items()):
            with self.subTest(asset_id=asset_id):
                field = surface.build_field(asset_id, size)[1]
                if "x" in recipe.tile_axes:
                    self.assertEqual(
                        [field[y * size] for y in range(size)],
                        [field[y * size + size - 1] for y in range(size)],
                    )
                if "y" in recipe.tile_axes:
                    self.assertEqual(field[:size], field[-size:])

    def test_metric_and_guide_encodings_are_bounded(self):
        for asset_id in sorted(surface.RECIPES):
            with self.subTest(asset_id=asset_id):
                field = surface.build_field(asset_id, 65)[1]
                metric = surface.metric_values(field)
                guide, median, scale = surface.guide_values(field)
                self.assertTrue(all(1 <= value <= 65535 for value in metric))
                self.assertTrue(all(16 <= value <= 240 for value in guide))
                self.assertGreaterEqual(scale, 1)
                self.assertIn(median, sorted(field))

    def test_artifacts_are_byte_repeatable(self):
        for asset_id in sorted(surface.RECIPES):
            with self.subTest(asset_id=asset_id):
                first, first_metadata = surface.baseline_artifacts(asset_id, 65)
                second, second_metadata = surface.baseline_artifacts(asset_id, 65)
                self.assertEqual(first, second)
                self.assertEqual(first_metadata, second_metadata)
                self.assertEqual(first_metadata["representation"], "plane")
                self.assertEqual(first_metadata["role"], "surface_material")
                self.assertEqual(first_metadata["authoringSpace"], "depth_tile")
                self.assertEqual(first_metadata["placementFrame"], "surface_domain")

    def test_write_and_verify_complete_set(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            surface.write_baselines(root, sorted(surface.RECIPES), 65, 3)
            manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(len(manifest["baselines"]), 4)
            with tempfile.TemporaryDirectory() as second_directory:
                second = Path(second_directory)
                surface.write_baselines(second, sorted(surface.RECIPES), 65, 3)
                self.assertEqual(surface.compare_directories(root, second), [])

    def test_tracked_baselines_match_generator(self):
        tracked = ROOT / "assets" / "geometry" / "2_procedural_surface_baselines"
        with tempfile.TemporaryDirectory() as directory:
            generated = Path(directory)
            surface.write_baselines(generated, sorted(surface.RECIPES), 128, 3)
            self.assertEqual(surface.compare_directories(tracked, generated), [])

    def test_contract_vocabulary_matches_baseline_metadata(self):
        contract = json.loads((ROOT / "tools" / "asset-language" / "contract.json").read_text(encoding="utf-8"))
        artifacts, metadata = surface.baseline_artifacts("wall_ritual_pilasters", 65)
        self.assertIn(metadata["representation"], contract["representations"])
        self.assertIn(metadata["role"], contract["roles"])
        self.assertIn(metadata["authoringSpace"], contract["authoringSpaces"])
        self.assertIn(metadata["placementFrame"], contract["placementFrames"])
        self.assertEqual(metadata["metricEncoding"]["neutral"], contract["depthProducts"]["height_metric"]["neutral"])
        self.assertEqual(metadata["guideEncoding"]["neutral"], contract["depthProducts"]["depth_guide"]["neutral"])

    def test_generator_does_not_import_random(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertNotIn("import random", source)
        self.assertNotIn("from random", source)

    def test_blender_preview_is_explicitly_derivative(self):
        preview_path = ROOT / "tools" / "asset-gen" / "blender" / "build_surface_v2_preview.py"
        source = preview_path.read_text(encoding="utf-8")
        self.assertIn('"canonical": False', source)
        self.assertIn("fieldQ15LeSha256", source)
        self.assertNotIn("ray_cast", source)
        self.assertNotIn("BVHTree", source)


if __name__ == "__main__":
    unittest.main()
