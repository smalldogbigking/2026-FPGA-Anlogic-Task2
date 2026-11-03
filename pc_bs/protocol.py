"""FPGA UART wire format; Python does not execute FPGA image algorithms."""
import binascii
import io
import struct
from PIL import Image
from compatibility import FPGA_STATUS_VERSIONS

MAGIC = b"FPG1"
SET, CALIBRATE, PHOTO, FRAME, QUERY, RECENTER = range(1, 7)
ACK, STATUS, VIDEO = 0x81, 0x82, 0x83
LEGACY_MODES = ['RAW', 'GRAY', 'BW', 'NEG', 'SEPIA', 'HEAT', 'SOBEL', 'CARTOON', 'NEON', 'DIGIT', 'MOTION', 'TRACK', 'HAND', 'FACE', 'RESERVE', 'REMOTE']
MODES = ['RAW', 'GRAY', 'NEG', 'SEPIA', 'HEAT', 'SOBEL', 'CARTOON', 'NEON', 'DIGIT', 'MOTION', 'TRACK', 'RESERVE', 'FACE', 'RESERVE', 'RESERVE', 'REMOTE']
V3_MODES = MODES.copy()
V3_MODES[13] = 'SORT'
V3_MODES[3] = 'RAW'
SERVO, OUTPUTS, ISP, PHOTO_ACK = 7,8,9,10
ERRORS = {0: "已接受", 1: "通讯校验失败", 2: "设备忙，请稍后", 3: "参数不正确",
          4: "请将拨码开关设为1100受控模式", 5: "不支持的命令", 6: "未采到完整画面"}

def crc8(data):
    c = 0
    for b in data:
        c ^= b
        for _ in range(8):
            c = ((c << 1) ^ 7) & 255 if c & 128 else (c << 1) & 255
    return c

def command(seq, cmd, a0=0, a1=0, a2=0):
    body = bytes((seq & 255, cmd, a0, a1, a2))
    return b"\xa5\x5a" + body + bytes((crc8(body),))

def reply(kind, seq, payload):
    body = struct.pack("<BBH", kind, seq, len(payload)) + payload
    return MAGIC + body + struct.pack("<H", binascii.crc_hqx(body, 0xffff))

class PacketParser:
    """Bounded buffering, fragmented reads, CRC and stream resynchronisation."""
    def __init__(self):
        self.buffer = bytearray()
        self.bad_packets = 0

    def feed(self, data):
        self.buffer.extend(data)
        if len(self.buffer) > 65536:
            del self.buffer[:-32768]
            self.bad_packets += 1
        packets = []
        while True:
            pos = self.buffer.find(MAGIC)
            if pos < 0:
                if len(self.buffer) > 3:
                    del self.buffer[:-3]
                return packets
            if pos:
                del self.buffer[:pos]
            if len(self.buffer) < 8:
                return packets
            kind, seq, n = struct.unpack_from("<BBH", self.buffer, 4)
            if (kind not in (ACK, STATUS, VIDEO) or n > 20000
                    or (kind == ACK and n != 46) or (kind == STATUS and n != 44)
                    or (kind == VIDEO and n < 51)):
                del self.buffer[0]
                self.bad_packets += 1
                continue
            if len(self.buffer) < 10 + n:
                return packets
            body = bytes(self.buffer[4:8+n])
            if binascii.crc_hqx(body, 0xffff) != struct.unpack_from("<H", self.buffer, 8+n)[0]:
                del self.buffer[0]
                self.bad_packets += 1
                continue
            packets.append((kind, seq, bytes(self.buffer[8:8+n])))
            del self.buffer[:10+n]

