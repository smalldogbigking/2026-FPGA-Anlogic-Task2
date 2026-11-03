"""H.264 MP4 with host/source timestamps. No camera or FPGA changes."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import io, json, os, subprocess, time
from PIL import Image
import imageio_ffmpeg

def timestamp(value=None):
    return datetime.fromtimestamp(time.time() if value is None else value, timezone(timedelta(hours=8))).isoformat(timespec='milliseconds')

class MP4Recording:
    def __init__(self,root,name,png,fps=4,now=None,wall=None):
        self.root=Path(root);self.root.mkdir(parents=True,exist_ok=True)
        self.name=name;self.path=self.root/name;self.partial=self.root/(name+'.partial.mp4')
        self.fps=max(1,min(6,int(fps)))
        image=Image.open(io.BytesIO(png)).convert('RGB')
        self.size=tuple(max(2,(v+1)//2*2) for v in image.size)
        self.last_png=png;self.last_info={};self.last_arrival=time.time() if wall is None else wall
        self.next_frame=time.monotonic() if now is None else now
        self.frames=0;self.closed=False;self.error=None
        self.timeline=(self.root/(name+'.jsonl')).open('w',encoding='utf-8')
        self.error_log=(self.root/(name+'.encoder.log')).open('wb')
        cmd=[imageio_ffmpeg.get_ffmpeg_exe(),'-hide_banner','-loglevel','error','-f','rawvideo',
             '-pixel_format','rgb24','-video_size','%dx%d'%self.size,'-framerate',str(self.fps),
             '-i','pipe:0','-an','-c:v','libx264','-preset','ultrafast','-crf','23',
             '-pix_fmt','yuv420p','-movflags','+faststart','-y',str(self.partial)]
        try:self.process=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=self.error_log,
                 creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        except Exception:
            self.timeline.close();self.error_log.close();raise

    def accept(self,png,info,wall=None):
        self.last_png=png;self.last_info=dict(info or {});self.last_arrival=time.time() if wall is None else wall

    def advance(self,now=None,wall=None):
        if self.closed:return
        now=time.monotonic() if now is None else now;wall=time.time() if wall is None else wall
        image=Image.open(io.BytesIO(self.last_png)).convert('RGB')
        if image.size!=self.size:image=image.resize(self.size,Image.Resampling.BILINEAR)
        pixels=image.tobytes();written=0
        while self.next_frame<=now+1e-8 and written<self.fps*10:
            self.process.stdin.write(pixels)
            source=self.last_info.get('status',{})
            self.timeline.write(json.dumps(dict(video_index=self.frames,time=wall-(now-self.next_frame),
                host_time=timestamp(wall-(now-self.next_frame)),source_received_at=timestamp(self.last_arrival),
                source_seq=source.get('source_seq'),frame=self.last_info.get('frame_counter')),
                ensure_ascii=False)+'\n')
            self.frames+=1;written+=1;self.next_frame+=1/self.fps
        if self.next_frame<now-10:self.next_frame=now
        self.timeline.flush()

    def close(self):
        if self.closed:
            if self.error:raise OSError(self.error)
            return self.name
        self.closed=True
        try:
            self.process.stdin.close()
            try:result=self.process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                self.process.kill();self.process.wait();raise OSError('录像编码超时，已保留临时文件')
            if result!=0 or not self.frames:raise OSError('录像编码失败，请查看 encoder.log')
            os.replace(self.partial,self.path)
            return self.name
        except Exception as exc:
            self.error=str(exc);raise
        finally:self.timeline.close();self.error_log.close()
