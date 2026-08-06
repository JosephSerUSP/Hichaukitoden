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
if __name__=='__main__': unittest.main()
