import hashlib,json,sys,threading,unittest
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app import create_app
from run import select_endpoint
from server_info import identity,ROOT,PROJECT_ID,DEPLOYMENT_ID

@contextmanager
def fake_server(payload):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            body=json.dumps(payload).encode()
            self.send_response(200);self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:yield server.server_port
    finally:server.shutdown();server.server_close();thread.join()

class PackageTests(unittest.TestCase):
    def test_reuses_only_this_project_copy(self):
        with fake_server(identity()) as port:
            self.assertEqual(select_endpoint(port),(port,True))

    def test_does_not_reuse_old_software_server(self):
        with fake_server(dict(software_id='plus_v2_face_events_app',software_version='1.1.0')) as port:
            if port==65535:self.skipTest('No higher TCP port available')
            selected,reuse=select_endpoint(port)
            self.assertGreater(selected,port);self.assertFalse(reuse)

    def test_does_not_silently_reuse_old_same_project_process(self):
        payload=identity();payload['software_version']='3.0.0'
        with fake_server(payload) as port:
            with self.assertRaisesRegex(RuntimeError,'旧服务3.0.0'):select_endpoint(port)

    def test_does_not_reuse_another_packaged_copy(self):
        payload=identity();payload['deployment_id']='another-directory'
        with fake_server(payload) as port:
            if port==65535:self.skipTest('No higher TCP port available')
            selected,reuse=select_endpoint(port)
            self.assertGreater(selected,port);self.assertFalse(reuse)

    def test_foreign_non_object_health_does_not_break_startup(self):
        with fake_server(['another-service']) as port:
            if port==65535:self.skipTest('No higher TCP port available')
            selected,reuse=select_endpoint(port)
            self.assertGreater(selected,port);self.assertFalse(reuse)

    def test_health_identifies_packaged_project(self):
        app=create_app(object())
        with app.test_client() as client:
            data=client.get('/api/health').json
        self.assertEqual(data['project_id'],PROJECT_ID)
        self.assertEqual(data['deployment_id'],DEPLOYMENT_ID)
        self.assertEqual(data['software_id'],'plus_v3_sort_app')

    def test_android_download_uses_sibling_project(self):
        app=create_app(object());client=app.test_client()
        response=client.get('/download/android.apk')
        try:
            self.assertEqual(response.status_code,200)
            release=ROOT.parent/'android/releases'
            current=json.loads((release/'release.json').read_text(encoding='utf-8-sig'))['versioned_file']
            expected=release/current
            self.assertEqual(hashlib.sha256(response.data).digest(),hashlib.sha256(expected.read_bytes()).digest())
            self.assertIn(current,response.headers['Content-Disposition'])
        finally:response.close()

if __name__=='__main__':unittest.main()

