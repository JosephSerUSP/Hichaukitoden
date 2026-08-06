import ast
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
        def top_level_functions(source):
            tree = ast.parse(source)
            return {node.name for node in tree.body
                    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}

        for name in ("clear_scene", "ensure_collection", "move_to_collection", "make_material", "assign_material", "flat_shade", "add_bevel", "parent_local"):
            self.assertNotIn(name, top_level_functions(builder), name)
        for name in ("_mesh_from_bmesh", "_rotation_matrix"):
            self.assertNotIn(name, top_level_functions(scenes), name)
        for name in ("_duplicate_hierarchy", "_operator_kwargs", "_export_obj"):
            self.assertNotIn(name, top_level_functions(exporter), name)

    def test_contract_and_material_loaders_work_on_host(self):
        import second_rite_asset_core as core
        self.assertEqual(core.CORE_VERSION, 1)
        self.assertEqual(core.load_contract()["contractVersion"], 1)
        self.assertEqual(core.load_contract()["materialRegistry"]["version"], 1)
        self.assertEqual(core.load_material_registry()["version"], 1)
        self.assertEqual(len(core.load_material_registry()["materials"]), 12)
        self.assertEqual(core.material_definition("bone")["id"], "bone")

    def test_material_registry_version_agreement(self):
        import second_rite_asset_core as core
        contract = json.loads((ROOT / "tools/asset-language/contract.json").read_text(encoding="utf-8"))
        registry = json.loads((ROOT / "tools/asset-language/materials.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            contract_path = directory / "contract.json"
            registry_path = directory / "materials.json"
            contract_path.write_text(json.dumps(contract), encoding="utf-8")
            registry_path.write_text(json.dumps(registry), encoding="utf-8")
            self.assertEqual(
                core.load_material_registry(registry_path, contract_path)["version"], 1)

    def test_material_registry_rejects_unsupported_version(self):
        import second_rite_asset_core as core
        registry = {"version": 2, "materials": []}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "materials.json"
            path.write_text(json.dumps(registry), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "unsupported material registry version"):
                core.load_material_registry(path)

    def test_material_registry_rejects_contract_mismatch(self):
        import second_rite_asset_core as core
        contract = json.loads((ROOT / "tools/asset-language/contract.json").read_text(encoding="utf-8"))
        contract["materialRegistry"]["version"] = 2
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "contract.json"
            path.write_text(json.dumps(contract), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "disagrees with contract"):
                core.load_material_registry(contract_path=path)

    def test_material_registry_rejects_malformed_json(self):
        import second_rite_asset_core as core
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "materials.json"
            path.write_text("{", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "malformed JSON"):
                core.load_material_registry(path)

    def test_exporter_handles_missing_file(self):
        exporter = (TOOLKIT / "second_rite_item_exporter.py").read_text(encoding="utf-8")
        self.assertIn('globals().get("__file__")', exporter)
        self.assertNotIn("Path(__file__)", exporter)
        self.assertIn("<Blender Text: second_rite_asset_core.py>", exporter)

    def test_calibration_has_exact_pixels_and_material_semantics(self):
        driver = (BLENDER_TOOLS / "check_blender_core.py").read_text(encoding="utf-8")
        self.assertIn("before_pixels != after_pixels", driver)
        self.assertNotIn("changed > 64", driver)
        self.assertNotIn("max delta", driver)
        self.assertIn("ordered usemtl", driver)
        self.assertIn("mtllib", driver)
        self.assertIn("Decimal", driver)
        self.assertIn("newmtl", driver)

    def test_standalone_core_origin_is_enforced(self):
        driver = (BLENDER_TOOLS / "check_blender_core.py").read_text(encoding="utf-8")
        self.assertIn("STANDALONE_CORE_ORIGIN", driver)
        self.assertIn("/ \"vendor\" / \"second_rite_asset_core.py\"", driver)

    def test_no_production_asset_path_is_test_output(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertFalse((Path(directory) / "assets").exists())
            self.assertIn("SECOND_RITE_OUT", (TOOLKIT / "build_expanded_item_library.py").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
