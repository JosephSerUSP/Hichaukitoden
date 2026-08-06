import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
BLENDER_TOOLS = ROOT / "tools" / "blender"
TOOLKIT = BLENDER_TOOLS / "second-rite-item-model-toolkit"
sys.path.insert(0, str(BLENDER_TOOLS))
import sync_asset_core


class AssetCoreHostTests(unittest.TestCase):
    def test_vendor_files_are_byte_identical(self):
        for source, target in sync_asset_core.expected_pairs():
            with self.subTest(target=target.name):
                self.assertEqual(source.read_bytes(), target.read_bytes())

    def test_sync_check_passes_and_does_not_write(self):
        before = {target: target.read_bytes() for _, target in sync_asset_core.expected_pairs()}
        result = subprocess.run(
            [sys.executable, str(BLENDER_TOOLS / "sync_asset_core.py"), "--check"],
            cwd=ROOT, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, {target: target.read_bytes() for _, target in sync_asset_core.expected_pairs()})

    def test_sync_check_detects_modified_temporary_vendor_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            vendor = Path(directory) / "vendor"
            pairs = []
            for source, target in sync_asset_core.expected_pairs():
                copy = vendor / target.name
                copy.parent.mkdir(parents=True, exist_ok=True)
                copy.write_bytes(source.read_bytes())
                pairs.append((source, copy))
            pairs[0][1].write_bytes(pairs[0][1].read_bytes() + b"\nchanged")
            self.assertTrue(sync_asset_core.check_pairs(pairs))

    def test_manifest_and_sha_list_include_vendor_files(self):
        manifest = json.loads((TOOLKIT / "TOOLCHAIN_MANIFEST.json").read_text(encoding="utf-8"))
        paths = {entry["path"] for entry in manifest["files"]}
        sha_paths = {
            line.split(maxsplit=1)[1].replace("\\", "/")
            for line in (TOOLKIT / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines()
            if line.strip()
        }
        for name in ("vendor/second_rite_asset_core.py", "vendor/contract.json", "vendor/materials.json"):
            self.assertIn(name, paths)
            self.assertIn(name, sha_paths)

    def test_manifest_hashes_and_lengths_are_current(self):
        manifest = json.loads((TOOLKIT / "TOOLCHAIN_MANIFEST.json").read_text(encoding="utf-8"))
        for entry in manifest["files"]:
            path = TOOLKIT / entry["path"]
            self.assertTrue(path.is_file(), entry["path"])
            data = path.read_bytes()
            self.assertEqual(entry["bytes"], len(data), entry["path"])
            self.assertEqual(entry["sha256"], hashlib.sha256(data).hexdigest(), entry["path"])

    def test_core_version_is_discoverable_without_bpy(self):
        source = (BLENDER_TOOLS / "second_rite_asset_core.py").read_text(encoding="utf-8")
        self.assertRegex(source, r"CORE_VERSION\s*=\s*1")

    def test_builder_scenes_and_exporter_use_shared_core(self):
        builder = (TOOLKIT / "build_expanded_item_library.py").read_text(encoding="utf-8")
        scenes = (ROOT / "tools/asset-gen/blender/scenes.py").read_text(encoding="utf-8")
        exporter = (TOOLKIT / "second_rite_item_exporter.py").read_text(encoding="utf-8")
        self.assertIn("import second_rite_asset_core as asset_core", builder)
        self.assertIn("import second_rite_asset_core as asset_core", scenes)
        self.assertIn("asset_core.export_asset_root", exporter)

    def test_migrated_infrastructure_is_not_reimplemented(self):
        builder = (TOOLKIT / "build_expanded_item_library.py").read_text(encoding="utf-8")
        scenes = (ROOT / "tools/asset-gen/blender/scenes.py").read_text(encoding="utf-8")
        exporter = (TOOLKIT / "second_rite_item_exporter.py").read_text(encoding="utf-8")
        for name in ("clear_scene", "ensure_collection", "move_to_collection", "make_material", "assign_material", "flat_shade", "add_bevel", "parent_local"):
            self.assertNotRegex(builder, rf"^def {name}\(", name)
        for name in ("_mesh_from_bmesh", "_rotation_matrix"):
            self.assertNotRegex(scenes, rf"^def {name}\(", name)
        for name in ("_duplicate_hierarchy", "_operator_kwargs", "_export_obj"):
            self.assertNotRegex(exporter, rf"^def {name}\(", name)

    def test_contract_and_material_loaders_work_on_host(self):
        import second_rite_asset_core as core
        self.assertEqual(core.CORE_VERSION, 1)
        self.assertEqual(core.load_contract()["contractVersion"], 1)
        self.assertEqual(len(core.load_material_registry()["materials"]), 12)
        self.assertEqual(core.material_definition("bone")["id"], "bone")

    def test_no_production_asset_path_is_test_output(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertFalse((Path(directory) / "assets").exists())
            self.assertIn("SECOND_RITE_OUT", (TOOLKIT / "build_expanded_item_library.py").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
