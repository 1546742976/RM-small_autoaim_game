"""Package the moving-fire release with current evidence."""
from pathlib import Path
import hashlib
import json
import math
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'builds/windows'
ART = ROOT / 'artifacts'
DEMO = ART / 'spread-demo-final'
checks = {}
logs = ['rules.log', 'game-smoke-headless.log', 'spread-export-1280.log', 'spread-export-960.log']
for name in logs:
    text = (ART / name).read_text(encoding='utf-8')
    assert not re.search(r'SCRIPT ERROR:|^ERROR:|SMOKE FAIL|^FAIL', text, re.M), name
    match = re.search(r'PASS: (\d+) rule checks|SMOKE PASS: (\d+) integration checks \(0 failures\)', text)
    assert match, name
    checks[name] = int(next(value for value in match.groups() if value))
for name in ['import.log', 'export.log', 'spread-demo.log']:
    text = (ART / name).read_text(encoding='utf-8')
    assert not re.search(r'SCRIPT ERROR:|^ERROR:', text, re.M), name
assert 'SPREAD DEMO: 18 moving, 6 accurate shots' in text

records = json.loads((DEMO / 'shots.json').read_text(encoding='utf-8'))
moving = [shot for shot in records if shot['stage'] == 'moving']
accurate = [shot for shot in records if shot['stage'] == 'accurate']
assert len(records) == 24 and len(moving) == 18 and len(accurate) == 6
assert all(shot['speed_ratio'] >= 0.34 for shot in moving)
assert all(shot['speed_ratio'] < 0.34 for shot in accurate)
assert all(shot['board_hit'] for shot in records)
aim_point = (0, 3.25, -5.9)


def norm(vector):
    return math.sqrt(sum(value * value for value in vector))


# The moving camera tracks the board between physics steps. Its board-center
# vector is not the firing-time camera forward; cone bounds are checked by
# test_rules.gd against the actual camera basis instead of this moving marker.
center_error = max(norm([a - b for a, b in zip(shot['impact'], aim_point)]) for shot in accurate)
assert center_error < 0.005
exe_hash = hashlib.sha256((OUT / 'RMPrecisionLab.exe').read_bytes()).hexdigest()
report = f'''# 验证记录 · 2026-11-14

对应“移动射击与 20% 随机散布”版本。最终 EXE SHA256：`{exe_hash}`。

## 规则与独立运行

| 检查 | 结果 | 原始日志 |
|---|---|---|
| 规则 | {checks['rules.log']} 项通过 | `artifacts/rules.log` |
| 无界面真实场景 | {checks['game-smoke-headless.log']} 项通过，0 失败 | `artifacts/game-smoke-headless.log` |
| Windows EXE，1280×720 | {checks['spread-export-1280.log']} 项通过，0 失败 | `artifacts/spread-export-1280.log` |
| Windows EXE，960×540 | {checks['spread-export-960.log']} 项通过，0 失败 | `artifacts/spread-export-960.log` |

导入、规则、场景和导出均通过，最终日志没有脚本或引擎错误。同份日志随便携包放在 `verification/`。本轮没有重新测量实时 FPS；录像采用固定步长，不用录像帧率代替性能结果。

## 移动射击与随机散布

- 两图 × 三枪均验证速度比 0.339 为中心射线，0.34、0.341 和 1.0 可开火并产生散布；正常扣弹并记录发射数，相机方向不被散布改变。
- 规则测试使用固定种子抽取 10,000 发，检查 10 米截面半径不超过 2 米、圆盘重心、半径平方均值及四象限计数，并验证序列可复现。0.34 与 1.8 在同一种子下散布一致，速度不会继续扩大散布。
- 精准射击与冷却、换弹、空弹夹、非训练阶段的失败射击均不消耗随机数。被拒绝的点击不补射。队列中的有效点击按实际发射时速度判定；速度降到 0.339 立即恢复精准。
- 使用真实物理射线验证散布命中头部立即击杀、身体零伤害且计入命中、墙体遮挡；三枪在两张地图均检查最后一发先计入击杀和发射数再进入结算。
- 准星精度与开火许可分别检查；移动时展开为琥珀色，停稳时收拢为暖白色，冷却、换弹和无弹时降低亮度。界面不增加速度或散布数值。

10,000 发的分布检查是固定样本的统计校验；均匀面积分布由 `r = 0.2 × sqrt(U)` 的采样公式确定。边界测试直接设置速度，实际行走／反向减速另通过玩家物理运动和演示验证。

## 回归范围

覆盖地图与免费枪械选择、键盘焦点、3 秒倒数、60 秒训练、射速、自动／手动换弹、余弹保留、同配置重开、更换配置、返回菜单及统计重置。暂停冻结移动、冷却、换弹动画、回合、人物和刷新计时，也不消耗散布随机数；操作说明保持原暂停状态。

两图均通过玩家实际碰撞走完规定闭环，检查六个目标的头身射线、移动路径与边界。连续切换地图后只保留一张地图和六个目标。保留人物区域、击杀去重、双手续弹关键帧和弹匣接触点检查。检查训练 HUD 没有经济、生命、速度、实时成绩或常驻操作说明。

自动化通过游戏输入事件、动作注入与固定场景设置完成，没有将其写成真人长时间试玩。地图检查覆盖规定路线与主要射线，没有穷举全部墙角和视角。

## 对比演示与画面

`media/spread-demo.mp4` 来自本轮最终 Windows EXE，使用真实移动、反向减速、射击和碰撞：先发射 18 发移动散布，再发射 6 发停稳精准射击。演示专用校准板、落点标记和标题仅在 `--spread-demo` 模式存在。

演示原始记录为 `media/shots.json`。18 发移动射击全部在速度比不低于 0.34 时发射，落点分散；6 发精准射击全部低于门槛，板面最大中心误差 {center_error * 1000:.3f} 毫米（浮点／碰撞精度）。24 发全部真实命中校准板。散布半径相对实际发射时的相机方向验证，不把移动过程中持续追踪的板面中心误当成发射时瞄准方向。

`media/moving-spread.png` 与 `media/stopped-precision.png` 为演示截图；`media/ui-1280/`、`media/ui-960/` 为对应尺寸的菜单、说明、准备、倒数、暂停、结算与两图截图。已目视检查本轮说明页、HUD 和对比画面。

交付更新的 Godot 源工程、Windows EXE、便携 ZIP、README、UI_DESIGN、素材／许可证清单及本记录。素材与许可证未改变，`licenses/` 保留作者署名及 CC BY、CC0、MIT、OFL、Godot 声明。
'''
(ROOT / 'VALIDATION.md').write_text(report, encoding='utf-8')
for name in ['README.md', 'ASSET_MANIFEST.md', 'VALIDATION.md', 'UI_DESIGN.md', 'LICENSE']:
    shutil.copy2(ROOT / name, OUT / name)
