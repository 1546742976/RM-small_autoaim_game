"""Package the focused zero-error lock change; no unrelated regression reruns."""
from pathlib import Path
import hashlib,json,shutil,zipfile
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 out=ROOT/'builds/windows';a=ROOT/'artifacts/lock-head';digest=sha(out/'RMPrecisionLab.exe')
 folders=[a/'export-checks',a/'demo-1280x720',a/'demo-960x540']
 for folder in folders:
  assert json.loads((folder/'build.json').read_text())['exe_sha256']==digest
  assert json.loads((folder/'checks.json').read_text())['failures']==0
 text=f'''# 验证记录 · 零误差锁头

日期：2026-11-15。最终 EXE SHA256：`{digest}`。

## 本轮完成

- 头部可见优先急停，取消地面换位并直接瞄准真实弹速拦截点；零随机射击偏移。
- 保留 0.18 秒反应、轮内 100 ms 和 2.5 秒换弹；轮间改为 150 ms。
- 已经起跳或换弹时等待完成。仅身体可见、遮挡、死亡、暂停和在途结算不得产生新射击。
- 短遮挡冻结反应积累，超过 0.15 秒重置；锁头期间不主动提前换弹或发起跳跃。
- 枪械朝向同步锁头，人物身体转向仍有速度限制。实体弹不追踪目标，突然反向仍可能躲开。

## 已执行的针对性检查

当前独立 EXE：无窗口专项 54 项，1280×720 和 960×540 图形专项各 55 项，均无失败。覆盖反应与射速边界、零随机偏移、急停优先、低弹量与进行中的换弹、遮挡恢复、仅身体可见、空中落地、暂停、死亡、重开及结算。真实子弹检查确认匀速横移可被提前量命中，而发射后突然反向可以躲开。

源码阶段另已执行实体子弹／路线及 bot 定点回归，日志保留于 verification/lock-head/；这些不冒充最终 EXE 的额外运行结果。

遵照用户“减少后续不必要的 check”的要求，完成针对性检查后未重跑全地图、全武器及网络回归。C++ 协议与控制逻辑未修改；上轮回归记录属于历史证据，不能当作本轮重跑结果。

## 媒体与限制

当前演示为 media/lock-head/demo-1280x720/demo.mp4，截图位于对应两种分辨率目录。演示使用隔离平地、脚本输入和第三人称镜头，不改变正常地图。已抽查射击截图中的人物、枪械方向与弹体；不是真人游玩或逐帧动画验收。

既有退出资源残留问题未宣称修复。独占 GPU 性能、实际 NUC 跨机联调及真人对战体感仍待验证。其他 media/verification 目录是历史交付。
'''
 (ROOT/'VALIDATION.md').write_text(text,encoding='utf-8')
 for name in ['README.md','UI_DESIGN.md','VALIDATION.md']:shutil.copy2(ROOT/name,out/name)
 v=out/'verification/lock-head';v.mkdir(parents=True,exist_ok=True)
 for p in a.glob('*'):
  if p.suffix in ['.log','.md']:shutil.copy2(p,v/p.name)
 for folder in folders:
  for p in folder.iterdir():
   if p.suffix in ['.png','.mp4']:dest=out/'media/lock-head'/folder.name/p.name
   elif p.suffix in ['.log','.json']:dest=v/folder.name/p.name
   else:continue
   dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
 (out/'media/README.md').write_text('当前零误差锁头媒体：lock-head/。其他目录是历史版本。',encoding='utf-8')
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
 with zipfile.ZipFile(portable) as z:assert hashlib.sha256(z.read('RMPrecisionLab.exe')).hexdigest()==digest
 files=[out/'RMPrecisionLab.exe',portable,source,ROOT/'builds/RMControl-cpp-sdk.zip',ROOT/'builds/RMPrecisionLab-first-person-source.zip']
 (ROOT/'builds/SHA256SUMS.txt').write_text('\n'.join(f'{sha(p)}  {p.relative_to(ROOT/"builds").as_posix()}' for p in files)+'\n')
 print('LOCK PACKAGED',digest)
if __name__=='__main__':main()
