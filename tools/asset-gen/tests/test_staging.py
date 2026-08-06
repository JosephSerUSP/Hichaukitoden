import json, sys, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/asset-gen'))
from lib import staging
class StagingTests(unittest.TestCase):
    def test_classification(self):
        self.assertEqual(staging.classify_manifest({'class':'x','name':'y','variants':[]})[0],'run')
        self.assertEqual(staging.classify_manifest({'manifestKind':'height_pattern_set','size':64})[0],'other')
        self.assertEqual(staging.classify_manifest({'class':'x'})[0],'invalid_run')
    def test_scan_ignores_other(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'patterns'; p.mkdir(); (p/'manifest.json').write_text(json.dumps({'size':64,'patterns':[]}))
            self.assertEqual(staging.scan_runs(d),( [], 1))
if __name__=='__main__': unittest.main()
