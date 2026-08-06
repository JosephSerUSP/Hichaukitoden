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
    def test_manifest_matrix(self):
        cases=[('explicit valid',{'manifestKind':'asset_gen_run','manifestVersion':1,'class':'x','name':'y','variants':[]},'run'),('missing version',{'manifestKind':'asset_gen_run','class':'x','name':'y','variants':[]},'invalid_run'),('unsupported version',{'manifestKind':'asset_gen_run','manifestVersion':2,'class':'x','name':'y','variants':[]},'invalid_run'),('empty class',{'manifestKind':'asset_gen_run','manifestVersion':1,'class':'','name':'y','variants':[]},'invalid_run'),('empty name',{'manifestKind':'asset_gen_run','manifestVersion':1,'class':'x','name':'','variants':[]},'invalid_run'),('legacy run',{'class':'x','name':'y','variants':[]},'run'),('explicit height pattern',{'manifestKind':'height_pattern_set','manifestVersion':1},'other'),('legacy height pattern',{'size':64,'seed':1,'patterns':[]},'other'),('unrelated',{'hello':'world'},'other'),('partial legacy',{'class':'x'},'invalid_run'),('nonobject',[], 'other'),('run version string',{'manifestKind':'asset_gen_run','manifestVersion':'1','class':'x','name':'y','variants':[]},'invalid_run'),('empty variants invalid type',{'manifestKind':'asset_gen_run','manifestVersion':1,'class':'x','name':'y','variants':{}},'invalid_run'),('other kind',{'manifestKind':'review','manifestVersion':1},'other'),('null',None,'other'),('legacy missing name',{'class':'x','variants':[]},'invalid_run'),('legacy missing class',{'name':'y','variants':[]},'invalid_run'),('legacy missing variants',{'class':'x','name':'y'},'invalid_run'),('valid multiple variants',{'class':'x','name':'y','variants':[1,2]},'run'),('explicit extra fields',{'manifestKind':'asset_gen_run','manifestVersion':1,'class':'x','name':'y','variants':[],'extra':1},'run')]
        for name,data,want in cases:
            with self.subTest(name=name): self.assertEqual(staging.classify_manifest(data)[0],want)
if __name__=='__main__': unittest.main()
