import json, os, sys, tempfile, unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
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
    def test_temporary_run_resolution_matrix(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            valid=root/'valid'; valid.mkdir()
            (valid/'manifest.json').write_text(json.dumps({'class':'x','name':'valid','variants':[]}))
            legacy=root/'legacy'; legacy.mkdir()
            (legacy/'manifest.json').write_text(json.dumps({'class':'x','name':'legacy','variants':[]}))
            ignored=root/'patterns'; ignored.mkdir()
            (ignored/'manifest.json').write_text(json.dumps({'manifestKind':'height_pattern_set','manifestVersion':1,'patterns':[]}))
            runs, ignored_count=staging.scan_runs(root)
            self.assertEqual({name for name,_ in runs},{'legacy','valid'}); self.assertEqual(ignored_count,1)
            self.assertEqual({name for name,_ in staging.list_runs(root)},{'legacy','valid'})
            os.utime(valid,(100,100)); os.utime(legacy,(200,200)); self.assertEqual(Path(staging.resolve_run(root,'latest')).name,'legacy')
            newer= root/'newer-pattern'; newer.mkdir(); (newer/'manifest.json').write_text(json.dumps({'manifestKind':'height_pattern_set','manifestVersion':1})); os.utime(newer,(300,300)); self.assertEqual(Path(staging.resolve_run(root,'latest')).name,'legacy')
            with self.assertRaisesRegex(RuntimeError,'non-run manifest'):
                staging.resolve_run(root, str(ignored))
            invalid=root/'invalid'; invalid.mkdir(); (invalid/'manifest.json').write_text(json.dumps({'manifestKind':'asset_gen_run','manifestVersion':2,'class':'x','name':'n','variants':[]}))
            with self.assertRaisesRegex(RuntimeError,'invalid run manifest'):
                staging.resolve_run(root, str(invalid))
            (invalid/'manifest.json').unlink(); invalid.rmdir()
            missing_manifest=root/'no-manifest'; missing_manifest.mkdir()
            with self.assertRaisesRegex(FileNotFoundError,'run manifest missing'):
                staging.resolve_run(root, str(missing_manifest))
            with self.assertRaisesRegex(FileNotFoundError,"no staged run"):
                staging.resolve_run(root, 'does-not-exist')
            malformed=root/'malformed'; malformed.mkdir(); (malformed/'manifest.json').write_text('{')
            with self.assertRaises(RuntimeError) as error:
                staging.scan_runs(root)
            self.assertIn(str(malformed/'manifest.json'),str(error.exception))
    def test_legacy_reprocess_is_upgraded(self):
        sys.path.insert(0,str(ROOT/'tools/asset-gen'))
        import gen
        with tempfile.TemporaryDirectory() as d:
            run=Path(d)/'legacy'; run.mkdir()
            original={'class':'smallBattler','name':'test','options':{'fps':15},'keepMe':'yes','variants':[]}
            (run/'manifest.json').write_text(json.dumps(original)); (run/'raw-0.png').write_bytes(b'raw')
            written={}
            def finish(path,manifest):
                written.update(manifest); staging.write_manifest(path,manifest)
            args=SimpleNamespace(run=str(run))
            with patch.object(gen,'_config',return_value={}), patch.object(gen,'_staging_root',return_value=str(Path(d))), patch.object(gen.classes,'resolve',return_value={'dir':'assets','filename':'{name}.png'}), patch.object(gen.classes,'filename',return_value='test.png'), patch.object(gen,'_process_variant',return_value={'index':0,'file':'processed-0.png'}), patch.object(gen,'_finish',side_effect=finish):
                self.assertEqual(gen.cmd_reprocess(args),0)
            result=staging.read_run_manifest(str(run))
            self.assertEqual(result['keepMe'],'yes'); self.assertEqual(result['manifestKind'],'asset_gen_run'); self.assertEqual(result['manifestVersion'],1)
    def test_web_context_rejects_non_run_before_preview(self):
        sys.path.insert(0,str(ROOT/'tools/asset-gen'))
        import server
        with tempfile.TemporaryDirectory() as d:
            other=Path(d)/'patterns'; other.mkdir(); (other/'manifest.json').write_text(json.dumps({'manifestKind':'height_pattern_set','manifestVersion':1,'patterns':[]}))
            with self.assertRaisesRegex(RuntimeError,'non-run manifest'):
                server.validated_context_run(d,str(other))
if __name__=='__main__': unittest.main()
