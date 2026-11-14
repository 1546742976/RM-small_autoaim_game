from pathlib import Path
import os, subprocess, hashlib, json, re
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'artifacts/audio-demo';out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP']: env[key]=str(ROOT/'artifacts/runtime'/key.lower())
exe=ROOT/'builds/windows/RMPrecisionLab.exe'
with (out/'stdout.log').open('w') as log:
 result=subprocess.run([str(exe),'--resolution','1280x720','--write-movie',str(out/'capture.avi'),'--fixed-fps','60','--log-file',str(out/'game.log'),'--','--radar-checks','--audio-demo',f'--capture-dir={out}'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW)
text=(out/'game.log').read_text(encoding='utf-8')
assert result.returncode==0 and re.search(r'RADAR PASS: \d+ checks \(0 failures\)',text) and not re.search(r'SCRIPT ERROR|^ERROR:|PROJECTILE FAIL',text,re.M),text
ffmpeg=ROOT/'tools/cache/python/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v9.0.2.exe'
with (out/'encode.log').open('w') as log:
 subprocess.run([str(ffmpeg),'-y','-i',str(out/'capture.avi'),'-c:v','libx264','-crf','22','-pix_fmt','yuv420p','-c:a','aac',str(out/'demo.mp4')],check=True,stdout=log,stderr=subprocess.STDOUT)
with (out/'mix-volume.log').open('w') as log:
 subprocess.run([str(ffmpeg),'-i',str(out/'demo.mp4'),'-vn','-af','volumedetect','-f','null','NUL'],check=True,stdout=log,stderr=subprocess.STDOUT)
volume=(out/'mix-volume.log').read_text(encoding='utf-8',errors='replace')
peak=float(re.search(r'max_volume: ([-0-9.]+) dB',volume).group(1))
assert -70<peak<0,volume
(out/'capture.avi').unlink()
(out/'build.json').write_text(json.dumps({'exe_sha256':hashlib.sha256(exe.read_bytes()).hexdigest()}))
print('AUDIO DEMO PASS')
