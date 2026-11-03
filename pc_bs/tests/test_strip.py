import sys,unittest,struct,io
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from protocol import FrameAssembler,PacketParser,decode_status,VIDEO,reply
from PIL import Image

class StripTests(unittest.TestCase):
    def status(self):
        s=bytearray(44);s[0]=3;s[1]=15;s[2]=10;s[3]=3
        return bytes(s)
    def strips(self,w,h,counter=123):
        for y in range(0,h,8):
            n=min(8,h-y)
            pixels=bytes((x+(y+row)*3)%256 for row in range(n) for x in range(w))
            yield struct.pack('<HHHB',counter,w,h,2)+self.status()+struct.pack('<HB',y,n)+pixels
    def test_complete_both_sizes_and_fragmented_crc(self):
        for w,h in [(160,90),(320,180)]:
            assembler=FrameAssembler();parser=PacketParser();complete=[]
            wire=b''.join(reply(VIDEO,7,p) for p in self.strips(w,h))
            for k in range(0,len(wire),137):
                for kind,seq,p in parser.feed(wire[k:k+137]):
                    result=assembler.feed(seq,p)
                    if result:complete.append(result)
            self.assertEqual(len(complete),1);png,info=complete[0]
            self.assertEqual(Image.open(io.BytesIO(png)).size,(w,h))
            self.assertEqual(info['status']['mode_name'],'TRACK')
            self.assertEqual(info['status']['protocol_version'],3)
            self.assertEqual(parser.bad_packets,0)
    def test_missing_reordered_discard_and_recover(self):
        parts=list(self.strips(160,90));a=FrameAssembler()
        self.assertIsNone(a.feed(1,parts[0]));self.assertIsNone(a.feed(1,parts[2]))
        for p in parts[3:]:self.assertIsNone(a.feed(1,p))
        for p in parts[:-1]:self.assertIsNone(a.feed(2,p))
        self.assertIsNotNone(a.feed(2,parts[-1]))
    def test_rtl_wire_trace_actual_uart(self):
        trace=Path(__file__).resolve().parents[1]/'checks/usb_strip_trace.hex'
        wire=bytes.fromhex(trace.read_text());parser=PacketParser();assembler=FrameAssembler();sizes=[]
        for kind,seq,p in parser.feed(wire):
            if kind==VIDEO:
                result=assembler.feed(seq,p)
                if result:sizes.append((result[1]['width'],result[1]['height']))
        self.assertEqual(sizes,[(16,10),(32,20)]);self.assertEqual(parser.bad_packets,0)
    def test_illegal_strip_is_bounded(self):
        p=next(self.strips(160,90));a=FrameAssembler()
        for q in (p[:-1],p[:53]+bytes([255])+p[54:]):
            with self.assertRaises(ValueError):a.feed(1,q)

if __name__=='__main__':unittest.main()
