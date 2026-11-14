"""Package the focused CS2-inspired original-audio update with honest evidence scope."""
from pathlib import Path
import hashlib,json,re,shutil,zipfile
ROOT=Path(__file__).resolve().parents[1]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 out=ROOT/'builds/windows';a=ROOT/'artifacts/cs2-audio';sha=digest(out/'RMPrecisionLab.exe')
 for folder in [ROOT/'artifacts/audio-demo',ROOT/'artifacts/radar/radar-1280x720']:
  assert json.loads((folder/'build.json').read_text())['exe_sha256']==sha
  for p in folder.glob('*.log'):assert not re.search(r'SCRIPT ERROR|^ERROR:|PROJECTILE FAIL',p.read_text(encoding='utf-8',errors='replace'),re.M),p
 for name,pattern in [('viewmodel','902 checks, 0 failures'),('gameplay','SMOKE PASS: 802 integration checks \(0 failures\)')]:
  text=(a/(name+'.log')).read_text(encoding='utf-8');assert re.search(pattern,text) and not re.search(r'SCRIPT ERROR|^ERROR:',text,re.M),text
 check=json.loads((ROOT/'artifacts/radar/radar-1280x720/checks.json').read_text());assert check['failures']==0
 text=f'''# 验证记录 · CS2 方向原创音效

日期：2026-11-15。当前 EXE SHA256：`{sha}`。

本轮重做项目已有枪声、脚步、落地、换弹及命中音。以 CS2 为方向，全部为原创合成，并非原声复刻；没有经过 CS2 原版采样的听觉比对。

- 36 个 48 kHz／16-bit 单声道音源均可读取、非静音、峰值小于 0.66，原始数据见 verification/cs2-audio/audio-metrics.json。
- 源工程六套换弹／模型时序：902 项，0 失败。
- 当前独立 EXE 无窗口玩法回归：802 项，0 失败。无窗口测试不作为听觉或画面证据。
- 当前独立 EXE 图形雷达／脚步／音源／显示与输入：{check['checks']} 项，0 失败。
- 当前独立 EXE 实机声音演示：9 项，0 失败，包含三枪、六套换弹和双方行走，混音峰值 -10.4 dB，无削波。演示采用自动输入，并非人工游玩。

当前媒体：media/cs2-audio/sound-showcase.wav、showcase-order.json 和 demo.mp4。头身冲击音在 WAV 合集中试听，未声称视频涵盖全部命中情况。

主观音色自然度和与 CS2 的相似度仍需试听；独占显卡性能和实际 Ubuntu NUC 跨机测试未执行。上一轮偶发退出资源残留仍未定位。此前完整地图／网络回归保留在历史验证目录及 verification/cs2-audio/previous-validation.md，不作为当前 EXE 的重跑结果。
'''
 (ROOT/'VALIDATION.md').write_text(text,encoding='utf-8')
 v=out/'verification/cs2-audio';v.mkdir(parents=True,exist_ok=True)
 media=out/'media/cs2-audio';media.mkdir(parents=True,exist_ok=True)
 for p in a.glob('*'):
  if p.suffix in ['.json','.log','.md']:shutil.copy2(p,v/p.name)
  elif p.suffix=='.wav':shutil.copy2(p,media/p.name)
 shutil.copy2(a/'showcase-order.json',media/'showcase-order.json')
 shutil.copy2(ROOT/'artifacts/audio-demo/demo.mp4',media/'demo.mp4')
 for name in ['game.log','build.json','mix-volume.log']:shutil.copy2(ROOT/'artifacts/audio-demo'/name,v/('demo-'+name))
 for name in ['game.log','checks.json','build.json']:shutil.copy2(ROOT/'artifacts/radar/radar-1280x720'/name,v/('radar-'+name))
 for name in ['README.md','UI_DESIGN.md','ASSET_MANIFEST.md','VALIDATION.md']:shutil.copy2(ROOT/name,out/name)
 (out/'media/README.md').write_text('当前媒体：cs2-audio/。其他目录是历史版本，见 VALIDATION.md。',encoding='utf-8')
 source=ROOT/'builds/RMPrecisionLab-godot-source.zip'
 with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for p in (ROOT/'射击游戏').rglob('*'):
   if p.is_file() and '.godot' not in p.parts:z.write(p,p.relative_to(ROOT).as_posix())
  for pat in ['*.md','LICENSE','tools/*.py','tools/*.ps1','sdk/cpp/**/*']:
   for p in ROOT.glob(pat):
    if p.is_file():z.write(p,p.relative_to(ROOT).as_posix())
 portable=ROOT/'builds/RMPrecisionLab-windows-x64.zip'
 with zipfile.ZipFile(portable,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for p in out.rglob('*'):
   if p.is_file():z.write(p,p.relative_to(out).as_posix())
 for p in [source,portable]:
  with zipfile.ZipFile(p) as z:assert z.testzip() is None
 with zipfile.ZipFile(portable) as z:assert hashlib.sha256(z.read('RMPrecisionLab.exe')).hexdigest()==sha
 files=[out/'RMPrecisionLab.exe',portable,source,ROOT/'builds/RMControl-cpp-sdk.zip',ROOT/'builds/RMPrecisionLab-first-person-source.zip']
 (ROOT/'builds/SHA256SUMS.txt').write_text('\n'.join(f'{digest(p)}  {p.relative_to(ROOT/"builds").as_posix()}' for p in files)+'\n')
 print('PACKAGED',sha)
if __name__=='__main__':main()
