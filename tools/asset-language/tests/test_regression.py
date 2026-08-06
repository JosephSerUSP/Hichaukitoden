import json, sys, tempfile, unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/asset-language'))
from lib.regression import snapshot, compare

class MiniRepo:
    def __enter__(self):
        self.tmp=tempfile.TemporaryDirectory(); self.root=Path(self.tmp.name)
        for p in ('data','assets/models','assets/geometry/test_asset','assets/geometry/1_blender_depth_maps'): (self.root/p).mkdir(parents=True,exist_ok=True)
        (self.root/'data/items.json').write_text(json.dumps({'items':[{'model':'assets/models/test_model.obj'}]}))
        (self.root/'data/tilesets.json').write_text(json.dumps({'tilesets':[{'features':[{'model':'assets/models/test_model.obj'}]}]}))
        (self.root/'assets/models/test_model.obj').write_text('mtllib test_model.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nvt 0 0\nvt 1 0\nvt 0 1\nvn 0 0 1\nusemtl test\nf 1/1/1 2/2/1 3/3/1\n')
        (self.root/'assets/models/test_model.mtl').write_text('newmtl test\nKd 1 1 1\n')
        (self.root/'assets/geometry/test_asset/asset.json').write_text(json.dumps({'id':'test_asset','topology':'plane','role':'surfaceFixture'}))
        for n in ('albedo.png','height.png'): Image.new('RGBA',(2,2),(1,2,3,255)).save(self.root/'assets/geometry/test_asset'/n)
        (self.root/'assets/geometry/1_blender_depth_maps/manifest.json').write_text(json.dumps({'maps':[{'preset':'test','surface':'wall','view':'above','tileAxes':'x','size':2,'wrapOk':True,'path':'C:/legacy','blend':'C:/legacy.blend'}]}))
        return self.root
    def __exit__(self,*a): self.tmp.cleanup()

