"""Package the tested Windows build and its current evidence, never old captures."""
from pathlib import Path
import hashlib, json, re, shutil, zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'builds/windows'
ART = ROOT / 'artifacts'
checks = {}
logs = ['rules.log', 'game-smoke-headless.log', 'ui-export-1280.log', 'ui-export-960.log']
for name in logs:
    text = (ART / name).read_text(encoding='utf-8')
    assert not re.search(r'SCRIPT ERROR:|^ERROR:|SMOKE FAIL|^FAIL', text, re.M), name
    match = re.search(r'PASS: (\d+) rule checks|SMOKE PASS: (\d+) integration checks \(0 failures\)', text)
    assert match, name
    checks[name] = int(next(value for value in match.groups() if value))
for name in ['import.log', 'export.log', 'ui-benchmark.log', 'ui-movie.log', 'ui-showcase-960.log']:
    text = (ART / name).read_text(encoding='utf-8')
    assert not re.search(r'SCRIPT ERROR:|^ERROR:', text, re.M), name

performance = json.loads((ART / 'ui-performance/performance.json').read_text(encoding='utf-8'))
assert len(performance) == 4 and all(row['seconds'] >= 30 for row in performance)
exe_hash = hashlib.sha256((OUT / 'RMPrecisionLab.exe').read_bytes()).hexdigest()
names = {'old_town': '旧镇街区', 'training_hall': '训练馆'}
rows = '\n'.join(f"| {names[r['map']]} | {r['resolution']} | {r['seconds']:.2f} s | {r['mean_fps']:.2f} | {r['p95_ms']:.3f} ms | {r['p99_ms']:.3f} ms | {r['worst_ms']:.3f} ms |" for r in performance)
report = f'''# 验证记录 · 2026-11-14

对应“极简 UI、地图选择与免费装备”版本。最终 EXE SHA256：`{exe_hash}`。

## 规则及独立运行检查

| 检查 | 结果 | 日志 |
|---|---|---|
| 规则 | {checks['rules.log']} 项通过 | `artifacts/rules.log` |
| 无界面真实场景 | {checks['game-smoke-headless.log']} 项通过，0 失败 | `artifacts/game-smoke-headless.log` |
| Windows EXE，1280×720 | {checks['ui-export-1280.log']} 项通过，0 失败 | `artifacts/ui-export-1280.log` |
| Windows EXE，960×540 | {checks['ui-export-960.log']} 项通过，0 失败 | `artifacts/ui-export-960.log` |

导入、规则检查、场景检查和导出均通过，最终日志没有脚本或引擎错误。移除了旧经济系统的 7 项规则检查，其余射击数值检查保留，不以旧版本的检查数量作为本轮结果。

覆盖两图 × 三枪的六种组合、默认配置与自由选择、键盘 Enter 操作卡片、3 秒倒数与禁止移动／射击／换弹、60 秒训练、同配置重开、变更配置、主菜单、暂停和操作说明。验证暂停冻结倒数、冷却、换弹、人物及刷新；恢复后继续，返回菜单恢复换弹姿态。

射击回归包含 0.339 / 0.34 / 0.341 边界、冷却、自动／手动换弹、余弹保留、真实头身射线、非头部零伤害、死亡立即关闭碰撞和最后一发计分。保留双手续弹各关键阶段与弹匣接触点检查。训练 HUD 检查没有生命、速度、实时成绩、购买或常驻键位；准备页检查控件在窗口范围内及键盘焦点存在。

## 地图检查

两图均使用 CharacterBody 的实际移动与碰撞走完预设闭环，每段到达终点且保持在地面；检查六个目标从预设视线可命中躯干和头部。每个目标路径采样 17 个胶囊位置检查与世界固体不重叠，地图边界真实射线不穿透。连续切换地图确认仅有一张地图和六个目标；旧地图的节点、灯光和碰撞同步释放。

旧镇街区为原创模块地图，不是 Inferno 的逐点复刻；建筑上层和门窗作为背景，不能进入。当前验证覆盖规定路线与主要射线，没有穷举所有墙角和视角。

## 本机实时性能

GPU：{performance[0]['gpu']}；Windows，Forward+ / D3D12，默认同步设置。使用最终独立 EXE，每个地图／尺寸组合预热 240 帧，再测量至少 30 秒，六个靶子运行，脚本持续绕行并周期换弹。

| 地图 | 分辨率 | 测量时长 | 平均 FPS | P95 帧间隔 | P99 帧间隔 | 最长帧 |
|---|---|---:|---:|---:|---:|---:|
{rows}

原始数据见 `media/performance.json`；只代表本机上述时长与场景，不包含首次加载，不代表其他硬件结果。

## 图像与交付

`media/ui-1280/` 和 `media/ui-960/` 包含最终 EXE 的菜单、说明、准备、倒数、暂停、结算和两图画面；`media/town-demo.mp4` 展示新流程、街区完整绕行、三枪换弹和命中反馈。截图由游戏自身渲染，已目视检查；录像采用固定步长，性能结论独立来自上表。

鼠标、键盘与路线通过游戏输入事件和动作注入验证，未将自动化检查写成真人长时间试玩。最初检查发现的焦点时序与地图释放顺序问题已修正，表格只列最终版本结果。

交付 Godot 源工程、Windows EXE、便携 ZIP、README、UI_DESIGN、素材／许可证清单及本记录。包中的 `licenses/` 保留模型作者署名、CC BY、CC0、MIT、OFL 和 Godot 声明。
'''
(ROOT / 'VALIDATION.md').write_text(report, encoding='utf-8')
for name in ['README.md', 'ASSET_MANIFEST.md', 'VALIDATION.md', 'UI_DESIGN.md', 'LICENSE']:
    shutil.copy2(ROOT / name, OUT / name)
media = OUT / 'media'
media.mkdir(exist_ok=True)
for source, target in [('ui-showcase-final', 'ui-1280'), ('ui-showcase-960', 'ui-960')]:
    folder = media / target
    folder.mkdir(exist_ok=True)
    for path in (ART / source).glob('*.png'):
        shutil.copy2(path, folder / path.name)
shutil.copy2(ART / 'ui-performance/performance.json', media / 'performance.json')
assert (media / 'town-demo.mp4').stat().st_size > 100_000
(media / 'README.md').write_text('''# 实机画面

- `town-demo.mp4`：最终 Windows EXE 的新流程、小镇绕行、三枪换弹及暂停／结算演示。
- `ui-1280/`、`ui-960/`：对应尺寸的稳定界面截图、两图截图与小镇路线画面。
- `performance.json`：独立实时测量数据。录像采用固定步长，录像帧率不是实时性能依据。

全部画面由本项目场景渲染；枪械和人物署名、外部材质来源见同包 ASSET_MANIFEST.md 与 licenses/。
''', encoding='utf-8')
verification = OUT / 'verification'
verification.mkdir(exist_ok=True)
for name in logs + ['import.log', 'export.log', 'ui-benchmark.log', 'ui-movie.log', 'ui-showcase-960.log']:
    shutil.copy2(ART / name, verification / name)
archive = ROOT / 'builds/RMPrecisionLab-windows-x64.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for path in sorted(OUT.rglob('*')):
        if path.is_file(): z.write(path, path.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert hashlib.sha256(z.read('RMPrecisionLab.exe')).hexdigest() == exe_hash
zip_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
(ROOT / 'builds/SHA256SUMS.txt').write_text(f'{exe_hash}  windows/RMPrecisionLab.exe\n{zip_hash}  {archive.name}\n', encoding='utf-8')
print(f'Validated and packaged {archive.stat().st_size/1024**2:.1f} MiB')
