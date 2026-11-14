"""Package the first-person release from this run's verified evidence."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "artifacts"
EVIDENCE = ART / "first-person"
OUT = ROOT / "builds/windows"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def valid_log(path):
    value = path.read_text(encoding="utf-8", errors="replace")
    assert not re.search(r"SCRIPT ERROR:|^ERROR:|SMOKE FAIL|INPUT FAIL|VIEWMODEL FAIL|^FAIL", value, re.M), path
    return value


def archive(source, path):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for file in sorted(source.rglob("*")):
            if file.is_file():
                output.write(file, file.relative_to(source).as_posix())
    with zipfile.ZipFile(path) as result:
        assert result.testzip() is None


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    exe = OUT / "RMPrecisionLab.exe"
    exe_hash = sha(exe)
    regression = read_json(EVIDENCE / "export-regression.json")
    assert regression["exe_sha256"] == exe_hash and len(regression["runs"]) == 6
    assert (EVIDENCE / "visual-review.md").is_file()
    logs = ["rules.log", "game-smoke-headless.log", "input-checks.log", "viewmodel-headless.log", "import.log", "export.log"]
    for name in logs:
        valid_log(ART / name)
    for path in EVIDENCE.rglob("game.log"):
        valid_log(path)
    checks = [read_json(EVIDENCE / f"checks-{size}/viewmodel-checks.json") for size in [1280, 960]]
    assert all(c["failures"] == 0 for c in checks)
    probe = valid_log(EVIDENCE / "cpp-probe/client.log")
    assert "CPP PROBE PASS:" in probe, probe
    probe_report = read_json(EVIDENCE / "cpp-probe/report.json")
    assert probe_report["frames"] > 0 and len(probe_report["actions"]) == 2
    assert probe_report["actions"][0]["fired"] and probe_report["actions"][0]["look_applied"]
    assert probe_report["actions"][1]["reloaded"]
    perf = []
    for size in [1280, 960]:
        reports = read_json(EVIDENCE / f"benchmark-{size}/performance.json")
        assert len(reports) == 2
        assert all(r["seconds"] >= 30 and r["shots"] > 0 and r["reloads_in_map"] > 0 for r in reports)
        assert all(r["resolution"] == [size, size * 9 // 16] for r in reports)
        perf.extend(reports)
    movies = []
    for weapon in ["deagle", "ak47", "m4a1"]:
        for kind in ["empty", "tactical"]:
            for speed in [1, 4]:
                path = EVIDENCE / f"{weapon}-{kind}-{speed}x/demo.mp4"
                assert path.stat().st_size > 10000
                movie_report = read_json(path.with_name("demo.json"))
                assert movie_report["mag_after"] > 0 and movie_report["reload_game_ms"] >= movie_report["reload_ms"] - 0.01
                expected_frames = movie_report["reload_ms"] / 1000 * speed * 60
                assert abs(movie_report["reload_frames"] - expected_frames) <= 4
                movies.append(path)
    movies.append(EVIDENCE / "hold-fire/demo.mp4")
    assert movies[-1].stat().st_size > 10000
    rows = "\n".join(f"| {r['map']} | {r['resolution']} | {r['seconds']:.2f} | {r['mean_fps']:.2f} | {r['p95_ms']:.2f} | {r['shots']} | {r['reloads_in_map']} |" for r in perf)
    totals = ", ".join(str(c["checks"]) for c in checks)
    regression_rows = "\n".join(f"| {r['test']} | {r['resolution']} | {'; '.join(r['summary'])} |" for r in regression["runs"])
    report = f"""# 验证记录 · 2026-11-14

对应第一人称双手、六套换弹表现与步枪持续射击版本。Windows EXE SHA256：`{exe_hash}`。

## 自动化与实机检查

