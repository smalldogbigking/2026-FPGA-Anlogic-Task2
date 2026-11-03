"""496 four-object command timelines; no hardware or serial access."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,time
root=Path(__file__).resolve().parents[1]
gcc=os.environ.get('HOST_GCC') or shutil.which('gcc')
if not gcc:raise SystemExit('Set HOST_GCC to a native GCC compiler.')
sources=['tests/continuous_benchmark.c','Protocol/motor_control.c','Protocol/pick_cycle.c',
         'Protocol/motion_profile.c','Calibration/calibration.c']
exe=root/'tests/continuous_benchmark.exe'
command=[gcc,'-std=c11','-O2','-Wall','-Wextra','-Werror','-Wno-misleading-indentation']
command+=['-I'+str(root/p) for p in ('App','Protocol','Calibration','Vision','tests')]
command+=[str(root/p) for p in sources]+['-lm','-o',str(exe)]
subprocess.run(command,cwd=root,check=True)
after=json.loads(subprocess.run([str(exe)],cwd=root,check=True,capture_output=True,text=True).stdout)
before=json.loads((root/'tests/continuous_before.json').read_text(encoding='utf-8-sig'))
assert len(after['batches'])==len(before['batches'])==496
ratios=[]
for a,b in zip(after['batches'],before['batches']):
    assert (a['start'],a['pattern'])==(b['start'],b['pattern'])
    assert 0<a['ms']<b['ms'],'A full four-object batch did not improve'
    ratios.append(1-a['ms']/b['ms'])
report=dict(when=time.strftime('%Y-%m-%dT%H:%M:%S%z'),hardware_tested=False,
            scope='four picks and drops, including final closed-home return; excluding vision/cooldown',
            baseline_backup='Reference/before_continuous_batch_20261028_231320.zip',
            model_sha256=hashlib.sha256((root/'Calibration/model_data.h').read_bytes()).hexdigest(),
            before=before,after=after,
            mean_time_reduction_percent=round(100*(1-after['mean_batch_ms']/before['mean_batch_ms']),2),
            per_batch_reduction_min_percent=round(100*min(ratios),2),per_batch_reduction_max_percent=round(100*max(ratios),2))
(root/'tests/continuous_comparison.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(f"PASS 496 four-object simulated batches (1984 picks), all handoffs raised/open; mean "
      f"{before['mean_batch_ms']/1000:.2f}s -> {after['mean_batch_ms']/1000:.2f}s, "
      f"time reduction {report['mean_time_reduction_percent']:.2f}%; no hardware access.")
