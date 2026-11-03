import threading
import unittest
from board_link import BoardLink, BoardError
from protocol import decode_status, ISP
from app import create_app

class SaturationTests(unittest.TestCase):
    def test_version_and_readback(self):
        s=bytearray(44);s[0]=4;s[2]=10;s[43]=0x18
        d=decode_status(s)
        self.assertEqual(d['mode_name'],'TRACK')
        self.assertEqual(d['saturation'],8)
        self.assertTrue(d['saturation_override'])
        s[0]=3
        self.assertNotIn('saturation',decode_status(s))

    def test_command_gate_and_range(self):
        class Device:
            status={'protocol_version':4}
            isp_lock=threading.Lock()
            def request(self,*args):self.sent=args;return {'code':0}
        d=Device()
        for v in range(9):
            BoardLink.isp(d,'saturation',v)
            self.assertEqual(d.sent,(ISP,5,v,0))
        for v in (-1,9,True):
            with self.assertRaises(BoardError):BoardLink.isp(d,'saturation',v)
        d.status={'protocol_version':3}
        with self.assertRaises(BoardError):BoardLink.isp(d,'saturation',7)

    def test_normalized_http(self):
        class Device:
            def isp(self,n,v):self.last=(n,v);return {'code':0}
        d=Device();c=create_app(d).test_client()
        for p,v in [(0,0),(50,4),(75,6),(87.5,7),(100,8)]:
            result=c.post('/api/isp',json={'name':'saturation','normalized':p})
            self.assertEqual(result.status_code,200)
            self.assertEqual(d.last,('saturation',v))