media = OUT / 'media'
media.mkdir(exist_ok=True)
captures = ['01-menu.png', '01-help.png', '02-setup.png', '02-countdown.png',
            '03-training.png', '04-pause.png', '05-results.png',
            'old_town-training.png', 'training_hall-training.png']
for size in ['1280', '960']:
    folder = media / f'ui-{size}'
    folder.mkdir(exist_ok=True)
    for name in captures:
        shutil.copy2(ART / f'spread-final-{size}' / name, folder / name)
for name in ['moving-spread.png', 'stopped-precision.png', 'shots.json']:
    shutil.copy2(DEMO / name, media / name)
assert (media / 'spread-demo.mp4').stat().st_size > 100_000
(media / 'README.md').write_text('''# 实机画面

- `spread-demo.mp4`：最终 Windows EXE 的移动散布与急停后精准射击对比。
- `moving-spread.png`、`stopped-precision.png`：对应阶段截图。
- `shots.json`：演示每发的速度、射线、碰撞点和是否命中校准板。
- `ui-1280/`、`ui-960/`：对应尺寸的界面与两图截图。

校准板、落点标记与标题只存在于演示模式，正常训练不显示。录像采用固定步长，录像帧率不是实时性能依据；本轮没有重新进行 FPS 测量。

全部画面由本项目场景渲染；模型署名和材质来源见同包 ASSET_MANIFEST.md 与 licenses/。
''', encoding='utf-8')
verification = OUT / 'verification'
verification.mkdir(exist_ok=True)
for name in logs + ['import.log', 'export.log', 'spread-demo.log']:
    shutil.copy2(ART / name, verification / name)
archive = ROOT / 'builds/RMPrecisionLab-windows-x64.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for path in sorted(OUT.rglob('*')):
        if path.is_file():
            z.write(path, path.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert hashlib.sha256(z.read('RMPrecisionLab.exe')).hexdigest() == exe_hash
zip_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
(ROOT / 'builds/SHA256SUMS.txt').write_text(f'{exe_hash}  windows/RMPrecisionLab.exe\n{zip_hash}  {archive.name}\n', encoding='utf-8')
print(f'Validated and packaged {archive.stat().st_size / 1024**2:.1f} MiB')
