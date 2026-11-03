import sys,tempfile,unittest,io
from PIL import Image
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from sort_link import ObservationParser,SortLink,encode_observation
from media_store import MediaStore
from protocol import decode_status

class SortTests(unittest.TestCase):
 def test_document_vector_fragmentation_resync(self):
  raw=bytes.fromhex('A5 5A 01 01 34 12 70 04 02 12 00 01 01 03 80 02 40 01 0F 01 03 02 03 F0 00 A0 00 07 B7 07')
  p=ObservationParser();rows=[]
  for v in b'noise\xa5'+raw:rows+=p.feed(bytes([v]))
  self.assertEqual(rows[0]['targets'][1]['class'],3)
  self.assertEqual(encode_observation(0x1234,0x0470,rows[0]['targets']),raw)
  damaged=bytearray(raw);damaged[15]^=1
  self.assertEqual(len(p.feed(damaged+raw)),1);self.assertGreater(p.errors,0)

 def test_semantic_and_bound_checks(self):
  p=ObservationParser();t=dict(slot=0,**{'class':4},shape=2,digit=2,x=1280,y=100,flags=15)
  self.assertEqual(p.feed(encode_observation(0,0,[t])),[])
  p.feed(b'x'*100000);self.assertLess(len(p.buffer),8193)

 def test_marker_no_alert_square_alert_and_frozen_frame(self):
  with tempfile.TemporaryDirectory() as d:
   media=MediaStore(d);now=[10.];link=SortLink(media,clock=lambda:now[0])
   marker=dict(slot=0,**{'class':3},shape=2,digit=3,x=240,y=160,flags=7)
   alert=dict(slot=1,**{'class':4},shape=2,digit=2,x=640,y=360,flags=15)
   link.accept(dict(seq=1,frame_id=10,targets=[marker]));self.assertEqual(media.events.store.events(),[])
   link.accept(dict(seq=2,frame_id=11,targets=[marker,alert]));link.accept(dict(seq=3,frame_id=11,targets=[alert]))
   self.assertEqual(len(media.events.store.events()),1)
   now[0]+=.5;link.accept(dict(seq=4,frame_id=11,targets=[alert]));self.assertTrue(link.snapshot()['stale'])
   media.close()

 def test_version5_status_compatible(self):
  b=bytearray(44);b[0]=5;b[2]=13;b[7]=6;b[34]=(3<<3)|3
  s=decode_status(b);self.assertEqual(s['mode_name'],'SORT');self.assertEqual(s['sort_phase'],6)
  self.assertEqual(s['sort_labels'][0],dict(slot=0,digit=3,**{'class':3}))

 def test_scan_stores_one_real_frame_and_thumbnail_per_entry(self):
  with tempfile.TemporaryDirectory() as d:
   media=MediaStore(d);link=SortLink(media);buf=io.BytesIO();Image.new('RGB',(160,90),'white').save(buf,format='PNG')
   info={'status':dict(mode=13,protocol_version=5,sort_phase=3,face_valid=True,face_box=[0,100,0,100],source_seq=12)}
   link.board_frame(buf.getvalue(),info);link.board_frame(buf.getvalue(),info)
   events=media.events.store.events();self.assertEqual(len(events),1);event=events[0]
   self.assertEqual(event['kind'],'face_scan');self.assertTrue((media.events.root/event['thumbnail']).is_file())
   self.assertTrue((media.root/event['details']['photo']).is_file());self.assertIsNone(event['video'])
   link.board_frame(buf.getvalue(),{'status':dict(mode=0)});link.board_frame(buf.getvalue(),info)
   self.assertEqual(len(media.events.store.events()),2);media.close()

if __name__=='__main__':unittest.main()
