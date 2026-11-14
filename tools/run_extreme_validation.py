from pathlib import Path
import os,subprocess,re,json,hashlib
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'artifacts/extreme-bot/export-checks';out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
for k in ['APPDATA','LOCALAPPDATA','TEMP','TMP']:env[k]=str(ROOT/'artifacts/runtime'/k.lower())
exe=ROOT/'builds/windows/RMPrecisionLab.exe'
with (out/'stdout.log').open('w',encoding='utf-8') as log:
 r=subprocess.run([str(exe),'--headless','--log-file',str(out/'game.log'),'--','--extreme-checks',f'--capture-dir={out}'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW)
text=(out/'stdout.log').read_text(encoding='utf-8');clean=re.sub(r'^ERROR: \d+ resources still in use at exit.*$', '', text, flags=re.M)
assert r.returncode==0 and re.search(r'EXTREME PASS: \d+ checks \(0 failures\)',text) and not re.search(r'SCRIPT ERROR|^ERROR:|PROJECTILE FAIL',clean,re.M),text
(out/'build.json').write_text(json.dumps({'exe_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'shutdown_resource_warning':'resources still in use at exit' in text}))
print('EXTREME EXPORT PASS')
