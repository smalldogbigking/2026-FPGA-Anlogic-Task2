"""Compile only. Never invokes a programmer or opens a serial port."""
from pathlib import Path
import subprocess,sys,time,re,json,hashlib,shutil,os
root=Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,str(root/'tools/check_download.py')],cwd=root,check=True)
uv=Path(os.environ.get('KEIL_UV4',shutil.which('UV4.exe') or 'UV4.exe'))
if not uv.is_file():raise SystemExit('Set KEIL_UV4 to your Keil UV4.exe path.')
log=root/'tests'/'keil_build.log'
if log.exists():log.unlink()
result=subprocess.run([str(uv),'-r',str(root/'MDK-ARM'/'RobotArmControl.uvprojx'),'-o',str(log)],cwd=root)
# Some uVision installations rewrite PackID, nTsel and capability fields.
# Deliver the user's original download configuration, then verify it again.
subprocess.run([sys.executable,str(root/'tools/check_download.py'),'--restore'],cwd=root,check=True)
text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else ''
print(text)
if result.returncode!=0 or not re.search(r'0 Error\(s\), 0 Warning\(s\)',text):raise SystemExit('Keil build has errors or warnings.')
match=re.search(r'Program Size: Code=(\d+) RO-data=(\d+) RW-data=(\d+) ZI-data=(\d+)',text)
if not match:raise SystemExit('Missing memory usage evidence.')
code,ro,rw,zi=map(int,match.groups())
hexfile=root/'MDK-ARM'/'Objects'/'robot_arm_control.hex'
if not hexfile.is_file():raise SystemExit('Missing new HEX.')
upper=0;flash={}
for line in hexfile.read_text().splitlines():
    raw=bytes.fromhex(line[1:]);n=int(raw[0]);address=int.from_bytes(raw[1:3],'big');kind=raw[3]
    if sum(raw)&255:raise SystemExit('HEX checksum failed.')
    if kind==4:upper=int.from_bytes(raw[4:6],'big')<<16
    if kind==0:
        for i,b in enumerate(raw[4:4+n]):flash[upper+address+i]=b
if not flash or min(flash)!=0x08000000 or max(flash)>=0x08010000:raise SystemExit('HEX exceeds the STM32F103C8 64KB flash region.')
if rw+zi>20480:raise SystemExit('RAM exceeds 20KB.')
out=root/'firmware';out.mkdir(exist_ok=True)
shutil.copy2(hexfile,out/'robot_arm_control.hex')
source_files=[]
for folder in ('App','Core','Drivers','Calibration','Protocol','Vision','Display'):
    source_files += [p for p in (root/folder).rglob('*') if p.is_file() and p.suffix.lower() in ('.c','.h','.s')]
source_files += [root/'MDK-ARM/RobotArmControl.uvprojx',root/'MDK-ARM/RobotArmControl.uvoptx']
(out/'source_hashes.json').write_text(json.dumps({p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                                               for p in sorted(source_files)},indent=2),encoding='utf-8')
report=dict(compiler_exit=result.returncode,code=code,ro_data=ro,rw_data=rw,zi_data=zi,flash_limit=65536,ram_limit=20480,
            download_configuration_identical_to_original=True,
            flash_image_span=max(flash)-min(flash)+1,ram_total=rw+zi,hex_sha256=hashlib.sha256(hexfile.read_bytes()).hexdigest(),
            built_local=time.strftime('%Y-%m-%dT%H:%M:%S%z'),downloaded=False,hardware_tested=False)
(out/'build_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
