"""Local B/S UI and USB bridge; image recognition remains on the FPGA."""
import argparse
import functools
import io
import re
import atexit
import uuid
import json
from pathlib import Path
from flask import Flask, request, jsonify, send_file
from board_link import BoardLink, BoardError
from protocol import CALIBRATE, PHOTO, RECENTER
from server_info import identity

ISP_LIMITS = {"wb_r": (40, 96), "wb_b": (40, 96), "exposure": (4, 1991), "gain": (16, 80), "saturation": (0, 8)}

def create_app(link=None):
    app = Flask(__name__, static_folder="static")
    app.config.update(MAX_CONTENT_LENGTH=2048)
    board = link if link is not None else BoardLink()
    app.extensions["board"] = board
    if hasattr(board,'stop'):
        atexit.register(board.stop)

    def guarded(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            if request.method == "POST" and not request.is_json:
                return jsonify(error="需要JSON请求"), 415
            if request.method == "POST" and not isinstance(request.get_json(silent=True), dict):
                return jsonify(error="需要JSON对象"), 400
            return fn(*args, **kwargs)
        return wrapper

    @app.get("/")
    def index():
        return app.send_static_file("index.html")

    @app.get('/sort')
    def sort_page():return app.send_static_file('sort.html')

    @app.get('/api/sort/status')
    def sort_status():
        if not hasattr(board,'sort'):return jsonify(error='无 SORT 接口'),503
        return jsonify(**board.sort.snapshot(),board=board.snapshot()['status'])

    @app.post('/api/sort/connect')
    @guarded
    def sort_connect():
        b=request.get_json();port=b.get('port','')
        if not isinstance(port,str) or not re.fullmatch(r'COM[1-9]\d{0,3}',port):return jsonify(error='请选择 COM 口'),400
        if port==getattr(board,'port',None):return jsonify(error='此端口用于 FPGA 视频，请选择额外的 SORT/MCU 串口'),409
        try:return jsonify(ok=True,result=board.sort.connect(port,b.get('kind','vision')))
        except (ValueError,OSError) as exc:return jsonify(error=str(exc)),409

    @app.post('/api/sort/disconnect')
    @guarded
    def sort_disconnect():board.sort.disconnect();return jsonify(ok=True)

    @app.get("/api/ports")
    @guarded
    def ports():
        return jsonify(ports=board.ports())

    @app.get("/api/status")
    @guarded
    def status():
        data = board.snapshot()
        data.update(identity())
        data["isp_limits"] = ISP_LIMITS
        data["isp_normalized"] = {
            name: round(100 * (data["status"][name] - lo) / (hi - lo), 1)
            for name, (lo, hi) in ISP_LIMITS.items() if name in data["status"]
        }
        return jsonify(data)

    @app.get("/api/frame")
    @guarded
    def frame():
        with board.lock:
            image = board.frame
        if image is None:
            return jsonify(error="还没有收到开发板画面"), 404
        return send_file(io.BytesIO(image), mimetype="image/png", max_age=0)

    @app.get('/api/health')
    def health():
        return jsonify(ok=True,api_version=1,**identity())

    @app.get('/download/android.apk')
    def android_download():
        release=Path(__file__).resolve().parents[1]/'android/releases'
        path=release/'FPGA-Vision.apk'
        name='Anlogic-Vision.apk'
        try:
            info=json.loads((release/'release.json').read_text(encoding='utf-8-sig'))
            candidate=info['versioned_file']
            if Path(candidate).name==candidate and (release/candidate).is_file():
                path=release/candidate;name=candidate
        except (OSError,ValueError,KeyError,TypeError):pass
        if not path.is_file():return jsonify(error='安装包尚未生成'),404
        return send_file(path,as_attachment=True,mimetype='application/vnd.android.package-archive',download_name=name)

    @app.get('/api/events')
    @guarded
    def events():
        try:
            limit=max(1,min(100,int(request.args.get('limit',50))))
            before=float(request.args['before']) if 'before' in request.args else None
        except ValueError:return jsonify(error='事件分页参数错误'),400
        engine=board.media.events
        return jsonify(events=engine.store.events(limit,before),monitor=engine.status())

    @app.post('/api/events/settings')
    @guarded
    def event_settings():
        enabled=request.get_json().get('enabled')
        if type(enabled) is not bool:return jsonify(error='enabled 必须为布尔值'),400
        board.media.events.set_enabled(enabled)
        return jsonify(ok=True,monitor=board.media.events.status())

    @app.get('/api/events/<event_id>')
    @guarded
    def event_detail(event_id):
        try:return jsonify(event=board.media.events.store.get(event_id))
        except ValueError as exc:return jsonify(error=str(exc)),404

    @app.get('/api/events/<event_id>/<asset>')
    @guarded
    def event_asset(event_id,asset):
        engine=board.media.events
        try:
            event=engine.store.get(event_id)
            if asset not in ('video','thumbnail','metadata','timeline'):raise ValueError('文件类型错误')
            if asset=='video' and event['state']!='completed':raise ValueError('录像尚未保存完成')
            names={'video':event.get('video'),'thumbnail':event.get('thumbnail'),
                   'metadata':event['id']+'.json','timeline':(event.get('video') or '')+'.jsonl'}
            name=names[asset]
            if not name or Path(name).name!=name:raise ValueError('文件不存在')
            path=engine.root/name
            if not path.is_file():raise ValueError('文件不存在')
            return send_file(path,mimetype={'video':'video/mp4','thumbnail':'image/jpeg',
                'metadata':'application/json','timeline':'application/x-ndjson'}[asset],
                as_attachment=asset in ('metadata','timeline') or request.args.get('download')=='1',conditional=True)
        except ValueError as exc:return jsonify(error=str(exc)),404

    @app.get('/api/notifications')
    @guarded
    def notifications():
        try:
            after=max(0,int(request.args.get('after',0)))
            wait=max(0,min(20,float(request.args.get('wait',0))))
            limit=max(1,min(100,int(request.args.get('limit',50))))
        except ValueError:return jsonify(error='通知参数错误'),400
        store=board.media.events.store
        return jsonify(store.recent(limit) if request.args.get('recent')=='1' else store.notifications(after,wait,limit))

    @app.post('/api/notifications/read')
    @guarded
    def notification_read():
        upto=request.get_json().get('upto')
        if type(upto) is not int or upto<0:return jsonify(error='通知编号错误'),400
        board.media.events.store.read(upto)
        return jsonify(ok=True)

    @app.post('/api/notifications/test')
    @guarded
    def notification_test():
        board.media.events.store.notify('test_'+uuid.uuid4().hex,'test','消息通知测试','电脑与手机消息通道工作正常')
        return jsonify(ok=True)

    @app.post("/api/connect")
    @guarded
    def connect():
        port = (request.get_json() or {}).get("port", "")
        if not isinstance(port, str) or not re.fullmatch(r"COM[1-9]\d{0,3}", port):
            return jsonify(error="请从串口列表选择开发板COM端口"), 400
        try:
            return jsonify(ok=True, result=board.connect(port))
        except (BoardError, OSError) as exc:
            return jsonify(error=str(exc)), 409

    @app.post("/api/disconnect")
    @guarded
    def disconnect():
        board.disconnect()
        return jsonify(ok=True)

    @app.post("/api/config")
    @guarded
    def configure():
        body = request.get_json() or {}
        try:
            result = board.configure(body.get("mode"), body.get("beauty"),
                                     body.get("quality"), body.get("fps"))
            return jsonify(ok=True, result=result, message="已接受，下一帧生效")
        except BoardError as exc:
            return jsonify(error=str(exc)), 409

    @app.post("/api/action")
    @guarded
    def action():
        name = (request.get_json() or {}).get("action")
        cmd = {"calibrate": CALIBRATE, "photo": PHOTO, "recenter": RECENTER}.get(name)
        if cmd is None:
            return jsonify(error="不支持的操作"), 400
        if cmd == RECENTER and board.snapshot()["status"].get("mode") not in ((10,12) if board.snapshot()["status"].get("protocol_version",2)>=3 else (11,13)):
            return jsonify(error="请先切换到TRACK，再让云台归中"), 409
        try:
            result = board.request(cmd)
            return jsonify(ok=True, result=result, message="已接受；完成状态由开发板反馈")
        except BoardError as exc:
            return jsonify(error=str(exc)), 409

    @app.post("/api/preview")
    @guarded
    def preview():
        body = request.get_json() or {}
        enabled, fps = body.get("enabled"), body.get("fps", 4)
        if type(enabled) is not bool or type(fps) is not int or fps not in (1, 2, 4, 6):
            return jsonify(error="预览目标支持1、2、4、6帧/秒，实际受串口带宽限制"), 400
        detail=body.get("detail",0)
        if type(detail) is not int or detail not in (0,1):return jsonify(error="画质档错误"),400
        with board.lock:
            board.preview_enabled, board.preview_fps, board.preview_detail = enabled, fps, detail
        return jsonify(ok=True)

    @app.post("/api/servo")
    @guarded
    def servo():
        b=request.get_json()
        try:return jsonify(ok=True,result=board.servo(b.get('pan'),b.get('tilt')))
        except BoardError as exc:return jsonify(error=str(exc)),409

    @app.post("/api/outputs")
    @guarded
    def outputs():
        b=request.get_json()
        try:return jsonify(ok=True,result=board.outputs(b.get('show'),b.get('led'),b.get('alarm')))
        except BoardError as exc:return jsonify(error=str(exc)),409

    @app.post("/api/isp")
    @guarded
    def isp():
        b=request.get_json()
        name, value = b.get('name'), b.get('value')
        if 'normalized' in b:
            normalized = b['normalized']
            if name not in ISP_LIMITS or type(normalized) not in (int, float) or not 0 <= normalized <= 100:
                return jsonify(error='标准化参数范围0—100'),400
            lo, hi = ISP_LIMITS[name]
            value = round(lo + normalized * (hi - lo) / 100)
        try:return jsonify(ok=True,result=board.isp(name,value),raw_value=value)
        except BoardError as exc:return jsonify(error=str(exc)),409

    @app.post("/api/media")
    @guarded
    def media():
        b=request.get_json();action=b.get('action')
        try:
            with board.lock:png=board.frame
            if action=='photo':name=board.media.photo(png)
            elif action=='record':name=board.media.start(png,board.preview_fps)
            elif action=='stop':name=board.media.stop()
            elif action=='faces':
                if type(b.get('enabled')) is not bool:return jsonify(error='参数错误'),400
                board.media.face_auto=b['enabled'];name=None
            else:return jsonify(error='未知操作'),400
            return jsonify(ok=True,name=name,media=board.media.status())
        except (ValueError,OSError) as exc:return jsonify(error=str(exc)),409

    @app.get("/api/files/<name>")
    @guarded
    def download(name):
        try:return send_file(board.media.path(name),as_attachment=True)
        except ValueError as exc:return jsonify(error=str(exc)),404

    @app.after_request
    def response_headers(response):
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; img-src 'self' data: blob:; style-src 'self'; "
            "script-src 'self'; frame-ancestors 'none'")
        return response
    return app

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8768)
    args = parser.parse_args(argv)
    app = create_app()
    print("打开 http://127.0.0.1:"+str(args.port), flush=True)
    print("直接访问，无需访问码。", flush=True)
    print("外部远程入口请自行配置，映射到当前服务端口。", flush=True)
    print("板卡USB连接后选择COM端口；拨码1100为电脑控制，独立TRACK为1001，人脸1010。", flush=True)
    from waitress import serve
    try:serve(app,host='127.0.0.1',port=args.port,threads=16)
    finally:app.extensions['board'].stop()

if __name__ == "__main__":
    main()
