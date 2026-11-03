import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app import create_app
from board_link import BoardLink
from protocol import OUTPUTS, ISP, QUERY
import threading

class StubBoard:
    def __init__(self): self.calls=[]
    def snapshot(self): return {'status':{'wb_r':64,'wb_b':96,'exposure':4,'gain':80}}
    def ports(self): return []
    def isp(self,name,value): self.calls.append(('isp',name,value));return {'code':0}
    def outputs(self,show,led,alarm): self.calls.append(('outputs',show,led,alarm));return {'code':0}

class SoftwareTests(unittest.TestCase):
    def setUp(self): self.board=StubBoard();self.client=create_app(self.board).test_client()
    def test_no_login_needed(self):
        response=self.client.get('/')
        self.assertEqual(response.status_code,200)
        response.close()
        self.assertEqual(self.client.get('/api/ports').status_code,200)
        s=self.client.get('/api/status').json
        self.assertEqual(s['isp_normalized']['wb_b'],100)
        self.assertEqual(s['isp_normalized']['exposure'],0)
        self.assertEqual(self.client.post('/api/login',json={}).status_code,404)
    def test_full_range_mapping(self):
        limits={'wb_r':(40,96),'wb_b':(40,96),'exposure':(4,1991),'gain':(16,80)}
        for name,(lo,hi) in limits.items():
            for percentage,expected in [(0,lo),(100,hi),(50,round((lo+hi)/2))]:
                response=self.client.post('/api/isp',json={'name':name,'normalized':percentage})
                self.assertEqual(response.status_code,200)
                self.assertEqual(response.json['raw_value'],expected)
                self.assertEqual(self.board.calls[-1],('isp',name,expected))
        for invalid in [-1,101,True,'50',None]:
            self.assertEqual(self.client.post('/api/isp',json={'name':'gain','normalized':invalid}).status_code,400)
    def test_alarm_command_preserves_outputs(self):
        self.assertEqual(self.client.post('/api/outputs',json={'show':True,'led':False,'alarm':True}).status_code,200)
        self.assertEqual(self.board.calls[-1],('outputs',True,False,True))
        # Exercise production protocol mapping without opening a real serial port.
        calls=[]
        class Sink:
            def request(self,*args):calls.append(args);return {'code':0}
        BoardLink.outputs(Sink(),True,False,True)
        BoardLink.outputs(Sink(),True,False,False)
        self.assertEqual(calls,[(OUTPUTS,5),(OUTPUTS,1)])

    def test_exposure_gain_independence(self):
        # Emulate the production shared shadow registers, initially 1991/48,
        # while actual AUTO is 900/80. First edit must retain the other axis.
        class Device:
            def __init__(self):
                self.lock=threading.RLock();self.isp_lock=threading.Lock()
                self.status={'exposure':900,'gain':80};self.shadow={'exposure':1991,'gain':48};self.calls=[]
            def request(self,cmd,*args):
                self.calls.append((cmd,*args))
                if cmd==ISP:
                    code,lo,hi=args
                    self.shadow[{3:'exposure',4:'gain'}[code]]=lo+(hi<<8)
                    self.status=dict(self.shadow)
                return {'code':0}
        device=Device()
        BoardLink.isp(device,'exposure',1991)
        self.assertEqual(device.status,{'exposure':1991,'gain':80})
        self.assertEqual(device.calls[0],(QUERY,))
        device=Device()
        BoardLink.isp(device,'gain',64)
        self.assertEqual(device.status,{'exposure':900,'gain':64})

if __name__=='__main__': unittest.main()
