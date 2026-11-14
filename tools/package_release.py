"""Package the verified projectile + local radar release and matching evidence."""
from pathlib import Path
import hashlib, json, re, shutil, zipfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'builds/windows'
E=ROOT/'artifacts/projectile'
R=ROOT/'artifacts/radar'

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf-8'))
def archive(root,destination):
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for path in sorted(root.rglob('*')):
            if path.is_file(): z.write(path,path.relative_to(root).as_posix())
    with zipfile.ZipFile(destination) as z: assert z.testzip() is None

def main():
    digest=sha(OUT/'RMPrecisionLab.exe')
    evidence=[]
    counts={}
    for size in ['1280x720','960x540']:
        for kind,folder in [('projectile',E/f'checks-{size}'),('radar',R/f'radar-{size}')]:
            assert read(folder/'build.json')['exe_sha256']==digest,folder
            report=read(folder/'checks.json');assert report['failures']==0,folder
            counts[kind+size]=report['checks'];evidence.append((kind,folder))
    demo=E/'demo-1280x720'
    assert read(demo/'build.json')['exe_sha256']==digest
    assert read(demo/'checks.json')['failures']==0
    combat=read(demo/'demo.json')
    assert combat['player_shots']>0 and combat['bot_shots']>0 and combat['phase']=='results'
    assert (demo/'demo.mp4').stat().st_size>10000
    evidence.append(('projectile',demo))
    regression=read(E/'regression/export-regression.json')
    assert regression['exe_sha256']==digest and len(regression['runs'])==6
    assert all(any('PASS' in s for s in run['summary']) for run in regression['runs'])
    evidence.append(('projectile',E/'regression'))
    probe=read(E/'cpp-probe/report.json')
    assert read(E/'cpp-probe/build.json')['exe_sha256']==digest
    assert probe['actions'][0]['fired'] and probe['actions'][1]['reloaded']
    evidence.append(('projectile',E/'cpp-probe'))
    review=E/'visual-review.md';assert review.exists()
    historical=OUT/'verification/previous-assessment-validation.md'
    if not historical.exists(): shutil.copy2(ROOT/'VALIDATION.md',historical)
    regress='\n'.join(f"- {run['test']} {run['resolution']}: {'; '.join(run['summary'])}" for run in regression['runs'])
    report=f"""# 验证记录 · 模糊雷达与实体子弹

验证日期：2026-11-15。最终 Windows EXE SHA256：`{digest}`。

## 已完成并实际验证

- [x] 箱阵左上角模糊雷达：双方 4 米区域中心、0.5 秒更新、隔墙显示；高度不影响位置，同区空心／实心标记可辨。暂停冻结并隐藏，继续刷新，死亡移除，重开清空。其他地图与菜单不显示。
- [x] 单一三维渲染，雷达仅合成到本地窗口；实际 TCP JPEG 取得下方完整场景，未加入坐标、雷达或地图 JSON 字段。比较同一静止场景的窗口、内层视口和网络 JPEG；尺寸、RGB 方向、相机内参检查通过。
- [x] 实体子弹 25 m/s、直径 2 cm、直线飞行；头部命中击杀，身体阻挡零伤害。覆盖 2 mm 薄墙扫掠、初始重叠、运动头部、最长 4 秒、暂停冻结、最后一发及在途互杀。
- [x] 镜头附近尾迹亮条定位并修复：原先仅检查弹体位置，现检查整段 0.75 米尾迹与镜头距离；逻辑检查及实机复现场景均通过。
- [x] 跳跃约 1 米、长按不连跳、顶头阻挡、人物实体走位碰撞；空中射击散布，落地停稳精准。
- [x] 1,000 个种子的连通性、三条 4 米主路、四个连接口和平台变化；10 个实际生成地图的双入口三维导航，以及玩家正常移动输入、bot 控制器上下高台。属于自动化路线检查，不等于真人逐路试玩。
- [x] 箱阵模拟超过 180 秒不结束且隐藏时钟；训练馆／旧镇保持 60 秒。停止新射击后等待在途子弹，最后一发击杀优先，暂停和重开清空状态。
- [x] 三图 × 三枪实体头身命中；两训练图 × 三枪精度、连射、换弹、输入与统计回归。箱阵另覆盖三枪程序发射及结算拒绝。

## 最终独立 EXE

| 检查 | 1280×720 | 960×540 |
|---|---:|---:|
| 实体子弹／跳跃／高台 | {counts['projectile1280x720']} 项，0 失败 | {counts['projectile960x540']} 项，0 失败 |
| 雷达／窗口输入／显示隔离 | {counts['radar1280x720']} 项，0 失败 | {counts['radar960x540']} 项，0 失败 |

{regress}

构建前的规则、流程、输入、实体场景、雷达与模型检查日志在 `verification/projectile/build/`。无窗口检查不作为画面或性能证据；图形结果来自最终导出的独立 EXE。测试固定布景及时间推进用于规则验证，正常游戏没有测试标记或额外 HUD。

## C++ 客户端

Windows 本机回环联调实际取得 {probe['frames']} 帧，{probe['frames_per_second']:.2f} 帧／秒，平均取图往返 {probe['mean_observe_ms']:.2f} ms；指定角度转动、单发与换弹成功。这不是 Ubuntu NUC 跨机测试，也不是人物识别算法结果。SDK 算法入口仍默认不识别、不射击。

## 媒体与目视范围

当前媒体为 `media/projectile/`、`media/radar/`，包括三维地图、跳跃、高台交火、子弹飞行及四分之一速度侧视片段；`regression/network-*/radar-local.png` 与 `radar-program.jpg` 是本地窗口／真实网络取图对照。演示由脚本安排布景，使用正常控制器、碰撞和射击流程；不是人工游玩录像。具体截图抽查在 `verification/projectile/visual-review.md`。

其余 assessment、first-person、control、spread 等目录是此前版本的历史证据，不作为本轮验收。第一人称模型和六套换弹素材本轮未重制，原制作文件包继续提供。

## 明确保留的未执行项

- [ ] 独占显卡环境的稳定约 60 FPS 验收。遵照用户“先完成交付，独占环境待复测”的选择，本轮没有关闭其他游戏，也未将历史共享 GPU 性能样本冒充本版结果。工具支持预热后每布局至少 30 秒采样。
- [ ] 实际 Ubuntu 22.04／24.04 NUC 跨机网络、延迟及算法联调；本机回环不能替代。
- [ ] 真人长时间逐路试玩及本轮音效听觉验收。已执行的自动输入、脚本演示与截图抽查不能替代这些项目。

交付源工程、Windows EXE／便携包、C++ SDK、README、视觉规范、接口文档、素材清单与本记录。游戏无需安装 Godot 或 Blender。新增素材支出 0 元。
"""
    (ROOT/'VALIDATION.md').write_text(report,encoding='utf-8')
    for name in ['README.md','VALIDATION.md','UI_DESIGN.md','ASSET_MANIFEST.md','CONTROL_API.md','LICENSE']:
        shutil.copy2(ROOT/name,OUT/name)
    for kind,folder in evidence:
        for file in folder.rglob('*'):
            if not file.is_file(): continue
            if file.suffix in ['.png','.jpg','.mp4']: dest=OUT/'media'/kind/file.relative_to(folder.parent)
            elif file.suffix in ['.log','.json','.md']:
                if file.suffix=='.log': assert not re.search(r'SCRIPT ERROR:|^ERROR:|PROJECTILE FAIL|SMOKE FAIL|CONTROL FAIL|INPUT FAIL',file.read_text(encoding='utf-8',errors='replace'),re.M),file
                dest=OUT/'verification'/kind/file.relative_to(folder.parent)
            else: continue
            dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,dest)
    shutil.copy2(review,OUT/'verification/projectile/visual-review.md')
    logs=OUT/'verification/projectile/build';logs.mkdir(parents=True,exist_ok=True)
    for name in ['import.log','rules.log','game-smoke-headless.log','input-checks.log','projectile-headless.log','radar-headless.log','viewmodel-headless.log','export.log']:
        file=ROOT/'artifacts'/name
        assert not re.search(r'SCRIPT ERROR:|^ERROR:|PROJECTILE FAIL|SMOKE FAIL|INPUT FAIL|VIEWMODEL FAIL',file.read_text(encoding='utf-8',errors='replace'),re.M),file
        shutil.copy2(file,logs/name)
    shutil.copytree(ROOT/'sdk/cpp',OUT/'sdk/cpp',dirs_exist_ok=True)
    shutil.copytree(ROOT/'射击游戏/assets/licenses',OUT/'licenses',dirs_exist_ok=True)
    (OUT/'media/README.md').write_text('# 实机媒体\n\n当前版本：projectile/、radar/。其余目录是历史版本，不能用于本轮验收。完整范围见根目录 VALIDATION.md。\n',encoding='utf-8')
    sdk=ROOT/'builds/RMControl-cpp-sdk.zip'
    with zipfile.ZipFile(sdk,'w',zipfile.ZIP_DEFLATED) as z:
        for file in (ROOT/'sdk/cpp').rglob('*'):
            if file.is_file(): z.write(file,file.relative_to(ROOT/'sdk').as_posix())
        z.write(ROOT/'CONTROL_API.md','CONTROL_API.md')
    with zipfile.ZipFile(sdk) as z: assert z.testzip() is None
    source=ROOT/'builds/RMPrecisionLab-godot-source.zip'
    with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in (ROOT/'射击游戏').rglob('*'):
            if file.is_file() and '.godot' not in file.parts: z.write(file,file.relative_to(ROOT).as_posix())
        for pattern in ['*.md','LICENSE','tools/*.py','tools/*.ps1','sdk/cpp/**/*']:
            for file in ROOT.glob(pattern):
                if file.is_file(): z.write(file,file.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(source) as z: assert z.testzip() is None
    # Keep the unchanged editable models while refreshing their accompanying docs.
    models=ROOT/'builds/RMPrecisionLab-first-person-source.zip'
    revised=models.with_suffix('.tmp.zip')
    with zipfile.ZipFile(models) as old, zipfile.ZipFile(revised,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as new:
        for info in old.infolist():
            data=(ROOT/info.filename).read_bytes() if info.filename in ['README.md','ASSET_MANIFEST.md'] else old.read(info.filename)
            new.writestr(info,data)
    with zipfile.ZipFile(revised) as z:
        assert z.testzip() is None
        assert len([n for n in z.namelist() if n.endswith('.blend')])==3
    revised.replace(models)
    portable=ROOT/'builds/RMPrecisionLab-windows-x64.zip';archive(OUT,portable)
    with zipfile.ZipFile(portable) as z: assert hashlib.sha256(z.read('RMPrecisionLab.exe')).hexdigest()==digest
    files=[OUT/'RMPrecisionLab.exe',portable,source,sdk,ROOT/'builds/RMPrecisionLab-first-person-source.zip']
    (ROOT/'builds/SHA256SUMS.txt').write_text('\n'.join(f'{sha(p)}  {p.relative_to(ROOT/"builds").as_posix()}' for p in files)+'\n',encoding='utf-8')
    print('PACKAGED',portable.stat().st_size,source.stat().st_size)
if __name__=='__main__': main()