- 构建执行规则、完整场景、持续射击输入与换弹稠密轨迹检查，均通过；原始日志位于 `verification/`。
- 最终 EXE 在 1280×720、960×540 下的双手检查分别通过 {totals} 项，失败数均为 0。每枪空仓／提前换弹按 120 Hz 采样，检查接触点、接触朝向、骨长、交接连续性与待机复位；实际最大误差见对应 `viewmodel-checks.json`。
- 输入检查覆盖两图三枪、步枪长按、沙鹰单发、松开停止、冷却、换弹期间拒绝、换弹后需重按、暂停、控制权切换和重开。射击仍通过真实武器、射线和统计流程。
- 换弹检查验证实际控制器末尾补弹、手动／自动动作选择、音效事件不重复、暂停续播、中断归位；网络动作继续一次最多一发。

所有自动化结果为实际运行记录；不代表真人长时间试玩。画面验收说明与尚存限制见 `verification/first-person/visual-review.md`。

| 最终 EXE 回归 | 分辨率 | 实际结果 |
|---|---|---|
{regression_rows}

## 实时性能

每图预热后连续测量至少 30 秒，包含移动、六靶运行、持续射击及换弹。下列测量独立于固定步长录像。

| 地图 | 分辨率 | 秒 | 平均 FPS | P95 帧间隔 ms | 发射数 | 换弹数 |
|---|---|---:|---:|---:|---:|---:|
{rows}

GPU：{perf[0]['gpu']}。原始帧间隔汇总还包含 P99 与最差值，不把平均帧率视为所有帧均稳定。本机结果不代表其他设备。

表中分辨率取同次测量结束后由视口实际导出的 PNG 尺寸。小窗口下 `ViewportTexture.get_width()` 返回 720×405，而 `get_image()` 导出的画面为 960×540；报告保留 `texture_reported_resolution` 原值及对应图片路径。FPS、帧数与时间均保留实测值。

## 画面与演示

`media/first-person/` 包含两图、两种分辨率的持枪与换弹关键帧，三枪改动前后的待机图，六套换弹各自正常速度与四分之一速度录像，以及步枪长按射击演示。录像来自本轮 Windows EXE，采用固定 60 FPS 输出；慢放只用于观察动作，不改变正常游戏换弹时长。

声音为本项目原创合成机械音，不是实枪录音。双手素材、修改和许可证见 ASSET_MANIFEST；可编辑 Blender 文件另附 `RMPrecisionLab-first-person-source.zip`。

## 程序控制回归与边界

本轮程序控制回归日志在 `verification/first-person/`，使用 Windows 本机回环；未执行实体 Ubuntu NUC 跨机检查。协议、相机内参、每请求最多一发及画面来源保持原有含义。先前版本验证记录保留在 `verification/previous-control-validation.md`，仅作为历史记录，不充当本轮结果。

另实际运行 C++ 联调客户端，对最终 EXE 执行取图、角度转动、单发和换弹。{probe_report['seconds']:.2f} 秒取得 {probe_report['frames']} 帧，平均 {probe_report['frames_per_second']:.2f} 帧／秒；取图平均往返 {probe_report['mean_observe_ms']:.2f} ms、P95 为 {probe_report['p95_observe_ms']:.2f} ms。结果见 `verification/first-person/cpp-probe/client.log`，动作响应与延迟明细见同目录 `report.json`；这组取图速率不等于上表未连接控制器时的游戏 FPS。
"""
    previous = ROOT / "VALIDATION.md"
    history = OUT / "verification/previous-control-validation.md"
    history.parent.mkdir(parents=True, exist_ok=True)
    if not history.exists():
        shutil.copy2(previous, history)
    previous.write_text(report, encoding="utf-8")
    for name in ["README.md", "ASSET_MANIFEST.md", "VALIDATION.md", "UI_DESIGN.md", "CONTROL_API.md", "LICENSE"]:
        shutil.copy2(ROOT / name, OUT / name)
    media = OUT / "media/first-person"
    verification = OUT / "verification/first-person"
    for folder in [media, verification]:
        folder.mkdir(parents=True, exist_ok=True)
    for name in logs:
        shutil.copy2(ART / name, OUT / "verification" / name)
    for source in EVIDENCE.rglob("*"):
        if not source.is_file():
            continue
        relative = source.relative_to(EVIDENCE)
        if source.suffix.lower() in [".png", ".jpg", ".jpeg", ".mp4"]:
            dest = media / relative
        elif source.suffix.lower() in [".json", ".log", ".md"]:
            dest = verification / relative
        else:
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
    before = media / "before"
    before.mkdir(exist_ok=True)
    for weapon in ["deagle", "ak47", "m4a1"]:
        shutil.copy2(ART / f"control-final-1280/{weapon}-idle.png", before / f"{weapon}-idle.png")
    (OUT / "media/README.md").write_text("""# 实机画面

