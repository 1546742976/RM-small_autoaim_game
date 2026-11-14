"""Package verified random-yard release; keep earlier media explicitly historical."""
from pathlib import Path
import hashlib,json,shutil,zipfile,re,struct
ROOT=Path(__file__).resolve().parents[1]
E=ROOT/'artifacts/assessment'
OUT=ROOT/'builds/windows'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p): return json.loads(p.read_text(encoding='utf-8'))
def archive(root,destination):
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(root.rglob('*')):
            if p.is_file(): z.write(p,p.relative_to(root).as_posix())
    with zipfile.ZipFile(destination) as z: assert z.testzip() is None
def main():
    digest=sha(OUT/'RMPrecisionLab.exe')
    metrics=[];checks=[]
    for size in ['1280x720','960x540']:
        folder=E/f'checks-{size}'
        assert read(folder/'build.json')['exe_sha256']==digest
        assert read(folder/'checks.json')['failures']==0
        # Preserve the original hash of the earlier shared-GPU sample.
        assert read(E/f'benchmark-{size}/checks.json')['failures']==0
        checks.append(read(E/f'checks-{size}/checks.json')['checks'])
        reports=read(E/f'benchmark-{size}/performance.json')
        assert len(reports)==3 and all(r['seconds']>=30 and r['bot_shots']>0 and r['player_shots']>0 for r in reports)
        for i,r in enumerate(reports):
            with (E/f'benchmark-{size}/benchmark-{i}.png').open('rb') as f: header=f.read(24)
            actual=struct.unpack('>II',header[16:24]); assert list(actual)==[int(s) for s in size.split('x')]
            r['resolution']=size; metrics.append(r)
    regression=read(E/'regression/export-regression.json')
    assert regression['exe_sha256']==digest and len(regression['runs'])==6
    assert all(r['summary'] and any('PASS' in line for line in r['summary']) for r in regression['runs'])
    assert read(E/'demo-1280x720/build.json')['exe_sha256']==digest
    assert read(E/'demo-1280x720/checks.json')['failures']==0
    demo=read(E/'demo-1280x720/demo.json')
    assert len(demo)==3 and len({r['seed'] for r in demo})==3
    assert all(r['encountered'] and r['player_shots']>0 and r['bot_shots']>0 for r in demo)
    assert (E/'demo-1280x720/demo.mp4').stat().st_size>10000
    probe=read(E/'cpp-probe/report.json')
    assert read(E/'cpp-probe/build.json')['exe_sha256']==digest
    assert probe['actions'][0]['fired'] and probe['actions'][1]['reloaded']
    rows='\n'.join(f"| {r['resolution']} | {r['seed']} | {r['generation_ms']:.1f} | {r['seconds']:.2f} | {r['mean_fps']:.2f} | {r['p95_ms']:.2f} | {r['bot_shots']} / {r['player_shots']} |" for r in metrics)
    regress='\n'.join(f"- {r['test']} {r['resolution']}: {'; '.join(r['summary'])}" for r in regression['runs'])
    history=OUT/'verification/previous-first-person-validation.md'
    if not history.exists(): shutil.copy2(ROOT/'VALIDATION.md',history)
    report=f'''# 验证记录 · 随机箱阵考核

实施日期：2026-11-14～15。最终 Windows EXE SHA256：`{digest}`。

## 本轮实际执行

- 最终独立 EXE 的 1280×720 / 960×540 场景检查分别通过 {checks[0]} / {checks[1]} 项，失败数为 0。
- 导出前的无窗口构建检查通过规则 346 项、原场景 829 项、输入 160 项及双手模型 901 项；这些不作为图形性能证据。
- 每次检查批量覆盖 1,000 个种子：连通性、固定种子复现、相邻布局的转折变化、三条主路 4 米净空；10 张实际生成地图使用玩家同尺寸胶囊对三条主路与四条连接口做物理扫掠。
- 三把枪覆盖真实射线爆头、最后一发获胜、身体命中零伤害；检查 bot 反应延迟、实际开火、墙体遮挡视线和子弹、玩家真实头身命中、暂停及切回旧图。双方同时死亡、超时和弹尽优先级另作规则检查。
- 胶囊扫掠不等同于真人逐路试玩；程序移动与对战演示另存于媒体目录。

{regress}

## 性能验收：独占环境待复测

用户已选择先完成交付。以下测量期间 Deadlock 同时运行，显卡总占用约 99～100%，因此仅保留为共享 GPU 环境的诊断样本，不用于确认稳定 60 FPS。未关闭用户的其他游戏；独占显卡环境的性能验收未执行。

性能样本版本 SHA256：`{read(E/'benchmark-1280x720/build.json')['exe_sha256']}`。此后仅调整自动录像辅助脚本，正式玩法代码未改动。

每种分辨率三个随机布局，预热后各测至少 30 秒。性能专用场景不结束回合，保留真实寻路、感知、移动、射线、弹匣与换弹；为持续采样，不结算玩家死亡，并补充玩家备弹。这不是普通对局胜负验证。

| 分辨率 | 随机种子 | 生成 ms | 测量秒 | 平均 FPS | P95 ms | bot / 玩家发射数 |
|---|---|---:|---:|---:|---:|---:|
{rows}

GPU：{metrics[0]['gpu']}。分辨率由同次输出 PNG 尺寸核对；P99、最差帧间隔在原始 performance.json 中。这些结果不代表独占环境性能，也未达到稳定 60 FPS 的验收要求。

## 程序接口

实际 C++ 客户端在箱阵地图进行 Windows 回环联调：{probe['frames']} 帧、{probe['frames_per_second']:.2f} 帧／秒，平均取图往返 {probe['mean_observe_ms']:.2f} ms；角度调整、一次开火和换弹均成功。现有协议保持版本和字段，未加入种子、道路、箱子和敌方坐标。未执行 Ubuntu NUC 实体跨机测试。

## 画面与交付

本轮截图、多个随机布局俯视图及连续换图／对战录像在 `media/assessment/`，原始日志在 `verification/assessment/`。录像由脚本使用正常移动、碰撞和射击流程驱动，辅助脚本读取地图路线及对手姿态安排交火，不是 C++ 视觉识别演示，也不是人工操作录像。三局发射数记录在 demo.json。目视抽查范围见 `verification/assessment/visual-review.md`。未将自动化检查视为真人长时间试玩或音效听觉验收。

其余 first-person、control、spread 媒体及报告为此前版本的历史结果；新模型无照片级细节承诺，第三人称动作使用原角色动画和持枪约束。

源工程为 `射击游戏/project.godot`，完整源工程压缩包为 `RMPrecisionLab-godot-source.zip`；游戏包解压运行 RMPrecisionLab.exe，无需安装 Godot 或 Blender。素材与署名见 ASSET_MANIFEST.md。
'''
    (ROOT/'VALIDATION.md').write_text(report,encoding='utf-8')
    for name in ['README.md','VALIDATION.md','UI_DESIGN.md','ASSET_MANIFEST.md','CONTROL_API.md','LICENSE']:
        shutil.copy2(ROOT/name,OUT/name)
    names=['checks-1280x720','checks-960x540','benchmark-1280x720','benchmark-960x540','demo-1280x720','regression','cpp-probe']
    for name in names:
        for file in (E/name).rglob('*'):
            if not file.is_file(): continue
            if file.suffix in ['.png','.jpg','.mp4']: dest=OUT/'media/assessment'/file.relative_to(E)
            elif file.suffix in ['.log','.json','.md']:
                if file.suffix=='.log': assert not re.search(r'SCRIPT ERROR:|^ERROR:|ASSESSMENT FAIL',file.read_text(encoding='utf-8',errors='replace'),re.M),file
                dest=OUT/'verification/assessment'/file.relative_to(E)
            else: continue
            dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,dest)
    review=E/'visual-review.md';assert review.exists()
    shutil.copy2(review,OUT/'verification/assessment/visual-review.md')
    build_logs=OUT/'verification/assessment/build'
    build_logs.mkdir(parents=True,exist_ok=True)
    for name in ['import.log','rules.log','game-smoke-headless.log','input-checks.log','assessment-headless.log','viewmodel-headless.log','export.log']:
        file=ROOT/'artifacts'/name
        assert not re.search(r'SCRIPT ERROR:|^ERROR:|ASSESSMENT FAIL|SMOKE FAIL|INPUT FAIL|VIEWMODEL FAIL',file.read_text(encoding='utf-8',errors='replace'),re.M),file
        shutil.copy2(file,build_logs/name)
    shutil.copytree(ROOT/'射击游戏/assets/licenses',OUT/'licenses',dirs_exist_ok=True)
    (OUT/'media/README.md').write_text('# 实机媒体\n\n当前箱阵考核版本在 assessment/，包含布局、界面、对手和对战录像。其他目录均为历史版本；验证范围见根目录 VALIDATION.md。\n',encoding='utf-8')
    source=ROOT/'builds/RMPrecisionLab-godot-source.zip'
    with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in (ROOT/'射击游戏').rglob('*'):
            if file.is_file() and '.godot' not in file.parts: z.write(file,file.relative_to(ROOT).as_posix())
        for pattern in ['*.md','LICENSE','tools/*.py','tools/*.ps1','sdk/cpp/**/*']:
            for file in ROOT.glob(pattern):
                if file.is_file(): z.write(file,file.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(source) as z: assert z.testzip() is None
    portable=ROOT/'builds/RMPrecisionLab-windows-x64.zip';archive(OUT,portable)
    with zipfile.ZipFile(portable) as z: assert hashlib.sha256(z.read('RMPrecisionLab.exe')).hexdigest()==digest
    (ROOT/'builds/SHA256SUMS.txt').write_text('\n'.join(f'{sha(p)}  {p.relative_to(ROOT/"builds").as_posix()}' for p in [OUT/'RMPrecisionLab.exe',portable,source,ROOT/'builds/RMControl-cpp-sdk.zip'])+'\n',encoding='utf-8')
    print('PACKAGED',portable.stat().st_size,source.stat().st_size)
if __name__=='__main__': main()
