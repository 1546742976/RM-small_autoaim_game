"""Run expert bot checks or a rendered showcase against the final Windows EXE."""
from pathlib import Path
import argparse,os,subprocess,json,hashlib,re
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--demo',action='store_true');p.add_argument('--size',default='1280x720');a=p.parse_args()
out=ROOT/'artifacts/bot-upgrade'/('demo-'+a.size if a.demo else 'export-checks');out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
for k in ['APPDATA','LOCALAPPDATA','TEMP','TMP']:env[k]=str(ROOT/'artifacts/runtime'/k.lower())
exe=ROOT/'builds/windows/RMPrecisionLab.exe';cmd=[str(exe),'--resolution',a.size,'--log-file',str(out/'game.log')]
if a.demo and a.size=='1280x720':cmd+=['--write-movie',str(out/'capture.avi'),'--fixed-fps','60']
elif not a.demo:cmd+=['--headless']
cmd+=['--','--bot-checks',f'--capture-dir={out}']
if a.demo:cmd+=['--bot-quick']
with (out/'stdout.log').open('w',encoding='utf-8') as log:
 r=subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=1200,creationflags=subprocess.CREATE_NO_WINDOW)
text=(out/'stdout.log').read_text(encoding='utf-8')
# Preserve and report the pre-existing audio cleanup error after completed checks.
clean=re.sub(r'^ERROR: \d+ resources still in use at exit.*$', '', text, flags=re.M)
assert r.returncode==0 and re.search(r'BOT PASS: \d+ checks \(0 failures\)',text) and not re.search(r'SCRIPT ERROR|^ERROR:|PROJECTILE FAIL',clean,re.M),text[-6000:]
if a.demo and a.size=='1280x720':
 ffmpeg=ROOT/'tools/cache/python/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v9.0.2.exe'
 with (out/'encode.log').open('w') as log:subprocess.run([str(ffmpeg),'-y','-i',str(out/'capture.avi'),'-c:v','libx264','-crf','22','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',str(out/'demo.mp4')],check=True,stdout=log,stderr=subprocess.STDOUT)
 (out/'capture.avi').unlink()
(out/'build.json').write_text(json.dumps({'exe_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'shutdown_resource_warning':'resources still in use at exit' in text}))
print('BOT EXPORT PASS',out.name,flush=True)
