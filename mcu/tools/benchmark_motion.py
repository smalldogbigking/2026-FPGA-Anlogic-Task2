"""Compare command timing at all 31 preserved points, no hardware access."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,time
root=Path(__file__).resolve().parents[1]
gcc=os.environ.get('HOST_GCC') or shutil.which('gcc')
if not gcc:raise SystemExit('Set HOST_GCC to a native GCC compiler.')
sources=['tests/motion_benchmark.c','Protocol/motor_control.c','Protocol/pick_cycle.c',
         'Protocol/motion_profile.c','Calibration/calibration.c']
exe=root/'tests/motion_benchmark.exe'
command=[gcc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-misleading-indentation']
command+=['-I'+str(root/p) for p in ('App','Protocol','Calibration','Vision','tests')]
command+=[str(root/p) for p in sources]+['-lm','-o',str(exe)]
subprocess.run(command,cwd=root,check=True)
after=json.loads(subprocess.run([str(exe)],cwd=root,check=True,capture_output=True,text=True).stdout)
before=json.loads((root/'tests/motion_before.json').read_text(encoding='utf-8-sig'))
assert len(after['cycles'])==len(before['cycles'])==62
ratios=[]
for a,b in zip(after['cycles'],before['cycles']):
    assert (a['point'],a['category'])==(b['point'],b['category'])
    assert 0<a['ms']<b['ms'],'A full cycle did not improve'
    ratios.append(1-a['ms']/b['ms'])
report=dict(when=time.strftime('%Y-%m-%dT%H:%M:%S%z'),hardware_tested=False,
            timing_scope='quintic PWM command timeline, excluding vision and batch cooldown',
            baseline_backup='Reference/before_motion_tuning_20261027_173003.zip',
            model_sha256=hashlib.sha256((root/'Calibration/model_data.h').read_bytes()).hexdigest(),
            before=before,after=after,mean_time_reduction_percent=round(100*(1-after['mean_ms']/before['mean_ms']),2),
            per_cycle_reduction_min_percent=round(100*min(ratios),2),per_cycle_reduction_max_percent=round(100*max(ratios),2))
(root/'tests/motion_comparison.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(f"PASS {after['count']} complete simulated cycles; mean {before['mean_ms']/1000:.2f}s -> "
      f"{after['mean_ms']/1000:.2f}s, time reduction {report['mean_time_reduction_percent']:.2f}%; no hardware access.")
