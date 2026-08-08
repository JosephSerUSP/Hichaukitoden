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
from lib import provider, ratings, report, staging  # noqa: E402


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

    def test_preview_surface_does_not_follow_crack_control_map(self):
        context = {"defaultSurface": "floor"}
        manifest = {
            "surface": "ceiling",
            "provider": {
                "heightControl": "tools/asset-gen/out/_crack-control-coffers.png",
            },
        }
        self.assertEqual(cracked.gen._preview_surface(manifest, context), "ceiling")

    def test_rating_and_report_show_the_exact_inpaint_base(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base_run = "texturePiece-approved-base-20260808-010000"
            crack_run = "texturePiece-cracked-20260808-010100"
            base_dir = root / base_run
            crack_dir = root / crack_run
            base_dir.mkdir()
            crack_dir.mkdir()
            Image.new("RGBA", (8, 8), (40, 50, 60, 255)).save(base_dir / "variant-2.png")
            Image.new("RGBA", (8, 8), (80, 50, 40, 255)).save(crack_dir / "variant-1.png")
            Image.new("RGB", (8, 8), (80, 50, 40)).save(crack_dir / "raw-1.png")
            staging.write_manifest(str(base_dir), {
                "manifestKind": staging.RUN_KIND,
                "manifestVersion": staging.RUN_VERSION,
                "class": "texturePiece",
                "name": "approved_base",
                "variants": [{"index": 2, "file": "variant-2.png"}],
            })
            crack_manifest = {
                "manifestKind": staging.RUN_KIND,
                "manifestVersion": staging.RUN_VERSION,
                "class": "texturePiece",
                "name": "cracked",
                "tileAxes": "xy",
                "provider": {"inpaintSource": f"{base_run}#2"},
                "variants": [{"index": 1, "file": "variant-1.png", "raw": "raw-1.png"}],
            }
            staging.write_manifest(str(crack_dir), crack_manifest)

            with patch.object(ratings, "load", return_value={}):
                items = ratings.queue(str(root), prefix="cracked")
            self.assertEqual(items[0]["base"]["run"], base_run)
            self.assertEqual(items[0]["base"]["variant"], 2)
            self.assertEqual(items[0]["base"]["image"],
                             f"/out/{base_run}/variant-2.png")

            section = report.run_section(str(crack_dir), crack_manifest)
            self.assertIn(f"approved base — {base_run}#2", section)


if __name__ == "__main__":
    unittest.main()
