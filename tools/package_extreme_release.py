"""Package the focused extreme-NPC update without unrelated regression runs."""
from pathlib import Path
import hashlib,json,shutil,zipfile
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 out=ROOT/'builds/windows';a=ROOT/'artifacts/extreme-bot';digest=sha(out/'RMPrecisionLab.exe')
 folders=[a/'export-checks']
 report=json.loads((folders[0]/'checks.json').read_text())
 assert json.loads((folders[0]/'build.json').read_text())['exe_sha256']==digest and report['failures']==0
 rows='\n'.join(f"- {r['target']}: {r['kills']}/{r['trials']}，中位 {r['median_seconds_capped_at_1']:.3f} 秒" for r in report['results'])
 text=f"""# 验证记录 · 极限 bot

日期：2026-11-15。最终 EXE SHA256：`{digest}`。

## 当前强度

bot 30 毫秒反应，6 米／秒移动、240 米／秒² 急停，1440°／秒转身，80 米视觉距离；保持全知追踪、120°视野及真实头部／枪口遮挡检查。零误差预测瞄头，70 毫秒持续射击、无额外轮间暂停，25 发弹夹、650 毫秒换弹和补充备弹。bot 专属实体弹速度 150 米／秒，最大 100 米；玩家仍为 25 米／秒，原武器射速和换弹不变。NPC 换弹姿态按其实际计时同步。

这是一组有意偏向 bot 的非对称参数；没有增加生命、穿墙命中、子弹追踪或直接判死。

## 针对性结果

最终独立 EXE {report['checks']} 项检查，0 失败。覆盖反应窗口、连续射击间隔、650 毫秒换弹、玩家参数隔离、不同实体弹速、高速弹扫掠 2 mm 薄墙、视线遮挡、暂停与结算。

约 18 米初始距离，目标不还击，每类 5 局，最多 1 秒，真实移动与实体头部碰撞：

{rows}

这是固定脚本场景，不代表真人胜率，也不能证明人类绝对无法击败。

## 本轮范围与未执行项

遵照用户减少不必要检查的要求，本轮只进行了改动相关检查和最终 EXE 核对，没有重跑全地图、全武器、网络、性能或录制新演示。此前媒体、锁头专项和专家对照均是历史版本记录。

既有退出资源残留未声称修复；独占 GPU 性能、实体 NUC 跨机和真人对战体验仍待验证。当前日志在 verification/extreme-bot/。源码与便携包已同步更新。
"""
 (ROOT/'VALIDATION.md').write_text(text,encoding='utf-8')
 for name in ['README.md','UI_DESIGN.md','CONTROL_API.md','VALIDATION.md']:shutil.copy2(ROOT/name,out/name)
 v=out/'verification/extreme-bot';v.mkdir(parents=True,exist_ok=True)
 for p in a.glob('*'):
  if p.suffix in ['.log','.md']:shutil.copy2(p,v/p.name)
 for folder in folders:
  for p in folder.iterdir():
   if p.suffix in ['.png','.mp4']:dest=out/'media/extreme-bot'/folder.name/p.name
   elif p.suffix in ['.log','.json']:dest=v/folder.name/p.name
   else:continue
   dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
 (out/'media/README.md').write_text('当前极限 bot 验证：extreme-bot/。其他目录是历史版本。',encoding='utf-8')
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
 print('EXTREME PACKAGED',digest)
if __name__=='__main__':main()