本轮第一人称版本的截图与录像在 `first-person/`：

- `captures-1280/`、`captures-960/`：两图三枪待机及六套换弹关键帧。
- `*-empty-1x/`、`*-tactical-1x/`：空仓与提前换弹正常速度录像。
- `*-empty-4x/`、`*-tactical-4x/`：四分之一速度录像。
- `hold-fire/`：步枪持续射击与换弹后重新按下的演示。
- `gameplay-*`：完整流程、说明页与规则回归画面。
- `before/`：改动前的三枪待机图，明确作为对照。

本目录其他旧文件为此前移动散布与控制接口版本的历史演示，不能当作本轮双手模型的画面证据。当前性能与验证范围见根目录 VALIDATION.md。
""", encoding="utf-8")
    shutil.copytree(ROOT / "射击游戏/assets/licenses", OUT / "licenses", dirs_exist_ok=True)
    source_archive = ROOT / "builds/RMPrecisionLab-first-person-source.zip"
    with zipfile.ZipFile(source_archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for path in sorted((ROOT / "tools/source/first_person").iterdir()):
            if path.suffix in [".blend", ".md"]:
                output.write(path, path.relative_to(ROOT).as_posix())
        for name in ["normalized_deagle.glb", "normalized_ak47.glb", "normalized_m4a1.glb", "djmaesen_smg45_animated_reload_arms.glb"]:
            path = ROOT / "tools/cache/visuals" / name
            output.write(path, path.relative_to(ROOT).as_posix())
        for path in [ROOT / "tools/prepare_first_person.py", ROOT / "tools/prepare_reload_audio.py", ROOT / "tools/prepare_visuals.py", ROOT / "tools/acquire_visual_assets.py", ROOT / "tools/update_asset_inventory.py", ROOT / "README.md", ROOT / "ASSET_MANIFEST.md", ROOT / "LICENSE"]:
            output.write(path, path.relative_to(ROOT).as_posix())
        for path in (ROOT / "射击游戏/assets/licenses").glob("*"):
            if path.is_file():
                output.write(path, path.relative_to(ROOT).as_posix())
        output.writestr("SOURCE_README.md", """# 第一人称制作源文件

三份 `tools/source/first_person/*.blend` 已内嵌贴图，可用 Blender 4.5.3 直接打开编辑。将本包解压到 Godot 源工程根目录后，使用 Blender 执行 `tools/prepare_first_person.py` 可从随包提供的规范化枪械和原始手套输入重新制作六套动作；执行 `python tools/prepare_reload_audio.py` 重建原创音效。

工具输入保留原作者署名和许可，见 ASSET_MANIFEST.md 与 `射击游戏/assets/licenses/`。Blender 本身未随包分发，游戏运行无需安装它。
""")
    with zipfile.ZipFile(source_archive) as source_zip:
        assert source_zip.testzip() is None
        assert len([n for n in source_zip.namelist() if n.endswith(".blend")]) == 3
    portable = ROOT / "builds/RMPrecisionLab-windows-x64.zip"
    archive(OUT, portable)
    with zipfile.ZipFile(portable) as package:
        assert hashlib.sha256(package.read("RMPrecisionLab.exe")).hexdigest() == exe_hash
    (ROOT / "builds/SHA256SUMS.txt").write_text("\n".join(f"{sha(path)}  {path.relative_to(ROOT / 'builds').as_posix()}" for path in [exe, portable, source_archive, ROOT / "builds/RMControl-cpp-sdk.zip"]) + "\n", encoding="utf-8")
    print(f"Packaged {portable.stat().st_size / 1024 ** 2:.1f} MiB; source {source_archive.stat().st_size / 1024 ** 2:.1f} MiB")


if __name__ == "__main__":
    main()
