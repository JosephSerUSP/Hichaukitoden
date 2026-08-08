import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "asset-gen"))

import build_cracked_inpaint_20260807 as cracked  # noqa: E402
from lib import provider  # noqa: E402


class CrackedInpaintTests(unittest.TestCase):
    def test_interior_only_protects_only_declared_axes(self):
        mask = np.ones((10, 10), dtype=bool)

        wall = cracked.interior_only(mask, "x", margin=2)
        self.assertFalse(wall[:, :2].any())
        self.assertFalse(wall[:, -2:].any())
        self.assertTrue(wall[2:-2, 2:-2].all())
        self.assertTrue(wall[:2, 2:-2].all())

        floor = cracked.interior_only(mask, "xy", margin=2)
        self.assertFalse(floor[:2, :].any())
        self.assertFalse(floor[-2:, :].any())
        self.assertFalse(floor[:, :2].any())
        self.assertFalse(floor[:, -2:].any())

    def test_best_variant_falls_back_within_same_run(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / "tool"
            out = tool / "out"
            reviews = tool / "reviews"
            reviews.mkdir(parents=True)
            run = "texturePiece-approved-20260807-120000"
            run_dir = out / run
            run_dir.mkdir(parents=True)
            # The score-6 raw was pruned, but score-5 from the same run survives.
            (run_dir / "raw-2.png").write_bytes(b"raw")
            (run_dir / "variant-2.png").write_bytes(b"base")
            (reviews / "ratings.json").write_text(json.dumps({
                f"{run}#1": {"score": 6},
                f"{run}#2": {"score": 5},
            }), encoding="utf-8")

            with patch.object(cracked, "TOOL", tool), patch.object(cracked, "OUT", out):
                self.assertEqual(cracked.best_variant("approved"), (run, 2, 5))

    def test_processed_variant_must_match_actual_base_edges(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = np.full((8, 8, 4), [20, 30, 40, 255], dtype=np.uint8)
            variant = base.copy()
            variant[3:5, 3:5, :3] = [200, 210, 220]
            base_path = root / "base.png"
            variant_path = root / "variant.png"
            Image.fromarray(base, mode="RGBA").save(base_path)
            Image.fromarray(variant, mode="RGBA").save(variant_path)

            result = cracked.verify_variant_compatibility(
                base_path, variant_path, "xy", width=2)
            self.assertEqual(result["borderDelta"], 0)
            self.assertEqual(result["width"], 8)

            variant[0, 4, :3] = [1, 2, 3]
            Image.fromarray(variant, mode="RGBA").save(variant_path)
            with self.assertRaisesRegex(RuntimeError, "border differs"):
                cracked.verify_variant_compatibility(base_path, variant_path, "xy", width=2)

    def test_inpaint_request_crops_to_the_damage_mask(self):
        image = Image.new("RGB", (8, 8), (80, 90, 100))
        mask = Image.new("L", (8, 8), 0)
        mask.putpixel((4, 4), 255)
        response = Mock(ok=True)
        response.json.return_value = {"images": [provider.base64.b64encode(
            provider._png_bytes(image)).decode("ascii")]}
        with patch.object(provider.requests, "post", return_value=response) as post:
            provider.inpaint_region(
                "http://forge", "model", "cracked stone", image, mask,
                {"inpaintFullRes": True, "inpaintFullResPadding": 32})
        body = post.call_args.kwargs["json"]
        self.assertTrue(body["inpaint_full_res"])
        self.assertEqual(body["inpaint_full_res_padding"], 32)


if __name__ == "__main__":
    unittest.main()
