# 验证记录 · 2026-11-14

对应第一人称双手、六套换弹表现与步枪持续射击版本。Windows EXE SHA256：`8e0042608199ad04bdba34c15654684c60b3a2dfbe1d20910b2819f013a13797`。

## 自动化与实机检查

- 构建执行规则、完整场景、持续射击输入与换弹稠密轨迹检查，均通过；原始日志位于 `verification/`。
- 最终 EXE 在 1280×720、960×540 下的双手检查分别通过 861, 860 项，失败数均为 0。每枪空仓／提前换弹按 120 Hz 采样，检查接触点、接触朝向、骨长、交接连续性与待机复位；实际最大误差见对应 `viewmodel-checks.json`。
- 输入检查覆盖两图三枪、步枪长按、沙鹰单发、松开停止、冷却、换弹期间拒绝、换弹后需重按、暂停、控制权切换和重开。射击仍通过真实武器、射线和统计流程。
- 换弹检查验证实际控制器末尾补弹、手动／自动动作选择、音效事件不重复、暂停续播、中断归位；网络动作继续一次最多一发。

所有自动化结果为实际运行记录；不代表真人长时间试玩。画面验收说明与尚存限制见 `verification/first-person/visual-review.md`。

| 最终 EXE 回归 | 分辨率 | 实际结果 |
|---|---|---|
| gameplay | 1280x720 | SMOKE PASS: 860 integration checks (0 failures) |
| input | 1280x720 | PASS: 166 input checks; failures: 0 |
| network | 1280x720 | CONTROL PASS: 149 checks (0 failures) |
| gameplay | 960x540 | SMOKE PASS: 860 integration checks (0 failures) |
| input | 960x540 | PASS: 166 input checks; failures: 0 |
| network | 960x540 | CONTROL PASS: 149 checks (0 failures) |

## 实时性能

每图预热后连续测量至少 30 秒，包含移动、六靶运行、持续射击及换弹。下列测量独立于固定步长录像。

| 地图 | 分辨率 | 秒 | 平均 FPS | P95 帧间隔 ms | 发射数 | 换弹数 |
|---|---|---:|---:|---:|---:|---:|
| training_hall | [1280, 720] | 30.00 | 240.01 | 5.34 | 32 | 4 |
| old_town | [1280, 720] | 30.00 | 240.01 | 5.35 | 32 | 4 |
| training_hall | [960, 540] | 30.01 | 239.99 | 5.32 | 32 | 4 |
| old_town | [960, 540] | 30.00 | 239.97 | 5.33 | 32 | 4 |

GPU：NVIDIA GeForce RTX 5070 Laptop GPU。原始帧间隔汇总还包含 P99 与最差值，不把平均帧率视为所有帧均稳定。本机结果不代表其他设备。

表中分辨率取同次测量结束后由视口实际导出的 PNG 尺寸。小窗口下 `ViewportTexture.get_width()` 返回 720×405，而 `get_image()` 导出的画面为 960×540；报告保留 `texture_reported_resolution` 原值及对应图片路径。FPS、帧数与时间均保留实测值。

## 画面与演示

`media/first-person/` 包含两图、两种分辨率的持枪与换弹关键帧，三枪改动前后的待机图，六套换弹各自正常速度与四分之一速度录像，以及步枪长按射击演示。录像来自本轮 Windows EXE，采用固定 60 FPS 输出；慢放只用于观察动作，不改变正常游戏换弹时长。

声音为本项目原创合成机械音，不是实枪录音。双手素材、修改和许可证见 ASSET_MANIFEST；可编辑 Blender 文件另附 `RMPrecisionLab-first-person-source.zip`。

## 程序控制回归与边界

本轮程序控制回归日志在 `verification/first-person/`，使用 Windows 本机回环；未执行实体 Ubuntu NUC 跨机检查。协议、相机内参、每请求最多一发及画面来源保持原有含义。先前版本验证记录保留在 `verification/previous-control-validation.md`，仅作为历史记录，不充当本轮结果。

另实际运行 C++ 联调客户端，对最终 EXE 执行取图、角度转动、单发和换弹。10.01 秒取得 150 帧，平均 14.98 帧／秒；取图平均往返 66.41 ms、P95 为 77.34 ms。结果见 `verification/first-person/cpp-probe/client.log`，动作响应与延迟明细见同目录 `report.json`；这组取图速率不等于上表未连接控制器时的游戏 FPS。
