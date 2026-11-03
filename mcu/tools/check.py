"""Native C fault-injection tests; no serial port, board or programmer access."""
from pathlib import Path
import subprocess,os,shutil,json,hashlib,time
root=Path(__file__).resolve().parents[1]
gcc=os.environ.get('HOST_GCC') or shutil.which('gcc')
if not gcc:raise SystemExit('Set HOST_GCC to a native GCC compiler.')
project=json.loads((root/'Reference/3fdb98897f6644758688d60778e46ede.json').read_text(encoding='utf-8-sig'))
points=project['points']
assert len(points)==31 and all(p['source']=='hardware' and p['xyz'][2]==0 for p in points)
header='/* Generated solely from preserved real calibration JSON, no synthetic replacement. */\n'
header+='static const float reference_xyz[][3]={'+','.join('{'+','.join(f'{float(x):.8f}f' for x in p['xyz'])+'}' for p in points)+'};\n'
header+='static const uint16_t reference_pwm[][4]={'+','.join('{'+','.join(map(str,p['pwm_us']))+'}' for p in points)+'};\n'
(root/'tests/calibration_samples.h').write_text(header,encoding='utf-8')
sources=['tests/test_robot.c','Vision/vision_protocol.c','Vision/pixel_map.c','Vision/robot_control.c',
         'Protocol/motor_control.c','Protocol/pick_cycle.c','Protocol/motion_profile.c','Calibration/calibration.c','Display/robot_display.c']
command=[gcc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-misleading-indentation']
command += ['-I'+str(root/p) for p in ('App','Protocol','Calibration','Vision','Display')]
command += [str(root/p) for p in sources]+['-lm','-o',str(root/'tests/test_robot.exe')]
subprocess.run(command,cwd=root,check=True)
result=subprocess.run([str(root/'tests/test_robot.exe')],cwd=root,capture_output=True,text=True)
print(result.stdout,end='');print(result.stderr,end='')
(root/'tests/native_results.log').write_text(result.stdout+result.stderr,encoding='utf-8')
if result.returncode:raise SystemExit(result.returncode)
report=dict(native_pass=True,when=time.strftime('%Y-%m-%dT%H:%M:%S%z'),evidence=result.stdout.strip(),hardware_tested=False)
(root/'tests/results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
try:
    from PIL import Image
    for p in (root/'tests').glob('oled_*.pgm'):
        with Image.open(p) as im:im.resize((768,384),Image.Resampling.NEAREST).save(p.with_suffix('.png'))
except ImportError:pass
