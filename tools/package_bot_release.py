"""Package only evidence produced by the current expert-bot Windows build."""
from pathlib import Path
import hashlib,json,re,shutil,zipfile
ROOT=Path(__file__).resolve().parents[1]
A=ROOT/'artifacts/bot-upgrade'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def archive(folder,dest):
 with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for p in folder.rglob('*'):
   if p.is_file():z.write(p,p.relative_to(folder).as_posix())
 with zipfile.ZipFile(dest) as z:assert z.testzip() is None

def main():
 out=ROOT/'builds/windows';digest=sha(out/'RMPrecisionLab.exe')
 folders=[A/'export-checks',A/'demo-1280x720',A/'demo-960x540',A/'cpp-probe']
 for folder in folders:assert read(folder/'build.json')['exe_sha256']==digest,folder
 report=read(A/'export-checks/checks.json');assert report['failures']==0 and len(report['comparison'])==8
 for folder in folders[1:3]:assert read(folder/'checks.json')['failures']==0
 regression=read(A/'regression/export-regression.json');assert regression['exe_sha256']==digest and len(regression['runs'])==6
 folders.append(A/'regression')
 assert (A/'demo-1280x720/demo.mp4').stat().st_size>10000
 labels={'static':'静止','strafe':'匀速横移','reverse':'反向变速','jump':'跳跃'}
 rows=[]
 for i in range(4):
  old,new=report['comparison'][i],report['comparison'][i+4]
  rows.append(f"| {labels[old['movement']]} | {old['kills']}/30 | {new['kills']}/30 | {old['median_seconds_capped_at_8']:.2f} s | {new['median_seconds_capped_at_8']:.2f} s |")
 table='\n'.join(rows)
 regress='\n'.join(f"- {r['test']} {r['resolution']}: {'; '.join(r['summary'])}" for r in regression['runs'])
 probe=read(A/'cpp-probe/report.json');assert probe['actions'][0]['fired'] and probe['actions'][1]['reloaded']
 text=f'''# 验证记录 · 全知专家 bot

日期：2026-11-15。最终 EXE SHA256：`{digest}`。

## 当前结果

- 统一专家强度，无难度选项。全知玩家位置／速度；射击仍检查头部、枪口和预测路径遮挡。
- 当前独立 EXE bot 专项：{report['checks']} 项，0 失败。覆盖提前量、落地限制、反应／射速、视线遮挡、掩体选择、低弹量换弹、暂停、卡住恢复、实际跳跃与落地，以及低顶、高障碍、地图边界拒绝起跳。
- 20 个固定种子的实际追击与上高台路线通过。地图生成器既有连通性检查与高台双入口往返另有构建前回归；不是对所有随机地图的穷举证明。
- 两种分辨率图形演示各 {read(A/'demo-1280x720/checks.json')['checks']} 项，0 失败；实际输出截图分别为 1280×720、960×540。包含追击、安全跳跃、掩体提前换弹和移动目标射击。
- 构建前：346 规则、802 玩法、166 输入、352590 实体子弹／路线、39 雷达与音效、902 模型／换弹检查通过。实体子弹测试以 960 Hz、8 倍时间运行，单步模拟时间保持 1/120 秒，不作为性能证据。

## 新旧 bot 对照

相同固定随机种子，每类新旧各 30 局，共 240 局。隔离平地夹具、约 18 米初始距离、真实角色移动和实体子弹；目标不还击，每局最多 8 秒，未击杀计为 8 秒截断值。以下不是人类玩家胜率。

| 目标 | 旧版击杀 | 新版击杀 | 旧版中位时间（截断） | 新版中位时间（截断） |
|---|---:|---:|---:|---:|
{table}

## 最终 EXE 兼容回归

{regress}

Windows C++ 本机回环取得 {probe['frames']} 帧，平均往返 {probe['mean_observe_ms']:.2f} ms；单发与换弹成功。网络协议未增加对手坐标或全知状态，这不是 Ubuntu NUC 跨机验收。

## 媒体与交付边界

当前媒体：media/bot-upgrade/，1280×720 录像与两尺寸截图；验证日志位于 verification/bot-upgrade/。演示使用自动输入、额外测试掩体、隔离平地和第三人称镜头，均不进入正常游戏。截图已抽查跳跃与掩体换弹，未称为真人长时间试玩。其余 media/verification 目录是历史版本，不代表本轮重新验收。

- 独占 GPU 的约 60 FPS 与实际 NUC 跨机验证仍待执行，未关闭用户其他游戏；固定帧率录制速度不作为性能结果。
- 新强度对真人的难度体感尚未验收；本轮只记录可复现的脚本对照。
- 历史音频退出资源残留曾在开发检查中再现；调整了脚步播放器释放顺序，最终专项运行在全部 2188 项通过后仍报告 6 个 ObjectDB 实例／2 个资源在退出时残留；此退出错误保留在日志中，不标为已解决。
'''
 (ROOT/'VALIDATION.md').write_text(text,encoding='utf-8')
 for name in ['README.md','UI_DESIGN.md','CONTROL_API.md','ASSET_MANIFEST.md','VALIDATION.md']:shutil.copy2(ROOT/name,out/name)
 for folder in folders:
  for p in folder.rglob('*'):
   if not p.is_file():continue
   if p.suffix in ['.png','.jpg','.mp4']:dest=out/'media/bot-upgrade'/p.relative_to(A)
   elif p.suffix in ['.log','.json']:
    if p.suffix=='.log':assert not re.search(r'SCRIPT ERROR|^ERROR:|PROJECTILE FAIL|SMOKE FAIL|CONTROL FAIL|INPUT FAIL',re.sub(r'^ERROR: \d+ resources still in use at exit.*$', '', p.read_text(encoding='utf-8',errors='replace'), flags=re.M),re.M),p
    dest=out/'verification/bot-upgrade'/p.relative_to(A)
   else:continue
   dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
 dest=out/'verification/bot-upgrade';shutil.copy2(A/'previous-validation.md',dest/'previous-validation.md')
 if (A/'visual-review.md').exists():shutil.copy2(A/'visual-review.md',dest/'visual-review.md')
 logs=dest/'build';logs.mkdir(exist_ok=True)
 for name in ['rules.log','game-smoke-headless.log','input-checks.log','projectile-headless.log','radar-headless.log','viewmodel-headless.log','export.log']:
  p=ROOT/'artifacts'/name;assert not re.search(r'SCRIPT ERROR|^ERROR:|PROJECTILE FAIL|SMOKE FAIL|INPUT FAIL|VIEWMODEL FAIL',p.read_text(encoding='utf-8',errors='replace'),re.M),p
  shutil.copy2(p,logs/name)
 (out/'media/README.md').write_text('当前专家 bot 媒体：bot-upgrade/。其他目录是历史版本；见 VALIDATION.md。',encoding='utf-8')
 sdk=ROOT/'builds/RMControl-cpp-sdk.zip'
 with zipfile.ZipFile(sdk,'w',zipfile.ZIP_DEFLATED) as z:
  for p in (ROOT/'sdk/cpp').rglob('*'):
   if p.is_file():z.write(p,p.relative_to(ROOT/'sdk').as_posix())
  z.write(ROOT/'CONTROL_API.md','CONTROL_API.md')
 source=ROOT/'builds/RMPrecisionLab-godot-source.zip'
 with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for p in (ROOT/'射击游戏').rglob('*'):
   if p.is_file() and '.godot' not in p.parts:z.write(p,p.relative_to(ROOT).as_posix())
  for pat in ['*.md','LICENSE','tools/*.py','tools/*.ps1','sdk/cpp/**/*']:
   for p in ROOT.glob(pat):
    if p.is_file():z.write(p,p.relative_to(ROOT).as_posix())
 portable=ROOT/'builds/RMPrecisionLab-windows-x64.zip';archive(out,portable)
 for p in [source,sdk]:
  with zipfile.ZipFile(p) as z:assert z.testzip() is None
 with zipfile.ZipFile(portable) as z:assert hashlib.sha256(z.read('RMPrecisionLab.exe')).hexdigest()==digest
 files=[out/'RMPrecisionLab.exe',portable,source,sdk,ROOT/'builds/RMPrecisionLab-first-person-source.zip']
 (ROOT/'builds/SHA256SUMS.txt').write_text('\n'.join(f'{sha(p)}  {p.relative_to(ROOT/"builds").as_posix()}' for p in files)+'\n')
 print('BOT PACKAGED',digest)
if __name__=='__main__':main()
