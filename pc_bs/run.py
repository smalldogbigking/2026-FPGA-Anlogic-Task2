"""Start this project's B/S server; never reuse or stop another project's server."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import threading
import urllib.request
import webbrowser
from server_info import ROOT, PROJECT_ID, DEPLOYMENT_ID, SOFTWARE_VERSION

def health(port):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=.5) as response:
            payload = json.load(response)
            return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}

def port_available(port):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as candidate:
            if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
                candidate.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            candidate.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False

def select_endpoint(preferred, scan=20):
    for port in range(preferred, min(65536, preferred + scan)):
        state = health(port)
        if state.get("project_id") == PROJECT_ID and state.get("deployment_id") == DEPLOYMENT_ID:
            if state.get('software_version')!=SOFTWARE_VERSION:
                raise RuntimeError(f"端口{port}运行的是本项目旧服务{state.get('software_version','未知版本')}；请先关闭原服务器窗口，再启动新版{SOFTWARE_VERSION}。重启后重新连接开发板COM口。")
            return port, True
        if not state and port_available(port):
            return port, False
    raise RuntimeError(f"No available port in {preferred}..{min(65535, preferred+scan-1)}")

def main(argv=None):
    parser = argparse.ArgumentParser(description="latest_plus_v3_fixed B/S server "+SOFTWARE_VERSION)
    parser.add_argument("--port", type=int, default=8768)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args(argv)
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    os.chdir(ROOT)
    try:
        port, reuse = select_endpoint(args.port)
    except RuntimeError as exc:
        print(str(exc),flush=True)
        return 2
    url = f"http://127.0.0.1:{port}"
    print(f"Project: {PROJECT_ID}", flush=True)
    print(f"Browser: {url}", flush=True)
    print(f"Files: {ROOT}", flush=True)
    if port != args.port:
        print(f"Port {args.port} is in use. This project uses {port}.", flush=True)
    if reuse:
        print("This project's server is already running.", flush=True)
        if not args.no_browser:
            webbrowser.open(url)
        return 0
    missing = [name for name in ("flask", "serial", "PIL", "numpy", "cv2", "imageio_ffmpeg", "waitress")
               if importlib.util.find_spec(name) is None]
    if missing:
        print("Installing missing dependencies: " + ", ".join(missing), flush=True)
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", str(ROOT / "requirements.txt")])
    def open_ready():
        import time
        for _ in range(80):
            state = health(port)
            if state.get("project_id") == PROJECT_ID and state.get("deployment_id") == DEPLOYMENT_ID:
                webbrowser.open(url)
                return
            time.sleep(.25)
    if not args.no_browser:
        threading.Thread(target=open_ready, daemon=True).start()
    from app import main as serve
    serve(["--port", str(port)])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

