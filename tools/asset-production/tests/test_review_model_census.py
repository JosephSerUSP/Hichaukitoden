import csv
import importlib.util
import json
import tempfile
import unittest
import sys
from pathlib import Path

from PIL import Image

MODULE_PATH = Path(__file__).resolve().parents[1] / "review_model_census.py"
spec = importlib.util.spec_from_file_location("review_model_census", MODULE_PATH)
review = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = review
spec.loader.exec_module(review)


def tiny_manifest():
    return {
        "full_matrix_count": 3,
        "skip_rules": [
            {
                "id": "functional_context_superseded_by_adapter_smoke_gate",
                "match": {"context": "functional"},
                "reason": "test",
            }
        ],
        "assets": [
            {
                "asset_id": "asset",
                "display_name": "Asset",
                "tier": "Tier A",
                "placement_adapter": "event_model",
                "states": [
                    {
                        "state": "default",
                        "model": "asset.obj",
                        "contexts": ["neutral", "first_stratum", "functional"],
                        "distances": ["one_cell"],
                        "angles": ["frontal"],
                        "lighting": ["normal"],
                    }
                ],
            }
        ],
    }


class ReviewModelCensusTests(unittest.TestCase):
    def test_structured_skip_removes_functional_from_required_matrix(self):
        rows = list(review.iter_matrix(tiny_manifest()))
        self.assertEqual(len(rows), 3)
        self.assertEqual(sum(1 for row in rows if row["skip_rule"]), 1)

    def test_failed_metadata_does_not_satisfy_required_frame(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            entries = [
                {
                    "asset_id": "asset",
                    "state": "default",
                    "context": "neutral",
                    "distance": "one_cell",
                    "angle": "frontal",
                    "lighting": "normal",
                    "path": "out/model-census-review/asset/neutral__one_cell__frontal__normal__default.png",
                    "success": False,
                    "error": "boom",
                }
            ]
            diag = review.process_captures(tiny_manifest(), entries, out)
            self.assertEqual(diag.failed_count, 1)
            self.assertIn("asset/neutral__one_cell__frontal__normal__default.png", diag.missing_paths)

    def test_success_metadata_requires_png_on_disk(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            entries = [
                {
                    "asset_id": "asset",
                    "state": "default",
                    "context": "neutral",
                    "distance": "one_cell",
                    "angle": "frontal",
                    "lighting": "normal",
                    "path": "out/model-census-review/asset/neutral__one_cell__frontal__normal__default.png",
                    "success": True,
                }
            ]
            diag = review.process_captures(tiny_manifest(), entries, out)
            self.assertEqual(diag.successful_count, 0)
            self.assertEqual(diag.failed_count, 1)

            png = out / "asset/neutral__one_cell__frontal__normal__default.png"
            png.parent.mkdir(parents=True)
            Image.new("RGB", (8, 8), "gray").save(png)
            diag = review.process_captures(tiny_manifest(), entries, out)
            self.assertEqual(diag.successful_count, 1)

    def test_duplicate_metadata_is_detected_by_logical_key(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            png = out / "asset/neutral__one_cell__frontal__normal__default.png"
            png.parent.mkdir(parents=True)
            Image.new("RGB", (8, 8), "gray").save(png)
            base = {
                "asset_id": "asset",
                "state": "default",
                "context": "neutral",
                "distance": "one_cell",
                "angle": "frontal",
                "lighting": "normal",
                "path": "asset/neutral__one_cell__frontal__normal__default.png",
                "success": True,
            }
            diag = review.process_captures(tiny_manifest(), [base, dict(base)], out)
            self.assertEqual(len(diag.duplicate_keys), 1)

    def test_incomplete_jsonl_recovery_preserves_complete_rows(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "captures.jsonl"
            path.write_text('{"a":1}\n{"b":', encoding="utf-8")
            rows, warnings = review.recover_jsonl(path)
            self.assertEqual(rows, [{"a": 1}])
            self.assertEqual(len(warnings), 1)

    def test_review_csv_merge_never_overwrites_human_scores(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "review.csv"
            path.write_text(
                "asset_id,recognition,spatialFunction,styleIntegration,materialHierarchy,screenEconomy,emotionalFunction,verdict,notes\n"
                "asset,5,4,3,2,1,5,promote_candidate,human note\n",
                encoding="utf-8",
            )
            review.merge_review_csv(path, tiny_manifest()["assets"])
            with path.open(newline="", encoding="utf-8") as f:
                row = next(csv.DictReader(f))
            self.assertEqual(row["recognition"], "5")
            self.assertEqual(row["verdict"], "promote_candidate")
            self.assertEqual(row["notes"], "human note")

    def test_border_occupancy_flags_edge_laden_frame(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "edge.png"
            img = Image.new("RGB", (32, 32), (20, 20, 20))
            for x in range(32):
                img.putpixel((x, 0), (255, 255, 255))
                img.putpixel((x, 31), (255, 255, 255))
            for y in range(32):
                img.putpixel((0, y), (255, 255, 255))
                img.putpixel((31, y), (255, 255, 255))
            img.save(path)
            self.assertGreater(review.border_occupancy(path, border=1), 0.9)

    def test_primary_contact_sheet_is_four_view_comparison(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            manifest = tiny_manifest()
            state = manifest["assets"][0]["states"][0]
            state["angles"] = ["frontal", "oblique"]
            entries = []
            for context in ("neutral", "first_stratum"):
                for angle in ("frontal", "oblique"):
                    rel = f"asset/{context}__one_cell__{angle}__normal__default.png"
                    path = out / rel
                    path.parent.mkdir(parents=True, exist_ok=True)
                    Image.new("RGB", (256, 240), (80, 80, 80)).save(path)
                    entries.append(
                        {
                            "asset_id": "asset",
                            "state": "default",
                            "context": context,
                            "distance": "one_cell",
                            "angle": angle,
                            "lighting": "normal",
                            "path": rel,
                            "success": True,
                        }
                    )
            review.generate_all_contact_sheets(out, manifest, entries)
            with Image.open(out / "contact-sheets/tier_a_stateful.png") as sheet:
                self.assertEqual(sheet.size[0], 4 * 256)
                self.assertEqual(sheet.size[1], 240 + 30)

    def test_publish_evidence_copies_decision_artifacts_and_hashes(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            out, publish = root / "out", root / "publish"
            (out / "contact-sheets").mkdir(parents=True)
            (out / "smoke").mkdir(parents=True)
            (out / "run.json").write_text("{}", encoding="utf-8")
            (out / "index.json").write_text("[]", encoding="utf-8")
            Image.new("RGB", (4, 4), "gray").save(out / "contact-sheets/tier_a_stateful.png")
            Image.new("RGB", (4, 4), "gray").save(out / "smoke/event_model__model.png")
            artifact_manifest = review.publish_evidence(out, publish)
            self.assertTrue((publish / "run.json").is_file())
            self.assertTrue((publish / "contact-sheets/tier_a_stateful.png").is_file())
            self.assertTrue((publish / "smoke/event_model__model.png").is_file())
            self.assertTrue((publish / "artifact-manifest.json").is_file())
            self.assertGreaterEqual(len(artifact_manifest["files"]), 4)


if __name__ == "__main__":
    unittest.main()
