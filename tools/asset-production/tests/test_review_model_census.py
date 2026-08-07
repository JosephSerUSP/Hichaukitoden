# tools/asset-production/tests/test_review_model_census.py
import unittest
import json
import tempfile
import os

from review_model_census import process_captures, merge_review_csv

class ReviewModelCensusTests(unittest.TestCase):
    def test_missing_frame_detection(self):
        manifest = {
            "assets": [
                {
                    "asset_id": "test_asset",
                    "display_name": "Test Asset",
                    "placement_adapter": "floor_feature_model",
                    "states": [
                        {
                            "state": "default",
                            "contexts": ["neutral"],
                            "distances": ["one_cell"],
                            "angles": ["frontal"],
                            "lighting": ["normal"]
                        }
                    ]
                }
            ]
        }
        index_entries = [] # Empty captures
        missing, duplicates = process_captures(manifest, index_entries)
        self.assertEqual(len(missing), 1)
        self.assertEqual(missing[0], "test_asset/neutral__one_cell__frontal__normal__default.png")
        self.assertEqual(len(duplicates), 0)

    def test_non_destructive_csv_merging(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            csv_path = os.path.join(tmpdir, "review.csv")
            with open(csv_path, "w") as f:
                f.write("asset_id,recognition,spatialFunction,styleIntegration,materialHierarchy,screenEconomy,emotionalFunction,verdict,notes\n")
                f.write("census_chest_arched_reliquary_chest,5,4,4,5,4,4,promote_candidate,Great chest\n")

            manifest_assets = [
                {"asset_id": "census_chest_arched_reliquary_chest"},
                {"asset_id": "census_door_portcullis"}
            ]

            merge_review_csv(csv_path, manifest_assets)

            with open(csv_path, "r") as f:
                lines = f.readlines()
            self.assertEqual(len(lines), 3)
            self.assertIn("census_chest_arched_reliquary_chest,5,4,4,5,4,4,promote_candidate,Great chest", lines[1])
            self.assertIn("census_door_portcullis,,,,,,,,", lines[2])

if __name__ == "__main__":
    unittest.main()
