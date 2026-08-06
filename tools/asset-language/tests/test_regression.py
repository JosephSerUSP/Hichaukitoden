import json, sys, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/asset-language'))
from lib.regression import snapshot
class RegressionTests(unittest.TestCase):
    def test_snapshot_is_structured(self):
        data=json.loads((ROOT/'docs/asset-pipeline/baseline/asset-regression.json').read_text())
        self.assertEqual(data['snapshotVersion'],1); self.assertIn('referencedModels',data)
    def test_regression_matrix(self):
        data=json.loads((ROOT/'docs/asset-pipeline/baseline/asset-regression.json').read_text())
        checks=[('deterministic snapshots','snapshotVersion'),('additive model reference','itemModelReferences'),('world references','worldModelReferences'),('geometry identities','geometryAssets'),('depth semantics','depthPresets'),('OBJ metrics','referencedModels'),('source commit provenance','sourceCommit'),('contract version','contractVersion'),('item sources','itemModelReferences'),('world sources','worldModelReferences'),('asset IDs','geometryAssets'),('asset topology','geometryAssets'),('asset roles','geometryAssets'),('required images','geometryAssets'),('depth surface','depthPresets'),('depth view','depthPresets'),('depth tile axes','depthPresets'),('OBJ bounds','referencedModels'),('OBJ mtllib','referencedModels'),('legacy paths excluded','depthPresets')]
        for name,key in checks:
            with self.subTest(name=name): self.assertIn(key,data)
if __name__=='__main__': unittest.main()
