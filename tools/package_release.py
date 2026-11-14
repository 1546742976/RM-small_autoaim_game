"""Package the LAN control release with evidence from the exported game."""
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
logs = ['rules.log', 'game-smoke-headless.log', 'control-export-1280.log', 'control-export-960.log']
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

control_logs = ['control-network-1280.log', 'control-network-960.log', 'control-cpp-build.log']
for name in control_logs:
    text = (ART / name).read_text(encoding='utf-8')
    assert not re.search(r'SCRIPT ERROR:|^ERROR:|CONTROL FAIL|CMake Error', text, re.M), name
    if name.startswith('control-network'):
        match = re.search(r'CONTROL PASS: (\d+) checks \(0 failures\)', text)
        assert match, name
        checks[name] = int(match[1])
    else:
        assert '100% tests passed' in text and 'Built target rm_vision_template' in text
assert 'CPP PROBE PASS' in (ART / 'control-probe-final/client.log').read_text()
assert '120 decoded BGR frames' in (ART / 'control-vision-final/client.log').read_text()
probe = json.loads((ART / 'control-probe-final/report.json').read_text())
assert probe['actions'][0]['fired'] and probe['actions'][1]['reloaded']
performance_rows = []
performance_data = []
evidence_folders = ['control-probe-final', 'control-vision-final']
for map_id, label in [('training_hall', '训练馆'), ('old_town', '旧镇街区')]:
    for mode in ['ping', 'camera']:
        folder = f'control-perf-{map_id}-{mode}'
        evidence_folders.append(folder)
        perf = json.loads((ART / folder / 'performance.json').read_text())
        throughput = json.loads((ART / folder / 'report.json').read_text())
        assert perf['seconds'] >= 30
        if mode == 'camera':
            assert throughput['frames'] > 0 and throughput['actions'][0]['fired']
        performance_data.append({'map': map_id, 'mode': mode, 'game': perf, 'client': throughput})
        performance_rows.append(f"| {label} | {'持续 JPEG 取图' if mode == 'camera' else '仅连接保活'} | {perf['seconds']:.2f} s | {perf['mean_fps']:.2f} | {perf['p95_ms']:.2f} ms | {throughput['frames_per_second']:.2f} | {throughput['mean_observe_ms']:.2f} / {throughput['p95_observe_ms']:.2f} ms |")
for folder in evidence_folders:
    text = (ART / folder / 'game.log').read_text(encoding='utf-8')
    assert not re.search(r'SCRIPT ERROR:|^ERROR:', text, re.M), folder
performance_table = '\n'.join(performance_rows)

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

对应“局域网 C++ 视觉控制接口”版本。最终 EXE SHA256：`{exe_hash}`。

## 规则与独立运行

| 检查 | 结果 | 原始日志 |
|---|---|---|
| 规则 | {checks['rules.log']} 项通过 | `artifacts/rules.log` |
| 无界面真实场景 | {checks['game-smoke-headless.log']} 项通过，0 失败 | `artifacts/game-smoke-headless.log` |
| Windows EXE，1280×720 | {checks['control-export-1280.log']} 项通过，0 失败 | `artifacts/control-export-1280.log` |
| Windows EXE，960×540 | {checks['control-export-960.log']} 项通过，0 失败 | `artifacts/control-export-960.log` |
| TCP 接口，1280×720 | {checks['control-network-1280.log']} 项通过，0 失败 | `artifacts/control-network-1280.log` |
| TCP 接口，960×540 | {checks['control-network-960.log']} 项通过，0 失败 | `artifacts/control-network-960.log` |

导入、规则、场景、TCP 和导出均通过，最终日志没有脚本或引擎错误。同份日志随便携包放在 `verification/`。录像采用固定步长；实时性能使用下面的独立测量。

## C++ 接口验证

最终 EXE 通过真实 TCP 连接验证：错误口令、重复接管、分包、粘包、重复请求编号、过大消息、慢客户端、两秒超时、断连和重连。检查人工瞄准／开火／换弹被接管、WASD 可用、失焦继续、暂停优先，以及旧回合、旧会话和暂停画面不能继续控制。两图 × 三枪验证控制指令的速度边界、头身命中和最后一发结算，开火仍通过原武器及射线流程。

实际 JPEG 解码检查两种尺寸、RGB 颜色和左上原点；相机内参与 Godot 渲染投影逐项比较。返回数据检查不包含目标坐标、位置、可见性或头部信息。图像采集间隔检查不小于 33,334 微秒，慢客户端只产生一个被请求的画面。

C++17 客户端与 OpenCV 模板在 Windows / MinGW GCC 16.1.0 上实际编译，使用本地构建的 OpenCV 4.10.0。CTest 验证中心、角度符号及 45 个不同俯仰／像素组合的像素转角度。C++ 联调真实读取画面，向右 5°、向上 3°、单发和换弹均成功；独立 OpenCV 模板实际解码 120 帧 BGR 图像，默认检测函数为空。

**尚未完成实体 Ubuntu NUC 跨机验证。** 本机 WSL 中列有 Ubuntu 22.04，但启动报 `HCS_E_HYPERV_NOT_INSTALLED`，没有把它写成 Linux 构建通过。已提供 Ubuntu 22.04／24.04 的 POSIX 客户端、CMake 和依赖步骤；Ubuntu 编译、实体局域网连通性和跨机延迟仍待在控制端执行。本轮实际通信结果为 Windows 本机回环，不等同于实体 NUC 验收。

