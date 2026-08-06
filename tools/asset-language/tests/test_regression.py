import json, sys, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/asset-language'))
from lib.regression import snapshot
class RegressionTests(unittest.TestCase):
    def test_snapshot_is_structured(self):
        data=json.loads((ROOT/'docs/asset-pipeline/baseline/asset-regression.json').read_text())
        self.assertEqual(data['snapshotVersion'],1); self.assertIn('referencedModels',data)
if __name__=='__main__': unittest.main()
