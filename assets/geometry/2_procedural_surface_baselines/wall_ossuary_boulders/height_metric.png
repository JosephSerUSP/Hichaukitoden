import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools" / "blender" / "depth_baseline.py"
SPEC = importlib.util.spec_from_file_location("depth_baseline", SCRIPT)
depth_baseline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(depth_baseline)


class DepthBaselineTests(unittest.TestCase):
    def test_equal_images_are_exact(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            left = directory / "left.png"
            right = directory / "right.png"
            Image.new("RGBA", (2, 2), (128, 128, 128, 255)).save(left)
            Image.new("RGBA", (2, 2), (128, 128, 128, 255)).save(right)
            result = depth_baseline.compare_images(left, right)
            self.assertTrue(result["shapeEqual"])
            self.assertEqual(result["changedPixels"], 0)
            self.assertEqual(result["maximumChannelDelta"], 0)

    def test_difference_report_has_coordinates_and_delta(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            left = directory / "left.png"
            right = directory / "right.png"
            first = Image.new("RGBA", (2, 2), (128, 128, 128, 255))
            second = first.copy()
            second.putpixel((1, 0), (130, 128, 128, 255))
            first.save(left)
            second.save(right)
            result = depth_baseline.compare_images(left, right)
            self.assertEqual(result["changedPixels"], 1)
            self.assertEqual(result["maximumChannelDelta"], 2)
            self.assertEqual(result["firstDifferences"][0]["x"], 1)
            self.assertEqual(result["firstDifferences"][0]["y"], 0)

    def test_adopt_requires_explicit_confirmation_token(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("UPDATE_TRACKED_DEPTH_BASELINE", source)
        self.assertIn('args.mode == "adopt"', source)
        self.assertIn("--confirm-production-write", source)

    def test_three_runs_and_four_presets_are_hard_coded(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("for index in range(3)", source)
        for preset in (
                "wall_pilasters", "floor_flagstones",
                "ceiling_coffers", "wall_boulders_rough"):
            self.assertIn(preset, source)


if __name__ == "__main__":
    unittest.main()
