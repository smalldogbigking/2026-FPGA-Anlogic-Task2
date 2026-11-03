"""Independent SORT observation monitor and MCU JSON event input.

No pixel inference or grasp decisions execute on the PC. GPIO UART can be
monitored with an extra USB-TTL adapter; MCU USB logs use JSON lines.
"""
import binascii,json,struct,threading,time,uuid,io
from pathlib import Path
import serial
from PIL import Image
from recording import timestamp

CLASS_NAMES=['待确认','圆形奇数','圆形偶数','标定标志','方形异常']

def encode_observation(seq,frame,targets):
    body=struct.pack('<BBHHBB',1,1,seq&65535,frame&65535,len(targets),9*len(targets))
    for t in targets:body+=struct.pack('<BBBBHHB',t['slot'],t['class'],t['shape'],t['digit'],t['x'],t['y'],t['flags'])
    return b'\xa5\x5a'+body+struct.pack('<H',binascii.crc_hqx(body,65535))

class ObservationParser:
    def __init__(self):self.buffer=bytearray();self.errors=0
    def feed(self,data):
        self.buffer.extend(data);result=[]
        if len(self.buffer)>8192:self.buffer=self.buffer[-4096:];self.errors+=1
        while len(self.buffer)>=2:
            p=self.buffer.find(b'\xa5\x5a')
            if p<0:self.buffer=self.buffer[-1:];break
            if p:del self.buffer[:p]
            if len(self.buffer)<10:break
            v,k,seq,frame,count,n=struct.unpack_from('<BBHHBB',self.buffer,2)
            if (v,k)!=(1,1) or count>4 or n!=9*count:
                del self.buffer[0];self.errors+=1;continue
            size=12+n
            if len(self.buffer)<size:break
            raw=bytes(self.buffer[:size])
            if binascii.crc_hqx(raw[2:-2],65535)!=int.from_bytes(raw[-2:],'little'):
                del self.buffer[0];self.errors+=1;continue
            targets=[];slots=set();ok=True
            for i in range(count):
                s,c,h,d,x,y,f=struct.unpack_from('<BBBBHHB',raw,10+i*9)
                if s>3 or s in slots or c>4 or h>3 or d>5 or x>=1280 or y>=720 or f&240:ok=False
                slots.add(s);targets.append(dict(slot=s,**{'class':c},class_name=CLASS_NAMES[c] if c<5 else '?',shape=h,digit=d,x=x,y=y,flags=f))
            del self.buffer[:size]
            if ok:result.append(dict(seq=seq,frame_id=frame,targets=targets))
            else:self.errors+=1
        return result

