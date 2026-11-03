"""FPGA-driven face events with five-second grace and durable notification cursors."""
from pathlib import Path
import json,sqlite3,threading,time,uuid
from recording import MP4Recording,timestamp

class EventStore:
    def __init__(self,root):
        self.root=Path(root);self.root.mkdir(parents=True,exist_ok=True)
        self.condition=threading.Condition(threading.RLock())
        self.db=sqlite3.connect(self.root/'events.sqlite3',check_same_thread=False)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.executescript('''
          CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY,started REAL NOT NULL,data TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS notifications(seq INTEGER PRIMARY KEY AUTOINCREMENT,event_id TEXT,
            kind TEXT NOT NULL,created REAL NOT NULL,data TEXT NOT NULL,read INTEGER NOT NULL DEFAULT 0,
            UNIQUE(event_id,kind));''')
        self.db.execute('INSERT OR IGNORE INTO meta VALUES (?,?)',('instance_id',uuid.uuid4().hex));self.db.commit()
        self.instance_id=self.db.execute('SELECT value FROM meta WHERE key=?',('instance_id',)).fetchone()[0]

    def save(self,event):
        with self.condition:
            self.db.execute('INSERT OR REPLACE INTO events VALUES (?,?,?)',
                (event['id'],event['started_unix'],json.dumps(event,ensure_ascii=False)));self.db.commit()

    def get(self,event_id):
        with self.condition:
            row=self.db.execute('SELECT data FROM events WHERE id=?',(event_id,)).fetchone()
            if row is None:raise ValueError('事件不存在')
            return json.loads(row[0])

    def events(self,limit=50,before=None):
        with self.condition:
            query='SELECT data FROM events';args=[]
            if before is not None:query+=' WHERE started < ?';args.append(before)
            query+=' ORDER BY started DESC LIMIT ?';args.append(limit)
            return [json.loads(r[0]) for r in self.db.execute(query,args)]

    def notify(self,event_id,kind,title,body):
        created=time.time();item=dict(event_id=event_id,kind=kind,title=title,body=body,
                                     created_at=timestamp(created),created_unix=created)
        with self.condition:
            self.db.execute('INSERT OR IGNORE INTO notifications(event_id,kind,created,data) VALUES (?,?,?,?)',
                (event_id,kind,created,json.dumps(item,ensure_ascii=False)))
            self.db.commit();self.condition.notify_all()

    def notifications(self,after=0,wait=0,limit=50):
        deadline=time.monotonic()+wait
        with self.condition:
            while True:
                rows=self.db.execute('SELECT seq,data,read FROM notifications WHERE seq>? ORDER BY seq LIMIT ?',
                    (after,limit)).fetchall()
                if rows or time.monotonic()>=deadline:break
                self.condition.wait(max(0,deadline-time.monotonic()))
            latest=self.db.execute('SELECT COALESCE(MAX(seq),0) FROM notifications').fetchone()[0]
            unread=self.db.execute('SELECT COUNT(*) FROM notifications WHERE read=0').fetchone()[0]
            return dict(items=[dict(json.loads(data),seq=seq,read=bool(read)) for seq,data,read in rows],
                        latest_seq=latest,unread=unread,instance_id=self.instance_id)

    def read(self,upto):
        with self.condition:
            self.db.execute('UPDATE notifications SET read=1 WHERE seq<=?',(upto,));self.db.commit()

    def recent(self,limit=30):
        with self.condition:
            rows=self.db.execute('SELECT seq,data,read FROM notifications ORDER BY seq DESC LIMIT ?',(limit,)).fetchall()
            result=self.notifications(after=rows[0][0] if rows else 0)
            result['items']=[dict(json.loads(data),seq=seq,read=bool(read)) for seq,data,read in reversed(rows)]
            return result

    def close(self):
        with self.condition:self.db.close()

