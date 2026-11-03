"""One serial owner; all browsers share one low-rate, cached hardware preview."""
import threading
import time
import serial
import serial.tools.list_ports
from protocol import (PacketParser, FrameAssembler, command, decode_status, decode_frame,
                      ACK, STATUS, SET, FRAME, QUERY, ERRORS, SERVO, OUTPUTS, ISP, PHOTO_ACK)
from media_store import MediaStore
from sort_link import SortLink
from compatibility import FPGA_CONTROL_VERSIONS

class BoardError(RuntimeError):
    pass

class BoardLink:
    def __init__(self):
        self.media=MediaStore()
        self.sort=SortLink(self.media)
        self.photo_saved_token=None
        self.photo_ack_queue=None
        self.lock = threading.RLock()
        self.command_lock = threading.Lock()
        self.isp_lock = threading.Lock()
        self.serial = None
        self.generation = self.seq = 0
        self.pending = {}
        self.parser = PacketParser()
        self.status = {}
        self.frame = None
        self.frame_info = {}
        self.frame_version = self.received = 0
        self.last_frame_time = self.last_status_time = 0.
        self.error = self.port = ""
        self.preview_enabled = True
        self.preview_fps = 4
        self.preview_detail = 0
        self.closed = False
        self.capture_wait_until = 0.
        threading.Thread(target=self._poll, daemon=True, name="FPGA-poll").start()

    @staticmethod
    def ports():
        return [{"port": p.device, "description": p.description}
                for p in serial.tools.list_ports.comports()]

    def connect(self, port, transport=None):
        self.disconnect()
        with self.command_lock:
            ser = transport if transport is not None else serial.Serial(
                port, 921600, timeout=.05, write_timeout=1,
                xonxoff=False, rtscts=False, dsrdtr=False)
            with self.lock:
                self.generation += 1
                generation = self.generation
                self.serial, self.port = ser, port
                self.status, self.pending, self.frame_info = {}, {}, {}
                self.photo_saved_token=None;self.photo_ack_queue=None
                self.frame = None
                self.frame_version = self.received = 0
                self.last_frame_time = self.capture_wait_until = 0.
                self.parser = PacketParser()
                self.error = ""
            threading.Thread(target=self._reader, args=(ser, generation, self.parser),
                             daemon=True, name="FPGA-rx").start()
        try:
            return self.request(QUERY)
        except BoardError:
            self.disconnect()
            raise

    def disconnect(self):
        with self.lock:
            old = self.serial
            self.serial = None
            self.generation += 1
            self.port = ""
            self.status = {}
            self.media.events.disconnected()
            self.media.stop()
            for record in self.pending.values():
                record["error"] = "连接已关闭"
                record["event"].set()
            self.pending = {}
            self.frame, self.frame_info = None, {}
            self.last_frame_time = 0.
        if old:
            try:
                old.close()
            except Exception:
                pass

    def request(self, cmd, a0=0, a1=0, a2=0, *, opportunistic=False):
        if not self.command_lock.acquire(blocking=not opportunistic):
            return None
        try:
            with self.lock:
                ser = self.serial
                if ser is None:
                    raise BoardError("未连接开发板串口")
                self.seq = (self.seq+1) & 255
                seq = self.seq
                record = {"event": threading.Event(), "response": None, "error": None}
                self.pending[seq] = record
            packet = command(seq, cmd, a0, a1, a2)
            try:
                for _ in range(2):
                    ser.write(packet)
                    if record["event"].wait(1.5):
                        if record["error"]:
                            raise BoardError(record["error"])
                        response = record["response"]
                        if response["code"]:
                            raise BoardError(ERRORS.get(response["code"], "设备错误"))
                        return response
                raise BoardError("开发板未应答：确认新bit、USB串口和921600波特率")
            finally:
                with self.lock:
                    self.pending.pop(seq, None)
        except (serial.SerialException, serial.SerialTimeoutException, OSError) as exc:
            raise BoardError(str(exc)) from exc
        finally:
            self.command_lock.release()

    def configure(self, mode, beauty, quality, fps):
        version=self.status.get("protocol_version")
        if version not in FPGA_CONTROL_VERSIONS:
            raise BoardError("当前控制软件支持USB协议3/4/5；latest_plus_v3_fixed应上报协议5，请检查所连串口和bit版本")
        if type(mode) is not int or not 0 <= mode <= 14:
            raise BoardError("模式必须为0到14")
        if mode==13 and version<5:
            raise BoardError("智能分拣SORT需要latest_plus_v3_fixed的USB协议5")
        if beauty not in ("off", "auto", "fixed"):
            raise BoardError("美化模式错误")
        if type(quality) is not int or quality not in (0, 1, 2):
            raise BoardError("画质档错误")
        if type(fps) is not int or fps not in (60, 30, 15):
            raise BoardError("帧率档错误")
        b = {"off": 0, "auto": 1, "fixed": 2}[beauty]
        f = {60: 0, 30: 1, 15: 2}[fps]
        return self.request(SET, mode, b, quality | f << 2)

    def servo(self, pan, tilt):
        if type(pan) is not int or type(tilt) is not int or not (1000<=pan<=2000 and 1000<=tilt<=2000):
            raise BoardError("云台脉宽范围1000—2000微秒")
        bits=pan|(tilt<<11)
        return self.request(SERVO,bits&255,(bits>>8)&255,(bits>>16)&255)

    def outputs(self, show, led, alarm):
        if any(type(v) is not bool for v in (show,led,alarm)):raise BoardError("输出开关必须为布尔值")
        return self.request(OUTPUTS,int(show)|int(led)<<1|int(alarm)<<2)

    def isp(self, name, value):
        limits={'auto':(0,0,0),'wb_r':(1,40,96),'wb_b':(2,40,96),'exposure':(3,4,1991),'gain':(4,16,80),'saturation':(5,0,8)}
        if name=='saturation' and self.status.get('protocol_version',0)<4:
            raise BoardError('饱和度调节需要USB协议4或5，当前配套为latest_plus_v3_fixed协议5')
        if name not in limits:raise BoardError("未知校正参数")
        code,lo,hi=limits[name]
        if type(value) is not int or not lo<=value<=hi:raise BoardError("校正参数超出范围")
        # FPGA has one shared exposure+gain override. Its inactive shadow gain
        # defaults to 48, so setting exposure alone used to lower an AUTO gain
        # of 80. Read actual sensor feedback and seed the companion parameter
        # before applying the requested setting. Serialize ISP edits as a pair.
        with self.isp_lock:
            if name in ('exposure','gain'):
                self.request(QUERY)
                with self.lock:
                    companion_name = 'gain' if name == 'exposure' else 'exposure'
                    companion_value = self.status.get(companion_name)
                companion_code, companion_lo, companion_hi = limits[companion_name]
                if type(companion_value) is not int or not companion_lo <= companion_value <= companion_hi:
                    raise BoardError('尚未收到有效曝光/增益回传，请稍后重试')
                self.request(ISP,companion_code,companion_value&255,companion_value>>8)
            return self.request(ISP,code,value&255,value>>8)

    def _reader(self, ser, generation, parser):
        assembler=FrameAssembler()
        try:
            while True:
                with self.lock:
                    if self.serial is not ser or generation != self.generation:
                        return
                data = ser.read(4096)
                if not data:
                    continue
                for kind, seq, payload in parser.feed(data):
                    now = time.monotonic()
                    response = None
                    if kind == ACK:
                        state = decode_status(payload[2:])
                        response = {"cmd": payload[0], "code": payload[1], "status": state}
                    elif kind == STATUS:
                        state = decode_status(payload)
                        response = {"cmd": QUERY, "code": 0, "status": state}
                    else:
                        result = assembler.feed(seq,payload)
                        if result is None:continue
                        png, info = result
                        state = info["status"]
                        self.media.accept(png,info,self.preview_fps)
                        self.sort.board_frame(png,info)
                        if state.get('photo_pending'):
                            token=state['photo_token']
                            try:
                                if token!=self.photo_saved_token:
                                    self.media.photo(png);self.photo_saved_token=token
                                self.photo_ack_queue=(token,1)
                            except OSError:
                                self.photo_ack_queue=(token,0)
                        with self.lock:
                            if generation != self.generation:
                                return
                            self.frame, self.frame_info = png, info
                            self.frame_version += 1
                            self.received += 1
                            self.last_frame_time = now
                            self.capture_wait_until = 0.
                    with self.lock:
                        if generation != self.generation:
                            return
                        if kind in (ACK,STATUS):
                            # Only current, still-connected status extends a face event.
                            self.media.events.observe(state)
                        self.status, self.last_status_time = state, now
                        if response is None or response["code"] == 0:
                            self.error = ""
                        if response:
                            record = self.pending.get(seq)
                            if record:
                                record["response"] = response
                                record["event"].set()
        except (ValueError, serial.SerialException, OSError) as exc:
            with self.lock:
                if generation != self.generation:
                    return
                self.error = str(exc)
                for record in self.pending.values():
                    record["error"] = "串口接收中断："+str(exc)
                    record["event"].set()
                self.serial, self.port = None, ""
            self.media.events.disconnected()
            try:
                ser.close()
            except Exception:
                pass

    def _poll(self):
        next_preview = next_query = 0.
        while not self.closed:
            time.sleep(.01)
            with self.lock:
                connected = self.serial is not None
                # Auto face recording works even when the browser is closed or
                # its preview checkbox is off. Capture preview frames in FACE
                # mode and throughout an active event; never change the FPGA.
                event_state=self.media.events.status()
                event_capture=event_state['enabled'] and (self.status.get('mode')==12 or (self.status.get('mode')==13 and self.status.get('sort_phase') in (1,2,3)) or bool(event_state['active']))
                preview, fps, detail = self.preview_enabled or event_capture, self.preview_fps, self.preview_detail
                sd_busy = self.status.get("sd_busy", False)
                awaiting = time.monotonic() < self.capture_wait_until
            if not connected:
                continue
            now = time.monotonic()
            try:
                if self.photo_ack_queue is not None:
                    token,ok=self.photo_ack_queue
                    answer=self.request(PHOTO_ACK,token,ok,opportunistic=True)
                    if answer is not None:self.photo_ack_queue=None
                elif (preview or self.status.get('photo_pending')) and not sd_busy and not awaiting and now >= next_preview:
                    # Reserve before sending; a fast reply cannot reintroduce a stale wait.
                    with self.lock:
                        self.capture_wait_until = now+6.
                    answer = self.request(FRAME, detail if self.status.get("protocol_version",2)>=3 else 0, opportunistic=True)
                    if answer is None:
                        with self.lock:
                            self.capture_wait_until = 0.
                    next_preview = now+1/max(1, fps)
                elif now >= next_query:
                    self.request(QUERY, opportunistic=True)
                    next_query = now+1.
            except BoardError as exc:
                with self.lock:
                    self.error = str(exc)
                    if "设备忙" in str(exc):
                        self.capture_wait_until = 0.
                next_preview, next_query = now+.5, now+1.

    def snapshot(self):
        with self.lock:
            age = round(time.monotonic()-self.last_frame_time, 2) if self.last_frame_time else None
            return {
                "connected": self.serial is not None, "port": self.port, "baud": 921600,
                "status": dict(self.status), "error": self.error,
                "frame_version": self.frame_version, "frame_age": age,
                "preview_enabled": self.preview_enabled, "preview_fps": self.preview_fps, "preview_detail":self.preview_detail,
                "received_frames": self.received, "bad_packets": self.parser.bad_packets,
                "histogram": self.frame_info.get("histogram", []),
                "preview_width": self.frame_info.get("width", 160),
                "preview_height": self.frame_info.get("height", 90),
                "media": self.media.status()
            }

    def stop(self):
        self.closed = True
        self.sort.disconnect()
        self.media.close()
        self.disconnect()