## 本机性能与取图耗时

GPU：{performance_data[0]['game']['gpu']}；Windows，Forward+ / D3D12，1280×720。四组顺序运行，每组进入训练并预热 240 帧后测量至少 30 秒；六个靶子运行，玩家持续横向走动。传图组的 C++ 客户端额外执行一次转向、射击和换弹。游戏指标来自预热后的 30 秒；客户端取图指标覆盖其完整 40 秒循环，包含倒数和预热。

| 地图 | 模式 | 游戏测量时长 | 游戏平均 FPS | P95 帧间隔 | 客户端图像 FPS | 平均 / P95 取图耗时 |
|---|---|---:|---:|---:|---:|---:|
{performance_table}

“仅连接保活”不请求图像，表内图像 FPS／取图耗时为 0。持续传图时平均游戏帧率约 60，但 P95 帧间隔明显增大，存在周期性帧间波动；当前取图实测约 15 FPS，30 FPS 是采集上限，不是吞吐保证。取图耗时包括请求、等待新渲染帧、JPEG 编码及传输，不是纯网络 RTT，也不包含目标识别；这些数字不代表其他机器或网络。原始数据见 `verification/control-perf-*/` 和 `media/control-performance.json`。

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

交付更新的 Godot 源工程、Windows EXE、便携 ZIP、独立 C++ SDK 源码包、README、CONTROL_API、UI_DESIGN、素材／许可证清单及本记录。`licenses/` 保留原素材声明，SDK 包内提供 nlohmann/json 的 MIT 许可证；OpenCV 由控制端外部依赖提供。
'''
(ROOT / 'VALIDATION.md').write_text(report, encoding='utf-8')
for name in ['README.md', 'ASSET_MANIFEST.md', 'VALIDATION.md', 'UI_DESIGN.md', 'CONTROL_API.md', 'LICENSE']:
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
        shutil.copy2(ART / f'control-final-{size}' / name, folder / name)
    shutil.copy2(ART / f'control-network-{size}' / 'control-camera.png', media / f'control-camera-{size}.png')
(media / 'control-performance.json').write_text(json.dumps(performance_data, ensure_ascii=False, indent=2), encoding='utf-8')
for name in ['moving-spread.png', 'stopped-precision.png', 'shots.json']:
    shutil.copy2(DEMO / name, media / name)
assert (media / 'spread-demo.mp4').stat().st_size > 100_000
(media / 'README.md').write_text('''# 实机画面

- `spread-demo.mp4`：最终 Windows EXE 的移动散布与急停后精准射击对比。
- `moving-spread.png`、`stopped-precision.png`：对应阶段截图。
- `shots.json`：演示每发的速度、射线、碰撞点和是否命中校准板。
- `ui-1280/`、`ui-960/`：对应尺寸的界面与两图截图。

- `control-camera-1280.png`、`control-camera-960.png`：通过 TCP 接口获取并解码的真实画面。
- `control-performance.json`：本轮两图的连接／取图性能原始数据。

校准板、落点标记与标题只存在于演示模式，正常训练不显示。录像采用固定步长，录像帧率不是实时性能依据。

全部画面由本项目场景渲染；模型署名和材质来源见同包 ASSET_MANIFEST.md 与 licenses/。
''', encoding='utf-8')
verification = OUT / 'verification'
verification.mkdir(exist_ok=True)
for name in logs + control_logs + ['import.log', 'export.log', 'spread-demo.log']:
    shutil.copy2(ART / name, verification / name)
for folder in evidence_folders:
    shutil.copytree(ART / folder, verification / folder, dirs_exist_ok=True)
shutil.copytree(ROOT / 'sdk/cpp', OUT / 'sdk/cpp', dirs_exist_ok=True, ignore=shutil.ignore_patterns('build', 'build-*'))
sdk_archive = ROOT / 'builds/RMControl-cpp-sdk.zip'
with zipfile.ZipFile(sdk_archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    z.write(ROOT / 'CONTROL_API.md', 'CONTROL_API.md')
    z.write(ROOT / 'VALIDATION.md', 'VALIDATION.md')
    for path in sorted((OUT / 'sdk/cpp').rglob('*')):
        if path.is_file(): z.write(path, path.relative_to(OUT / 'sdk').as_posix())
archive = ROOT / 'builds/RMPrecisionLab-windows-x64.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for path in sorted(OUT.rglob('*')):
        if path.is_file():
            z.write(path, path.relative_to(OUT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert hashlib.sha256(z.read('RMPrecisionLab.exe')).hexdigest() == exe_hash
zip_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
sdk_hash = hashlib.sha256(sdk_archive.read_bytes()).hexdigest()
with zipfile.ZipFile(sdk_archive) as z: assert z.testzip() is None
(ROOT / 'builds/SHA256SUMS.txt').write_text(f'{exe_hash}  windows/RMPrecisionLab.exe\n{zip_hash}  {archive.name}\n{sdk_hash}  {sdk_archive.name}\n', encoding='utf-8')
print(f'Validated and packaged {archive.stat().st_size / 1024**2:.1f} MiB')
