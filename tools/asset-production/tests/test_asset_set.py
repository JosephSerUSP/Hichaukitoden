from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "tools" / "asset-production"))

import asset_set  # noqa: E402


class AssetSetTests(unittest.TestCase):
    def test_first_stratum_set_is_valid_and_coherent(self):
        data = asset_set.load_asset_set(root=ROOT, check_files=True)
        self.assertEqual(data["id"], "first_stratum")
        self.assertEqual(len(data["assets"]), 7)
        chest = asset_set.get_asset(data, "first_stratum_treasure_chest", kind="world_prop")
        self.assertEqual(chest["states"], ["closed", "open"])
        self.assertEqual(chest["defaultState"], "closed")
        self.assertEqual(set(chest["products"]["states"]), {"closed", "open"})

    def test_surface_command_resolves_existing_generator(self):
        data = asset_set.load_asset_set(root=ROOT, check_files=True)
        floor = asset_set.get_asset(data, "first_stratum_floor_broken_flagstones", kind="surface")
        command = asset_set.surface_generate_command(
            floor, root=ROOT,
            overrides={"variants": 2, "seed": 104, "loras": ["JoStyle:0.7"]},
            python_executable="python",
        )
        self.assertEqual(command[:4], ["python", "tools/asset-gen/gen.py", "generate", "texturePiece"])
        self.assertIn("--height", command)
        self.assertIn("--depth-weight", command)
        self.assertEqual(command[command.index("--variants") + 1], "2")
        self.assertEqual(command[-2:], ["--lora", "JoStyle:0.7"])

    def test_run_annotation_preserves_existing_manifest(self):
        data = asset_set.load_asset_set(root=ROOT, check_files=True)
        wall = asset_set.get_asset(data, "first_stratum_wall_ritual_pilasters", kind="surface")
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            manifest = {"manifestKind": "asset_gen_run", "manifestVersion": 1,
                        "name": "existing", "variants": [{"index": 1}]}
            (run / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            record = asset_set.annotate_run_manifest(
                run, asset_set=data, asset=wall, root=ROOT
            )
            updated = json.loads((run / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(updated["name"], "existing")
            self.assertEqual(updated["variants"], [{"index": 1}])
            self.assertEqual(record["assetId"], wall["id"])
            self.assertEqual(len(record["depthGuide"]["sha256"]), 64)
            self.assertEqual(updated["productionRecord"], record)

    def test_repository_path_rejects_escape(self):
        with self.assertRaises(asset_set.AssetSetError):
            asset_set.repository_path("../outside", root=ROOT)


if __name__ == "__main__":
    unittest.main()
