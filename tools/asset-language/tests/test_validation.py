import json, sys, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/asset-language'))
from lib.validation import validate_contract, validate_record

class ValidationTests(unittest.TestCase):
    def test_contract_passes(self): self.assertEqual(validate_contract(), [])
    def test_complete_record_passes(self):
        r={"contractVersion":1,"id":"example","displayName":"Example","representation":"plane","role":"surface_fixture","authoringSpace":"depth_tile","placementFrame":"surface_domain","materials":["old_limestone"],"states":["inactive","active"],"defaultState":"inactive","variants":[],"sockets":[],"sources":{},"products":{},"provenance":{"generator":"test","generatorVersion":"1","sourceCommit":"x","command":"test","inputs":[],"outputs":[]}}
        self.assertEqual(validate_record(r),[])
    def test_bad_default_state(self):
        r={"contractVersion":1,"id":"example","displayName":"Example","representation":"plane","role":"surface_fixture","authoringSpace":"depth_tile","placementFrame":"surface_domain","materials":[],"states":["active"],"defaultState":"inactive","variants":[],"sockets":[],"sources":{},"products":{},"provenance":{}}
        self.assertTrue(any(d['code']=='default_state' for d in validate_record(r)))
    def test_required_failure_matrix(self):
        base={"contractVersion":1,"id":"example","displayName":"Example","representation":"plane","role":"surface_fixture","authoringSpace":"depth_tile","placementFrame":"surface_domain","materials":["old_limestone"],"states":["inactive"],"defaultState":"inactive","variants":[],"sockets":[],"sources":{},"products":{},"provenance":{"generator":"g","generatorVersion":"1","sourceCommit":"c","command":"x","inputs":[],"outputs":[]}}
        cases=[("invalid record ID",lambda r:r.update(id="Bad"),"invalid_id"),("missing required field",lambda r:r.pop("displayName"),"missing_field"),("wrong top-level type",lambda r:r.update(sources=[]),"object_type"),("empty display name",lambda r:r.update(displayName=""),"display_name"),("duplicate material",lambda r:r.update(materials=["old_limestone","old_limestone"]),"duplicate_id"),("duplicate state",lambda r:r.update(states=["inactive","inactive"]),"duplicate_id"),("duplicate variant",lambda r:r.update(variants=["v","v"]),"duplicate_id"),("state variant overlap",lambda r:r.update(variants=["inactive"]),"state_variant_overlap"),("unknown material",lambda r:r.update(materials=["missing"]),"unknown_material"),("invalid space frame",lambda r:r.update(placementFrame="item_viewport"),"space_frame"),("invalid item display",lambda r:r.update(role="item_display"),"role_compatibility"),("invalid structural opening",lambda r:r.update(role="structural_opening"),"role_compatibility"),("absolute path",lambda r:r.update(sources={"prompt":"/x"}),"invalid_path"),("backslash path",lambda r:r.update(sources={"prompt":"a\\b"}),"invalid_path"),("parent escape path",lambda r:r.update(sources={"prompt":"../x"}),"invalid_path"),("duplicate socket",lambda r:r.update(sockets=[{"id":"x","kind":"vfx","position":[0,0,0]},{"id":"x","kind":"vfx","position":[0,0,0]}]),"duplicate_socket"),("non-object socket",lambda r:r.update(sockets=["x"]),"socket_type"),("missing socket position",lambda r:r.update(sockets=[{"id":"x","kind":"vfx"}]),"vector"),("unknown socket state",lambda r:r.update(sockets=[{"id":"x","kind":"vfx","position":[0,0,0],"state":"missing"}]),"socket_state"),("non-normalized vector",lambda r:r.update(sockets=[{"id":"x","kind":"vfx","position":[0,0,0],"forward":[2,0,0]}]),"vector_normalization"),("zero vector",lambda r:r.update(sockets=[{"id":"x","kind":"vfx","position":[0,0,0],"forward":[0,0,0]}]),"vector_normalization"),("parallel vectors",lambda r:r.update(sockets=[{"id":"x","kind":"vfx","position":[0,0,0],"forward":[1,0,0],"up":[1,0,0]}]),"parallel_vectors"),("non-object metric product",lambda r:r.update(products={"heightMetric":"x"}),"invalid_path"),("missing metric range",lambda r:r.update(products={"heightMetric":{"path":"h.png"}}),"range_cells"),("non-positive metric range",lambda r:r.update(products={"heightMetric":{"path":"h.png","rangeCells":0}}),"range_cells"),("metric guide collision",lambda r:r.update(products={"heightMetric":{"path":"h.png","rangeCells":1},"depthGuide":"h.png"}),"path_collision"),("guide legacy collision",lambda r:r.update(products={"depthGuide":"h.png","legacyHeight":"h.png"}),"path_collision"),("malformed SHA-256",lambda r:r.update(provenance={**base["provenance"],"inputs":[{"path":"x","sha256":"bad"}]}),"sha256"),("duplicate input",lambda r:r.update(provenance={**base["provenance"],"inputs":[{"path":"x"},{"path":"x"}]}),"duplicate_provenance_path"),("duplicate output",lambda r:r.update(provenance={**base["provenance"],"outputs":[{"path":"x"},{"path":"x"}]}),"duplicate_provenance_path"),("input output collision",lambda r:r.update(provenance={**base["provenance"],"inputs":[{"path":"x"}],"outputs":[{"path":"x"}]}),"duplicate_provenance_path"),("source output collision",lambda r:r.update(sources={"prompt":"x"},provenance={**base["provenance"],"outputs":[{"path":"x"}]}),"source_output_collision"),("missing provenance identity",lambda r:r.update(provenance={}),"provenance_field"),("wrong provenance collection type",lambda r:r.update(provenance={**base["provenance"],"inputs":{}}),"provenance_type")]
        for name, mutate, code in cases:
            with self.subTest(name=name):
                r=json.loads(json.dumps(base)); mutate(r)
                self.assertTrue(any(d['code']==code for d in validate_record(r)), name)
    def test_diagnostics_are_deterministically_ordered(self):
        r={"contractVersion":1,"id":"Bad","displayName":"","representation":"plane","role":"surface_fixture","authoringSpace":"depth_tile","placementFrame":"item_viewport","materials":["x","x"],"states":[],"defaultState":"x","variants":[],"sockets":[],"sources":[],"products":[],"provenance":[]}
        a=validate_record(r); b=validate_record(r); self.assertEqual(a,b); self.assertEqual(a,sorted(a,key=lambda d:(d['path'],d['field'],d['code'],d['message'])))
    def test_schema_agreement_mutations(self):
        schema=json.loads((ROOT/'tools/asset-language/asset-record.schema.json').read_text())
        cases=[
            ("required fields",lambda s:s["required"].pop(),"schema_required"),
            ("representation enum",lambda s:s["properties"]["representation"]["enum"].pop(),"schema_enum"),
            ("role enum",lambda s:s["properties"]["role"]["enum"].pop(),"schema_enum"),
            ("authoring space enum",lambda s:s["properties"]["authoringSpace"]["enum"].pop(),"schema_enum"),
            ("placement frame enum",lambda s:s["properties"]["placementFrame"]["enum"].pop(),"schema_enum"),
            ("socket enum",lambda s:s["properties"]["sockets"]["items"]["properties"]["kind"]["enum"].pop(),"schema_socket_enum"),
            ("id pattern",lambda s:s["properties"]["id"].update(pattern=".*"),"schema_id_pattern"),
            ("unique identity arrays",lambda s:s["properties"]["states"].update(uniqueItems=False),"schema_unique"),
            ("source properties",lambda s:s["properties"]["sources"]["properties"].pop("prompt"),"schema_sources"),
            ("product properties",lambda s:s["properties"]["products"]["properties"].pop("albedo"),"schema_products"),
            ("metric required fields",lambda s:s["properties"]["products"]["properties"]["heightMetric"]["required"].pop(),"schema_metric_height"),
            ("provenance required fields",lambda s:s["properties"]["provenance"]["required"].pop(),"schema_provenance"),
            ("sha pattern",lambda s:s["$defs"]["provenanceFile"]["properties"]["sha256"].update(pattern=".*"),"schema_sha256"),
            ("repository path",lambda s:s["$defs"]["repositoryPath"].update(pattern=".*"),"schema_repository_path"),
        ]
        for name,mutate,code in cases:
            with self.subTest(name=name):
                candidate=json.loads(json.dumps(schema)); mutate(candidate)
                self.assertTrue(any(d["code"]==code for d in validate_contract(schema_data=candidate)), name)
    def test_contract_and_material_constants(self):
        contract=json.loads((ROOT/'tools/asset-language/contract.json').read_text())
        materials=json.loads((ROOT/'tools/asset-language/materials.json').read_text())
        cases=[
            ("depth neutral",lambda c:c["depthProducts"]["height_metric"].update(neutral=1),contract,materials,"depth_contract"),
            ("coordinate mapping",lambda c:c["coordinateSystems"]["objToEngine"].update(formula="wrong"),contract,materials,"coordinate_contract"),
            ("reserved states",lambda c:c["states"].pop(),contract,materials,"vocabulary_mismatch"),
            ("exact material identity",lambda m:m["materials"].__setitem__(0,{**m["materials"][0],"id":"different_seed"}),contract,materials,"material_identity"),
            ("opacity mode",lambda m:m["materials"][0].update(opacityMode="unsupported"),contract,materials,"material_opacity"),
            ("generation tags",lambda m:m["materials"][0].update(generationTags=[]),contract,materials,"material_tags"),
            ("legacy MTL",lambda m:m["materials"][0].update(legacyMtl={"kd":[2,0,0]}),contract,materials,"material_mtl"),
        ]
        for name,mutate,contract_base,materials_base,code in cases:
            with self.subTest(name=name):
                c=json.loads(json.dumps(contract_base)); m=json.loads(json.dumps(materials_base))
                if "material" in name or name in ("opacity mode","generation tags","legacy MTL"): mutate(m)
                else: mutate(c)
                self.assertTrue(any(d["code"]==code for d in validate_contract(contract_data=c,materials_data=m)), name)
    def test_schema_product_and_provenance_types(self):
        base={"contractVersion":1,"id":"example","displayName":"Example","representation":"plane","role":"surface_fixture","authoringSpace":"depth_tile","placementFrame":"surface_domain","materials":[],"states":["inactive"],"defaultState":"inactive","variants":[],"sockets":[],"sources":{},"products":{"albedo":7},"provenance":{"generator":"g","generatorVersion":"1","sourceCommit":"c","command":"x","inputs":[],"outputs":[]}}
        self.assertTrue(any(d["code"]=="invalid_path" for d in validate_record(base)))
        base["products"]={}; base["provenance"]["inputs"]=[]; base["provenance"]["outputs"]=[{"path":"x"}]
        base["sources"]={"prompt":"x"}; self.assertTrue(any(d["code"]=="source_output_collision" for d in validate_record(base)))
if __name__=='__main__': unittest.main()
