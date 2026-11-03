import io,json,tempfile,threading,time,unittest
from pathlib import Path
from PIL import Image
from face_events import FaceEvents,EventStore
from recording import MP4Recording
from media_store import MediaStore
from app import create_app

def png(color='red'):
    out=io.BytesIO();Image.new('RGB',(160,90),color).save(out,format='PNG');return out.getvalue()

class Clock:
    value=0.
    def mono(self):return self.value
    def wall(self):return 1770000000.+self.value
    def advance(self,n):self.value+=n

class Recorder:
    def __init__(self,root,name,image,fps,now=None,wall=None):self.frames=0;self.fps=fps;self.closed=False
    def advance(self,*a):self.frames+=1
    def accept(self,*a):pass
    def close(self):self.closed=True

class FaceEventTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.clock=Clock()
        self.engine=FaceEvents(self.temp.name,clock=self.clock.mono,wall=self.clock.wall,recorder_factory=Recorder,start_worker=False)
    def tearDown(self):self.engine.close();self.temp.cleanup()
    def begin(self):
        self.engine.accept(png(),{'frame_counter':1},4);self.engine.observe({'face_valid':True})
        return self.engine.status()['active']['id']
    def test_reappear_within_five_seconds_keeps_single_video(self):
        event=self.begin();self.clock.advance(1);self.engine.observe({'face_valid':False})
        self.clock.advance(4.9);self.engine.tick();self.assertEqual(self.engine.active['id'],event)
        self.engine.observe({'face_valid':True});self.assertIsNone(self.engine.missing_since)
        self.clock.advance(1);self.engine.observe({'face_valid':False})
        self.clock.advance(4.99);self.engine.tick();self.assertIsNotNone(self.engine.active)
        self.clock.advance(.01);self.engine.tick();self.assertIsNone(self.engine.active)
        events=self.engine.store.events();self.assertEqual(len(events),1)
        self.assertEqual(events[0]['state'],'completed');self.assertEqual(events[0]['reason'],'face_disappeared')
        self.assertEqual([n['kind'] for n in self.engine.store.notifications()['items']],['face_started','face_completed'])
    def test_reappear_after_five_seconds_creates_new_event(self):
        event=self.begin();self.engine.observe({'face_valid':False});self.clock.advance(5.001)
        self.engine.observe({'face_valid':True})
        self.assertNotEqual(self.engine.active['id'],event);self.assertEqual(len(self.engine.store.events()),2)
    def test_no_frame_still_finishes_and_reports_missing_video(self):
        self.engine.observe({'face_valid':True});self.engine.observe({'face_valid':False})
        self.clock.advance(5);self.engine.tick()
        self.assertEqual(self.engine.store.events()[0]['state'],'no_video')
    def test_disconnected_reason_is_not_face_disappearance(self):
        self.begin();self.engine.disconnected();e=self.engine.store.events()[0]
        self.assertEqual(e['reason'],'disconnected');self.assertIsNone(self.engine.active)
    def test_stale_telemetry_does_not_record_forever(self):
        self.begin();self.clock.advance(8.1);self.engine.tick()
        self.assertEqual(self.engine.store.events()[0]['reason'],'telemetry_timeout')
    def test_setting_off_finishes_event_and_persists(self):
        self.begin();self.engine.set_enabled(False)
        self.engine.observe({'face_valid':True});self.assertIsNone(self.engine.active)
        other=FaceEvents(self.temp.name,start_worker=False);self.assertFalse(other.enabled);other.close()
    def test_restart_marks_only_unfinished_event_interrupted(self):
        self.begin();other=FaceEvents(self.temp.name,start_worker=False)
        self.assertEqual(other.store.events()[0]['state'],'interrupted');other.close()
        # Prevent teardown from replacing the simulated recovery state.
        self.engine.active=None;self.engine.recorder=None
    def test_notifications_durable_cursor_read_and_idempotence(self):
        event=self.begin();s=self.engine.store
        s.notify(event,'face_started','duplicate','duplicate')
        self.assertEqual(s.notifications()['latest_seq'],1)
        other=EventStore(self.temp.name);self.assertEqual(other.notifications()['unread'],1)
        other.read(1);self.assertEqual(s.notifications()['unread'],0)
        self.assertEqual(s.notifications(after=1)['items'],[])
        other.close()
    def test_long_poll_wakes_on_new_message(self):
        result=[];worker=threading.Thread(target=lambda:result.append(self.engine.store.notifications(after=0,wait=2)))
        worker.start();time.sleep(.05);self.engine.store.notify('x','test','Test','Body');worker.join(2)
        self.assertFalse(worker.is_alive());self.assertEqual(result[0]['items'][0]['title'],'Test')

class ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        class Board:
            def snapshot(self):return {'status':{},'media':self.media.status(),'connected':False}
        self.board=Board();self.board.media=MediaStore(self.temp.name)
        self.board.lock=threading.RLock();self.board.frame=None;self.board.preview_fps=4
        self.client=create_app(self.board).test_client()
    def tearDown(self):self.board.media.close();self.temp.cleanup()
    def test_api_events_settings_notifications_and_assets(self):
        c=self.client;self.assertEqual(c.get('/api/health').json['software_id'],'plus_v3_sort_app')
        self.assertEqual(c.post('/api/events/settings',json={'enabled':'yes'}).status_code,400)
        self.assertEqual(c.get('/api/events').json['events'],[])
        self.assertEqual(c.post('/api/notifications/test',json={}).status_code,200)
        data=c.get('/api/notifications').json;self.assertEqual(data['unread'],1)
        self.assertEqual(c.post('/api/notifications/read',json={'upto':data['latest_seq']}).status_code,200)
        self.assertEqual(c.get('/api/notifications').json['unread'],0)
        self.assertEqual(c.get('/api/events/not-there/video').status_code,404)
        self.assertEqual(c.get('/api/notifications?wait=bad').status_code,400)
        self.assertEqual(c.post('/api/events/settings',data='x').status_code,415)
    def test_manual_stop_does_not_stop_face_event(self):
        self.board.media.events.observe({'face_valid':True});event=self.board.media.events.active['id']
        self.assertEqual(self.client.post('/api/media',json={'action':'stop'}).status_code,200)
        self.assertEqual(self.board.media.events.active['id'],event)

class EncodingTests(unittest.TestCase):
    def test_real_h264_round_trip_and_frame_timestamps(self):
        import cv2
        with tempfile.TemporaryDirectory() as root:
            r=MP4Recording(root,'test.mp4',png(),fps=4,now=0,wall=1770000000)
            r.advance(0,1770000000);r.accept(png('blue'),{'frame_counter':2,'status':{'source_seq':9}},1770000000.5)
            r.advance(1.25,1770000001.25);r.close()
            video=cv2.VideoCapture(str(Path(root)/'test.mp4'))
            self.assertTrue(video.isOpened());self.assertEqual(int(video.get(cv2.CAP_PROP_FRAME_COUNT)),6)
            self.assertAlmostEqual(video.get(cv2.CAP_PROP_FPS),4);ok,image=video.read();self.assertTrue(ok);video.release()
            timeline=[json.loads(s) for s in (Path(root)/'test.mp4.jsonl').read_text().splitlines()]
            self.assertEqual(len(timeline),6);self.assertTrue(timeline[0]['host_time'].endswith('+08:00'))
            self.assertFalse((Path(root)/'test.mp4.partial.mp4').exists())

if __name__=='__main__':unittest.main()