class FaceEvents:
    def __init__(self,root,*,grace=5.,clock=time.monotonic,wall=time.time,
                 recorder_factory=MP4Recording,start_worker=True):
        self.root=Path(root);self.store=EventStore(root);self.lock=threading.RLock()
        self.clock=clock;self.wall=wall;self.grace=grace;self.recorder_factory=recorder_factory
        self.settings_file=self.root/'settings.json';self.enabled=True
        try:self.enabled=bool(json.loads(self.settings_file.read_text())['enabled'])
        except (OSError,ValueError,KeyError):pass
        self.active=self.recorder=None;self.missing_since=self.last_status=None
        self.missing_reason='face_disappeared';self.last_png=None;self.last_frame_time=-1e30;self.fps=4
        self.error='';self.stopping=threading.Event()
        for event in self.store.events(limit=100000):
            if event.get('state')=='recording':
                event.update(state='interrupted',ended_at=timestamp(),ended_unix=time.time(),reason='server_restarted',
                             error='上次运行未正常结束，视频可能不完整')
                self.store.save(event);self._metadata(event)
                self.store.notify(event['id'],'interrupted','上次人脸记录中断',event['started_at'])
        if start_worker:
            threading.Thread(target=self._worker,daemon=True,name='face-event-timer').start()

    def _metadata(self,event):
        path=self.root/(event['id']+'.json');temp=path.with_suffix('.json.tmp')
        temp.write_text(json.dumps(event,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');temp.replace(path)

    def _start_video(self,png,now):
        if self.recorder or self.active.get('error'):return
        name=self.active['id']+'.mp4'
        try:
            self.recorder=self.recorder_factory(self.root,name,png,self.fps,now=now,wall=self.wall())
            self.active.update(video=name,video_started_at=timestamp(self.wall()),fps=self.recorder.fps)
            self.store.save(self.active)
        except Exception as exc:
            self.active['error']=self.error=str(exc);self.store.save(self.active)
            self.store.notify(self.active['id'],'recording_error','人脸录像失败',str(exc))

    def observe(self,state):
        with self.lock:
            now=self.clock();self._tick(now);self.last_status=now
            if not self.enabled:return
            if bool(state.get('face_valid')):
                if self.active is None:
                    wall=self.wall();event_id='face_'+timestamp(wall)[:19].replace('-','').replace(':','').replace('T','_')+'_'+uuid.uuid4().hex[:8]
                    self.active=dict(id=event_id,started_at=timestamp(wall),started_unix=wall,
                        last_seen_at=timestamp(wall),last_seen_unix=wall,state='recording',ended_at=None,
                        duration_seconds=None,video=None,frames=0,thumbnail=None,error='',reason=None)
                    self.store.save(self.active);self._metadata(self.active)
                    self.store.notify(event_id,'face_started','检测到人脸，开始记录','开始时间：'+self.active['started_at'])
                    if self.last_png and now-self.last_frame_time<=3:self._start_video(self.last_png,now)
                self.active['last_seen_at']=timestamp(self.wall());self.active['last_seen_unix']=self.wall()
                self.missing_since=None;self.missing_reason='face_disappeared'
            elif self.active and self.missing_since is None:
                self.missing_since=now;self.missing_reason='face_disappeared'

    def accept(self,png,info,fps=4):
        with self.lock:
            now=self.clock();self._tick(now)
            self.last_png=png;self.last_frame_time=now;self.fps=max(1,min(6,int(fps)))
            if self.active:
                if not self.active['thumbnail']:
                    from PIL import Image
                    import io
                    name=self.active['id']+'.jpg'
                    Image.open(io.BytesIO(png)).convert('RGB').save(self.root/name,'JPEG',quality=85)
                    self.active['thumbnail']=name
                self._start_video(png,now)
                if self.recorder:self.recorder.accept(png,info,self.wall());self.recorder.advance(now,self.wall())

    def _tick(self,now):
        if not self.active:return
        if self.last_status is not None and now-self.last_status>=3 and self.missing_since is None:
            self.missing_since=self.last_status+3;self.missing_reason='telemetry_timeout'
        if self.missing_since is not None and now-self.missing_since>=self.grace:self._finish(self.missing_reason)
        elif self.recorder:self.recorder.advance(now,self.wall())

    def tick(self):
        with self.lock:self._tick(self.clock())

    def _finish(self,reason):
        if not self.active:return
        event,recorder=self.active,self.recorder;self.active=self.recorder=None;self.missing_since=None;now=self.wall()
        if recorder:
            try:recorder.advance(self.clock(),now);recorder.close();event['frames']=recorder.frames
            except Exception as exc:event['error']=self.error=str(exc)
        event.update(ended_at=timestamp(now),ended_unix=now,duration_seconds=round(now-event['started_unix'],3),
            reason=reason,state='completed' if recorder and not event['error'] else 'no_video')
        self.store.save(event);self._metadata(event)
        title='人脸事件已保存' if event['state']=='completed' else '人脸事件结束（视频未完整保存）'
        body='开始 '+event['started_at']+'；持续 '+str(event['duration_seconds'])+' 秒'
        if reason!='face_disappeared':body+='；'+{'disconnected':'设备连接中断','server_shutdown':'电脑服务关闭',
            'monitor_disabled':'已关闭自动记录','telemetry_timeout':'状态回传超时'}.get(reason,reason)
        self.store.notify(event['id'],'face_completed',title,body)

    def disconnected(self):
        with self.lock:self._finish('disconnected');self.last_status=None;self.last_png=None

    def set_enabled(self,enabled):
        with self.lock:
            self.enabled=enabled;self.settings_file.write_text(json.dumps(dict(enabled=enabled)),encoding='utf-8')
            if not enabled:self._finish('monitor_disabled')

    def status(self):
        with self.lock:
            active=dict(self.active) if self.active else None
            if active and self.recorder:active['frames']=self.recorder.frames
            remaining=None if self.missing_since is None else round(max(0,self.grace-(self.clock()-self.missing_since)),1)
            return dict(enabled=self.enabled,grace_seconds=self.grace,active=active,remaining_seconds=remaining,error=self.error)

    def _worker(self):
        while not self.stopping.wait(.1):
            try:self.tick()
            except Exception as exc:
                with self.lock:
                    self.error=str(exc)
                    if self.active:self.active['error']=str(exc);self._finish('recording_error')

    def close(self):
        self.stopping.set()
        with self.lock:self._finish('server_shutdown')
        self.store.close()