class RegressionMutationTests(unittest.TestCase):
    def baseline(self):
        self.fixture=MiniRepo(); self.repo=self.fixture.__enter__(); self.base=snapshot(self.repo)
    def tearDown(self):
        if hasattr(self,'fixture'): self.fixture.__exit__(None,None,None)
    def test_unchanged_repository_passes(self): self.baseline(); self.assertEqual(compare(self.repo,self.base),[])
    def test_two_snapshots_equal(self): self.baseline(); self.assertEqual(snapshot(self.repo),snapshot(self.repo))
    def test_serialized_snapshots_are_byte_deterministic(self):
        self.baseline(); self.assertEqual(json.dumps(snapshot(self.repo),sort_keys=True,separators=(',',':')),json.dumps(snapshot(self.repo),sort_keys=True,separators=(',',':')))
    def test_source_commit_does_not_affect_comparison(self): self.baseline(); changed=dict(self.base,sourceCommit='other'); self.assertEqual(compare(self.repo,changed),[])
    def test_additive_model_reference_passes(self): self.baseline(); (self.repo/'data/items.json').write_text(json.dumps({'items':[{'model':'assets/models/test_model.obj'},{'model':'assets/models/test_model.obj'}]})); self.assertEqual(compare(self.repo,self.base),[])
    def test_additive_geometry_asset_passes(self): self.baseline(); p=self.repo/'assets/geometry/extra'; p.mkdir(); (p/'asset.json').write_text(json.dumps({'id':'extra','topology':'plane','role':'surfaceFixture'})); Image.new('RGBA',(2,2),(1,1,1,255)).save(p/'albedo.png'); Image.new('RGBA',(2,2),(1,1,1,255)).save(p/'height.png'); self.assertEqual(compare(self.repo,self.base),[])
    def test_additive_depth_preset_passes(self): self.baseline(); p=self.repo/'assets/geometry/1_blender_depth_maps/manifest.json'; d=json.loads(p.read_text()); d['maps'].append({'preset':'extra','surface':'floor','view':'above','tileAxes':'xy','size':2,'wrapOk':True}); p.write_text(json.dumps(d)); self.assertEqual(compare(self.repo,self.base),[])
    def test_missing_baseline_reference_location_fails(self): self.baseline(); (self.repo/'data/items.json').write_text(json.dumps({'items':[]})); self.assertTrue(compare(self.repo,self.base))
    def test_changed_model_path_fails(self): self.baseline(); (self.repo/'data/items.json').write_text(json.dumps({'items':[{'model':'assets/models/other.obj'}]})); self.assertTrue(compare(self.repo,self.base))
    def test_unresolved_current_model_reference_fails(self): self.baseline(); (self.repo/'data/items.json').write_text(json.dumps({'items':[{'model':'assets/models/test_model.obj'},{'model':'assets/models/missing.obj'}]})); self.assertTrue(compare(self.repo,self.base))
    def test_missing_referenced_obj_fails(self): self.baseline(); (self.repo/'assets/models/test_model.obj').unlink(); self.assertTrue(compare(self.repo,self.base))
    def test_deleting_baseline_obj_fails(self): self.baseline(); (self.repo/'assets/models/test_model.obj').unlink(); self.assertTrue(compare(self.repo,self.base))
    def test_changed_obj_metrics_fail(self): self.baseline(); (self.repo/'assets/models/test_model.obj').write_text('mtllib test_model.mtl\nv 0 0 0\nv 2 0 0\nv 0 1 0\nusemtl test\nf 1 2 3\n'); self.assertTrue(compare(self.repo,self.base))
    def test_changed_obj_vertex_count_fails(self): self.baseline(); p=self.repo/'assets/models/test_model.obj'; p.write_text(p.read_text().replace('v 0 1 0','v 0 1 0\nv 0 0 1')); self.assertTrue(compare(self.repo,self.base))
    def test_changed_obj_face_count_fails(self): self.baseline(); p=self.repo/'assets/models/test_model.obj'; p.write_text(p.read_text().replace('f 1/1/1 2/2/1 3/3/1','f 1/1/1 3/3/1 2/2/1\nf 1/1/1 2/2/1 3/3/1')); self.assertTrue(compare(self.repo,self.base))
    def test_changed_obj_bounds_fail(self): self.baseline(); p=self.repo/'assets/models/test_model.obj'; p.write_text(p.read_text().replace('v 1 0 0','v 9 0 0')); self.assertTrue(compare(self.repo,self.base))
    def test_changed_mtllib_fails(self): self.baseline(); p=self.repo/'assets/models/test_model.obj'; p.write_text(p.read_text().replace('test_model.mtl','other.mtl')); self.assertTrue(compare(self.repo,self.base))
    def test_missing_mtl_fails(self): self.baseline(); (self.repo/'assets/models/test_model.mtl').unlink(); self.assertTrue(compare(self.repo,self.base))
    def test_malformed_mtllib_diagnostic(self): self.baseline(); p=self.repo/'assets/models/test_model.obj'; p.write_text(p.read_text().replace('mtllib test_model.mtl','mtllib')); self.assertTrue(compare(self.repo,self.base))
    def test_malformed_vertex_diagnostic(self): self.baseline(); p=self.repo/'assets/models/test_model.obj'; p.write_text(p.read_text().replace('v 1 0 0','v nope 0 0')); self.assertTrue(compare(self.repo,self.base))
    def test_missing_baseline_geometry_fails(self): self.baseline(); import shutil; shutil.rmtree(self.repo/'assets/geometry/test_asset'); self.assertTrue(compare(self.repo,self.base))
    def test_malformed_geometry_json_diagnostic(self): self.baseline(); (self.repo/'assets/geometry/test_asset/asset.json').write_text('{'); self.assertTrue(compare(self.repo,self.base))
    def test_changed_geometry_topology_fails(self): self.baseline(); p=self.repo/'assets/geometry/test_asset/asset.json'; p.write_text(json.dumps({'id':'test_asset','topology':'shell','role':'surfaceFixture'})); self.assertTrue(compare(self.repo,self.base))
    def test_changed_geometry_id_fails(self): self.baseline(); p=self.repo/'assets/geometry/test_asset/asset.json'; p.write_text(json.dumps({'id':'changed','topology':'plane','role':'surfaceFixture'})); self.assertTrue(compare(self.repo,self.base))
    def test_changed_geometry_role_fails(self): self.baseline(); p=self.repo/'assets/geometry/test_asset/asset.json'; p.write_text(json.dumps({'id':'test_asset','topology':'plane','role':'objectFixture'})); self.assertTrue(compare(self.repo,self.base))
    def test_missing_albedo_fails(self): self.baseline(); (self.repo/'assets/geometry/test_asset/albedo.png').unlink(); self.assertTrue(compare(self.repo,self.base))
    def test_missing_height_fails(self): self.baseline(); (self.repo/'assets/geometry/test_asset/height.png').unlink(); self.assertTrue(compare(self.repo,self.base))
    def test_changed_image_dimensions_fail(self): self.baseline(); Image.new('RGBA',(3,2)).save(self.repo/'assets/geometry/test_asset/albedo.png'); self.assertTrue(compare(self.repo,self.base))
    def test_changed_image_height_fails(self): self.baseline(); Image.new('RGBA',(2,3)).save(self.repo/'assets/geometry/test_asset/albedo.png'); self.assertTrue(compare(self.repo,self.base))
    def test_changed_image_mode_fails(self): self.baseline(); Image.new('RGB',(2,2)).save(self.repo/'assets/geometry/test_asset/albedo.png'); self.assertTrue(compare(self.repo,self.base))
    def test_unreadable_image_diagnostic(self): self.baseline(); (self.repo/'assets/geometry/test_asset/albedo.png').write_bytes(b'not an image'); self.assertTrue(compare(self.repo,self.base))
    def test_missing_baseline_depth_preset_fails(self): self.baseline(); (self.repo/'assets/geometry/1_blender_depth_maps/manifest.json').write_text(json.dumps({'maps':[]})); self.assertTrue(compare(self.repo,self.base))
    def test_changed_depth_semantics_fail(self): self.baseline(); p=self.repo/'assets/geometry/1_blender_depth_maps/manifest.json'; d=json.loads(p.read_text()); d['maps'][0]['view']='below'; p.write_text(json.dumps(d)); self.assertTrue(compare(self.repo,self.base))
    def test_changed_depth_surface_fails(self): self.baseline(); p=self.repo/'assets/geometry/1_blender_depth_maps/manifest.json'; d=json.loads(p.read_text()); d['maps'][0]['surface']='floor'; p.write_text(json.dumps(d)); self.assertTrue(compare(self.repo,self.base))
    def test_changed_depth_tile_axes_fails(self): self.baseline(); p=self.repo/'assets/geometry/1_blender_depth_maps/manifest.json'; d=json.loads(p.read_text()); d['maps'][0]['tileAxes']='y'; p.write_text(json.dumps(d)); self.assertTrue(compare(self.repo,self.base))
    def test_changed_depth_size_fails(self): self.baseline(); p=self.repo/'assets/geometry/1_blender_depth_maps/manifest.json'; d=json.loads(p.read_text()); d['maps'][0]['size']=3; p.write_text(json.dumps(d)); self.assertTrue(compare(self.repo,self.base))
    def test_baseline_nonwrapping_depth_fails(self): self.baseline(); p=self.repo/'assets/geometry/1_blender_depth_maps/manifest.json'; d=json.loads(p.read_text()); d['maps'][0]['wrapOk']=False; p.write_text(json.dumps(d)); self.assertTrue(compare(self.repo,self.base))
    def test_new_nonwrapping_depth_preset_fails(self): self.baseline(); p=self.repo/'assets/geometry/1_blender_depth_maps/manifest.json'; d=json.loads(p.read_text()); d['maps'].append({'preset':'bad','surface':'wall','view':'above','tileAxes':'x','size':2,'wrapOk':False}); p.write_text(json.dumps(d)); self.assertTrue(compare(self.repo,self.base))
    def test_malformed_depth_preset_diagnostic(self): self.baseline(); p=self.repo/'assets/geometry/1_blender_depth_maps/manifest.json'; p.write_text(json.dumps({'maps':['bad']})); self.assertTrue(compare(self.repo,self.base))
    def test_legacy_absolute_path_and_blend_ignored(self): self.baseline(); p=self.repo/'assets/geometry/1_blender_depth_maps/manifest.json'; d=json.loads(p.read_text()); d['maps'][0]['path']='D:/changed'; d['maps'][0]['blend']='D:/changed.blend'; p.write_text(json.dumps(d)); self.assertEqual(compare(self.repo,self.base),[])
if __name__=='__main__': unittest.main()