def decode_status(raw):
    if len(raw) != 44 or raw[0] not in FPGA_STATUS_VERSIONS:
        raise ValueError("状态协议版本或长度错误")
    flags, packed, mode = raw[3], raw[4], raw[2]
    if mode > 15:
        raise ValueError("非法模式编号")
    u16 = lambda i: raw[i] | raw[i+1] << 8
    sort_active=raw[0]>=5 and mode==13 and raw[7]==6
    return {
        "sort_phase":raw[7] if raw[0]>=5 and mode==13 else None,
        "sort_labels":[{"slot":i,"digit":raw[34+i]&7,"class":(raw[34+i]>>3)&7} for i in range(4)] if sort_active else [],
        "sort_frame":u16(38) if sort_active else None,
        "sort_sequence":u16(40) if sort_active else None,
        "physical_mode": raw[1], "mode": mode, "mode_name": (V3_MODES if raw[0]>=5 else MODES if raw[0]>=3 else LEGACY_MODES)[mode], "protocol_version":raw[0],
        **({"saturation":raw[43]&15,"saturation_override":bool(raw[43]&16)} if raw[0]>=4 else {}),
        "controlled": bool(flags & 1), "lease_alive": bool(flags & 2),
        "calibration_busy": bool(flags & 4), "calibration_valid": bool(flags & 8),
        "photo_pending": bool(flags & 16), "sd_busy": False, "digit_valid": bool(flags & 32),
        "hand_valid": bool(flags & 64), "target_valid": bool(flags & 128),
        "beauty": ["off", "auto", "fixed", "invalid"][packed & 3],
        "quality_index": (packed >> 2) & 3, "fps_index": (packed >> 4) & 3,
        "fps_set": raw[5], "digit": raw[6] if flags & 32 else None,
        "hand": raw[7] if flags & 64 else None, "target_mask": raw[8] & 15,
        "target_count": (raw[8] & 15).bit_count(), "target_shapes": raw[9],
        "target_center": [u16(10), u16(12)] if flags & 128 else None,
        "pan_us": u16(14), "tilt_us": u16(16), "photo_status": raw[18],
        "photo_token": raw[19], "photo_error": raw[42], "mean": raw[20], "gain": raw[21],
        "exposure": u16(22), "wb_r": raw[24], "wb_b": raw[25],
        "source_seq": u16(26), "track_ready": bool(raw[28] & 1),
        "center_seconds": (raw[28] >> 1) & 3, "digit_threshold": raw[29],
        "tone": raw[30], "source_valid": bool(raw[31] & 1),
        "face_valid": bool(raw[32]&1) and not sort_active, "face_confidence":raw[33] if not sort_active else 0,
        "face_box":[u16(34),u16(36),u16(38),u16(40)] if not sort_active else [0,0,0,0],
        "manual_servo":bool(raw[32]&2), "hdmi_show":bool(raw[32]&4),
        "led_blink":bool(raw[32]&8), "alarm":bool(raw[32]&16),
        "wb_override":bool(raw[32]&32), "ae_override":bool(raw[32]&64)
    }

PALETTE = [c for v in range(256) for c in (
    ((v >> 5) & 7)*255//7, ((v >> 2) & 7)*255//7, (v & 3)*255//3)]

def decode_frame(payload):
    if len(payload) < 51:
        raise ValueError("视频头不完整")
    counter, w, h, fmt = struct.unpack_from("<HHHB", payload)
    if fmt != 1 or not 1 <= w <= 320 or not 1 <= h <= 180 or len(payload) != 51+w*h:
        raise ValueError("视频分辨率、像素格式或长度错误")
    image = Image.frombytes("P", (w, h), payload[51:])
    image.putpalette(PALETTE)
    bins = image.convert("L").histogram()
    output = io.BytesIO()
    image=image.resize((w,w*9//16),Image.Resampling.NEAREST)
    image.save(output, format="PNG", compress_level=1)
    return output.getvalue(), {
        "frame_counter": counter, "width": w, "height": h,
        "status": decode_status(payload[7:51]),
        "histogram": [sum(bins[i:i+16]) for i in range(0, 256, 16)]
    }


class FrameAssembler:
    """Assemble strictly ordered strips; publish only complete previews.

    Format2 uses the51-byte base header, row_startLE16, row_count8,
    then width*row_count RGB332 bytes. Strips can span HDMI refreshes.
    Missing/reordered strips discard a partial frame rather than smear it.
    """
    def __init__(self):
        self.key=None
        self.next_row=0
        self.pixels=bytearray()
        self.header=None

    def feed(self, seq, payload):
        if len(payload)<51:raise ValueError("视频头不完整")
        counter,w,h,fmt=struct.unpack_from("<HHHB",payload)
        if fmt==1:return decode_frame(payload)
        if fmt!=2 or len(payload)<54 or not 1<=w<=320 or not 1<=h<=180:
            raise ValueError("分段视频格式错误")
        row,rows=struct.unpack_from("<HB",payload,51)
        if not 1<=rows<=8 or row+rows>h or len(payload)!=54+w*rows:
            raise ValueError("分段视频长度错误")
        key=(seq,counter,w,h)
        if row==0:
            self.key=key;self.next_row=0;self.pixels=bytearray();self.header=payload[:51]
        if key!=self.key or row!=self.next_row:
            self.key=None;self.pixels=bytearray();return None
        self.pixels.extend(payload[54:]);self.next_row+=rows
        if self.next_row<h:return None
        complete=struct.pack("<HHHB",counter,w,h,1)+self.header[7:51]+self.pixels
        self.key=None;self.pixels=bytearray()
        png,info=decode_frame(complete)
        info["segmented"]=True
        return png,info
