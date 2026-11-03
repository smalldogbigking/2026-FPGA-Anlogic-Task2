import unittest
import re
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from board_link import BoardLink,BoardError
from protocol import SET,decode_status
from server_info import identity,SOFTWARE_VERSION
from app import create_app

class Device:
    def __init__(self,version):self.status={'protocol_version':version};self.calls=[]
    def request(self,*args):self.calls.append(args);return {'code':0}
    def configure(self,*args):return BoardLink.configure(self,*args)

class VersionSyncTests(unittest.TestCase):
    def test_v5_sort_configuration_reaches_wire_command(self):
        d=Device(5);client=create_app(d).test_client()
        r=client.post('/api/config',json=dict(mode=13,beauty='auto',quality=0,fps=60))
        self.assertEqual(r.status_code,200);self.assertEqual(d.calls,[(SET,13,1,0)])

    def test_legacy_control_and_reject_unsupported_sort(self):
        for version in (3,4,5):
            d=Device(version);BoardLink.configure(d,10,'off',1,30)
            self.assertEqual(d.calls,[(SET,10,0,5)])
        for version in (3,4):
            with self.assertRaisesRegex(BoardError,'协议5'):BoardLink.configure(Device(version),13,'off',0,60)
        for version in (None,2,6):
            with self.assertRaises(BoardError):BoardLink.configure(Device(version),0,'off',0,60)

    def test_sort_bytes_are_not_a_face_box(self):
        raw=bytearray(44);raw[0]=5;raw[2]=13;raw[7]=6;raw[8]=15;raw[32]=1
        for slot,(kind,digit) in enumerate([(1,3),(2,4),(3,3),(4,5)]):raw[34+slot]=(kind<<3)|digit
        raw[38:42]=bytes([0x34,0x12,0x78,0x56]);s=decode_status(raw)
        self.assertFalse(s['face_valid']);self.assertEqual(s['face_box'],[0,0,0,0])
        self.assertEqual(s['sort_frame'],0x1234);self.assertEqual(s['sort_sequence'],0x5678)
        self.assertEqual([t['class'] for t in s['sort_labels']],[1,2,3,4])
        raw[7]=3;raw[34:42]=bytes([10,0,20,0,30,0,40,0]);s=decode_status(raw)
        self.assertTrue(s['face_valid']);self.assertEqual(s['face_box'],[10,20,30,40]);self.assertEqual(s['sort_labels'],[])

    def test_health_has_android_contract(self):
        health=create_app(object()).test_client().get('/api/health').json
        self.assertEqual(health['software_version'],'3.0.2');self.assertEqual(SOFTWARE_VERSION,'3.0.2')
        self.assertEqual(health['target_fpga_protocol'],5);self.assertIn(5,health['fpga_control_versions'])
        metadata=(Path(__file__).resolve().parents[1]/'pyproject.toml').read_text(encoding='utf-8')
        self.assertEqual(re.search(r'^version = "([^"]+)"',metadata,re.M).group(1),SOFTWARE_VERSION)
        self.assertIn('"compatibility"',metadata)

if __name__=='__main__':unittest.main()
