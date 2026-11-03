"""Host-only photos, MJPEG recordings and optional periodic face crops."""
from pathlib import Path
import io, json, threading, time, uuid, os
import cv2
import numpy as np
from PIL import Image
from face_events import FaceEvents

class MediaStore:
    def __init__(self, root=None):
        self.root=Path(root or os.environ.get('FPGA_CAPTURE_DIR') or Path(__file__).with_name('captures'))
        self.root.mkdir(exist_ok=True, parents=True)
        self.lock=threading.RLock()
        self.writer=None;self.record_id=None;self.record_frames=0;self.record_size=None
        self.record_fps=2;self.next_record=0.;self.last_image=None
        self.timeline=None;self.face_auto=False;self.face_seen=False;self.last_face=0.
        self.events=FaceEvents(self.root/'events')

    def photo(self, png, prefix='photo'):
        with self.lock:
            if not png: raise ValueError('还没有收到画面')
            name=prefix+'_'+time.strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:8]+'.png'
            image=Image.open(io.BytesIO(png)).convert('RGB')
            image.save(self.root/name, format='PNG')
            return name

    def start(self, png, fps=2):
        with self.lock:
            if self.writer: return self.record_id
            if not png: raise ValueError('请先接收开发板画面')
            im=Image.open(io.BytesIO(png)).convert('RGB')
            name='record_'+time.strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:8]+'.avi'
            writer=cv2.VideoWriter(str(self.root/name),cv2.VideoWriter_fourcc(*'MJPG'),fps,im.size)
            if not writer.isOpened(): raise ValueError('电脑录像编码器打开失败')
            self.writer=writer;self.record_id=name;self.record_frames=0;self.record_size=im.size
            self.record_fps=fps;self.next_record=0.
            self.timeline=(self.root/(name+'.jsonl')).open('w',encoding='utf8')
            return name

    def accept(self,png,info,fps=4):
        self.events.accept(png,info,fps)
        with self.lock:
            now=time.monotonic();state=info['status']
            if self.writer:
                image=np.asarray(Image.open(io.BytesIO(png)).convert('RGB'))[:,:,::-1].copy()
                if image.shape[1::-1]!=self.record_size:image=cv2.resize(image,self.record_size,interpolation=cv2.INTER_LINEAR)
                if self.next_record==0: self.next_record=now
                # Repeat the last received frame across transport gaps, capped at
                # 10 seconds to keep disconnects from creating unbounded writes.
                while self.last_image is not None and self.next_record+1/self.record_fps<now and now-self.next_record<10:
                    self.writer.write(self.last_image);self.record_frames+=1;self.next_record+=1/self.record_fps
                self.writer.write(image);self.record_frames+=1
                self.next_record=max(self.next_record+1/self.record_fps,now)
                self.last_image=image
                self.timeline.write(json.dumps({'time':time.time(),'source_seq':state.get('source_seq'),'frame':info['frame_counter'],'avi_index':self.record_frames-1})+'\n')
                self.timeline.flush()
            face=bool(state.get('face_valid'))
            if self.face_auto and face and (not self.face_seen or now-self.last_face>=10):
                im=Image.open(io.BytesIO(png)).convert('RGB');w,h=im.size
                x0,x1,y0,y1=state['face_box']
                box=(max(0,x0*w//1280),max(0,y0*h//720),min(w,(x1+1)*w//1280),min(h,(y1+1)*h//720))
                if box[2]>box[0] and box[3]>box[1]:
                    buf=io.BytesIO();im.crop(box).save(buf,format='PNG');self.photo(buf.getvalue(),'face');self.last_face=now
            self.face_seen=face

    def stop(self):
        with self.lock:
            name=self.record_id
            if self.writer: self.writer.release();self.writer=None
            if self.timeline: self.timeline.close();self.timeline=None
            self.last_image=None
            return name

    def files(self):
        with self.lock:
            return [{'id':p.name,'bytes':p.stat().st_size} for p in sorted(self.root.iterdir(),key=lambda p:p.stat().st_mtime,reverse=True)
                    if p.suffix in ('.png','.avi') and (not self.writer or p.name!=self.record_id)][:100]

    def path(self, name):
        if name not in {f['id'] for f in self.files()}: raise ValueError('文件不存在或尚未完成保存')
        return self.root/name

    def status(self):
        with self.lock:
            return {'recording':bool(self.writer),'recording_name':self.record_id,'recording_frames':self.record_frames,'face_auto':self.face_auto,'files':self.files(),'face_events':self.events.status()}

    def close(self):
        self.events.close()
        self.stop()
