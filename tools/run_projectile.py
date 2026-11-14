"""Run projectile/vertical-map checks on the actual source or exported game."""
from pathlib import Path
import argparse, os, subprocess, re, json, hashlib, time
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--mode',choices=['checks','demo','benchmark','radar'],default='checks')
p.add_argument('--size',default='1280x720')
p.add_argument('--export',action='store_true')
p.add_argument('--headless',action='store_true')
a=p.parse_args()
if a.headless and a.mode=='benchmark': p.error('Performance requires rendered frames')
out=ROOT/('artifacts/radar' if a.mode=='radar' else 'artifacts/projectile')/f'{a.mode}-{a.size}{"-headless" if a.headless else ""}'
out.mkdir(parents=True,exist_ok=True)
engine=ROOT/'builds/windows/RMPrecisionLab.exe' if a.export else Path(r'D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')
env=os.environ.copy()
for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP']:
    dest=ROOT/'artifacts/runtime'/key.lower();dest.mkdir(parents=True,exist_ok=True);env[key]=str(dest)
cmd=[str(engine)]
if not a.export: cmd+=['--path',str(ROOT/'射击游戏')]
cmd+=['--resolution',a.size,'--position','40,40','--log-file',str(out/'game.log')]
if a.headless: cmd+=['--headless']
if a.mode=='demo': cmd+=['--write-movie',str(out/'capture.avi'),'--fixed-fps','60']
cmd+=['--',('--radar-checks' if a.mode=='radar' else '--projectile-'+a.mode),f'--capture-dir={out}']
(out/'game.log').write_text('',encoding='utf-8')
with (out/'stdout.log').open('w',encoding='utf-8') as log:
    process=subprocess.Popen(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        deadline=time.monotonic()+900
        while process.poll() is None:
            time.sleep(.4)
            text=(out/'game.log').read_text(encoding='utf-8',errors='replace')+(out/'stdout.log').read_text(encoding='utf-8',errors='replace')
            if re.search(r'SCRIPT ERROR:|^ERROR:',text,re.M) or time.monotonic()>deadline: raise RuntimeError(text[-5000:])
    finally:
        if process.poll() is None: process.terminate();process.wait()
text=(out/'game.log').read_text(encoding='utf-8',errors='replace')+(out/'stdout.log').read_text(encoding='utf-8',errors='replace')
assert process.returncode==0 and re.search(r'(PROJECTILE|RADAR) PASS: \d+ checks \(0 failures\)',text) and 'PROJECTILE FAIL' not in text,text[-5000:]
if a.mode=='demo':
    ffmpeg=ROOT/'tools/cache/python/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v9.0.2.exe'
    with (out/'encode.log').open('w') as log:
        subprocess.run([str(ffmpeg),'-y','-i',str(out/'capture.avi'),'-c:v','libx264','-crf','22','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',str(out/'demo.mp4')],stdout=log,stderr=subprocess.STDOUT,check=True)
    (out/'capture.avi').unlink()
if a.export:(out/'build.json').write_text(json.dumps({'exe_sha256':hashlib.sha256(engine.read_bytes()).hexdigest()}),encoding='utf-8')
print('PASS',out.name,flush=True)