class SortLink:
    def __init__(self,media,clock=time.monotonic):
        self.media=media;self.clock=clock;self.lock=threading.RLock();self.serial=None
        self.parser=ObservationParser();self.last={};self.last_rx=self.last_new=0.;self.port='';self.error=''
        self.mode='vision';self.generation=0;self.last_seq=None;self.last_frame=None;self.gaps=0
        self.alerts={};self.face_session=False;self.face_pending=False

    def snapshot(self):
        with self.lock:
            now=self.clock()
            return dict(connected=self.serial is not None,port=self.port,kind=self.mode,error=self.error,
                        observation=self.last,age=round(now-self.last_rx,3) if self.last_rx else None,
                        frame_age=round(now-self.last_new,3) if self.last_new else None,
                        stale=not self.last_new or now-self.last_new>.3,bad_packets=self.parser.errors,gaps=self.gaps)

    def event(self,kind,data=None,event_id=None):
        if kind not in ('face_scan','square_alert','sort_started','sort_done','sort_error'):raise ValueError('不支持的分拣事件')
        data=data or {};now=time.time();key=event_id or ('sort_'+uuid.uuid4().hex)
        labels={'face_scan':'人脸已扫描','square_alert':'方形异常，禁止抓取','sort_started':'机械臂开始分拣','sort_done':'机械臂分拣完成','sort_error':'机械臂故障或保护停机'}
        descriptions={'face_scan':'人脸扫描画面已保存，可在事件记录查看。',
                      'square_alert':f"数字 {data.get('digit','—')}，像素位置 ({data.get('x','—')}, {data.get('y','—')})；该工件不抓取。",
                      'sort_started':'机械臂已开始处理工件。','sort_done':'机械臂已完成工件分拣。',
                      'sort_error':'机械臂保护停机，请检查急停、限位与通信状态。'}
        event=dict(id=key,kind=kind,title=labels[kind],description=descriptions[kind],state='observed',started_unix=now,started_at=timestamp(now),
                   ended_at=timestamp(now),ended_unix=now,duration_seconds=None,video=None,thumbnail=None,error='',details=data)
        if kind=='face_scan':
            png=data.pop('_png',None)
            if not png:raise ValueError('没有对应的人脸画面，未生成扫描留档')
            photo=self.media.photo(png,'sort_face_scan');event['details']['photo']=photo
            event['thumbnail']=key+'.jpg'
            Image.open(io.BytesIO(png)).convert('RGB').save(self.media.events.root/event['thumbnail'],format='JPEG',quality=92)
        self.media.events.store.save(event)
        path=self.media.events.root/(key+'.json');path.write_text(json.dumps(event,ensure_ascii=False,indent=2),encoding='utf-8')
        self.media.events.store.notify(key,kind,labels[kind],descriptions[kind])
        return event

    def board_frame(self,png,info):
        state=info['status'];sorting=state.get('mode')==13 and state.get('protocol_version',0)>=5
        if not sorting:self.face_session=False
        if sorting and state.get('sort_phase')==3 and state.get('face_valid') and not self.face_session:
            try:
                self.event('face_scan',{'source_seq':state.get('source_seq'),'face_box':state.get('face_box'),'_png':png})
                self.face_session=True
            except (OSError,ValueError) as exc:self.error='扫描图像未保存：'+str(exc)

    def accept(self,observation):
        with self.lock:
            now=self.clock();seq=observation['seq'];frame=observation['frame_id']
            if self.last_seq is not None:
                ds=(seq-self.last_seq)&65535
                if ds==0 or ds>=32768:return
                self.gaps+=ds-1
            self.last_seq=seq;self.last_rx=now
            if self.last_frame is None or 0<(frame-self.last_frame)&65535<32768:
                self.last_frame=frame;self.last_new=now
            self.last=observation
            for t in observation['targets']:
                if t['class']!=4 or t['shape']!=2 or not 1<=t['digit']<=5 or t['digit']==3 or t['flags']&7!=7:continue
                # PC notification dedup only. No robot task queue on FPGA/PC.
                key=(round(t['x']/40),round(t['y']/40))
                if now-self.alerts.get(key,-1e30)>10:
                    self.event('square_alert',t.copy());self.alerts[key]=now

    def connect(self,port,kind='vision'):
        if kind not in ('vision','mcu'):raise ValueError('串口类型错误')
        self.disconnect();ser=serial.Serial(port,115200,timeout=.1,write_timeout=1)
        with self.lock:
            self.serial=ser;self.port=port;self.mode=kind;self.error='';self.generation+=1;generation=self.generation
            self.parser=ObservationParser();self.last_seq=self.last_frame=None;self.last={};self.last_rx=self.last_new=0
        def reader():
            lines=bytearray()
            try:
                while self.serial is ser and generation==self.generation:
                    raw=ser.read(1024)
                    if kind=='vision':
                        for obs in self.parser.feed(raw):self.accept(obs)
                    else:
                        lines.extend(raw)
                        if len(lines)>8192:lines.clear();self.error='MCU 行过长'
                        while b'\n' in lines:
                            line,_,tail=lines.partition(b'\n');lines=bytearray(tail)
                            try:
                                obj=json.loads(line);self.event(obj.pop('kind'),obj)
                            except (ValueError,KeyError,TypeError):self.error='忽略无效 MCU 事件行'
            except (OSError,serial.SerialException) as exc:self.error=str(exc)
            finally:
                ser.close()
                with self.lock:
                    if self.serial is ser:self.serial=None;self.port=''
        threading.Thread(target=reader,daemon=True,name='SORT-UART').start()
        return self.snapshot()

    def disconnect(self):
        with self.lock:
            old=self.serial;self.serial=None;self.generation+=1;self.port=''
            self.last_new=0
        if old:old.close()
