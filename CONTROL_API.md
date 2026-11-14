# 局域网视觉控制接口 · v1

Windows 游戏提供真实第一人称画面，Ubuntu C++ 程序负责自己的视觉算法。接口接管当前玩家的瞄准、单发和换弹。地图、开始／重开、WASD 走位与空格跳跃仍由人操作。本版没有人物识别算法，没有目标真值接口。

## 启动与连接

在解压后的 Windows 便携包目录打开终端并启动（替换口令）：

```powershell
.\RMPrecisionLab.exe -- --control --control-bind=0.0.0.0 --control-port=47650 --control-token=YOUR_TOKEN
```

源工程运行时在 Godot 可执行文件后加 `--path .\射击游戏`。普通启动不监听端口；开启接口必须提供非空口令。监听失败会打印原因并退出。口令用于局域网连接校验，通信不使用 TLS；只在可信局域网使用，不需要公网端口转发。

让 Ubuntu 和游戏电脑处于可互通的局域网，使用 Windows 的局域网 IPv4 地址连接。Windows 防火墙如果询问，允许此 EXE 在所用的专用网络通信；无需关闭整个防火墙。端口默认 47650，可修改。游戏 HUD 不增加接口数据显示。

Ubuntu 22.04／24.04 构建：

```bash
sudo apt update
sudo apt install build-essential cmake libopencv-dev
cmake -S sdk/cpp -B build/control -DCMAKE_BUILD_TYPE=Release
cmake --build build/control -j
ctest --test-dir build/control --output-on-failure
./build/control/rm_control_probe --host WINDOWS_IP --token YOUR_TOKEN --seconds 10
./build/control/rm_vision_template WINDOWS_IP YOUR_TOKEN
```

没有图形桌面时模板加 `--no-window`。只构建无 OpenCV 的联调工具可加 `-DRM_WITH_OPENCV=OFF`。默认模板只读取、显示画面；替换 `examples/vision_template.cpp` 的 `detect_target()` 后才会瞄准／射击。检测函数输入为 BGR `cv::Mat`，返回头部像素和是否请求单发；默认返回空，不内置模型、不猜测目标。`aim_at()` 使用画面内参和当时的玩家俯仰，把像素转换为角度增量。

联调指令（先在游戏中开始训练）：

```bash
./build/control/rm_control_probe --host WINDOWS_IP --token YOUR_TOKEN --seconds 10 --actions --output probe
```

联调模式会向右转 5°、向上转 3°、发射一发，再请求换弹。输出 `frame.jpg`、`frame.json` 和 `report.json`；报告含实际帧数、取图耗时和操作响应，不代表已实现自动识别。`--ping-only` 仅保活和读状态，供性能对照。

## C++ 调用约定

`rm_control::Client` 是同步、单请求、非线程安全的客户端。`connect(host, port, token)` 接管；`observe()` 返回 JPEG、内参和状态；`act(Action)` 调整视角并可单发；`reload()` 使用最近一次取图的上下文；`ping()` 保活；`disconnect()` 释放。正常循环不断取图即可保活，空闲时至少每秒调用一次 `ping()`。不要在同一客户端对象上并发调用。

```cpp
rm_control::Client client;
client.connect("192.168.1.20", 47650, "YOUR_TOKEN");
auto frame = client.observe();
// 以下像素应由你的检测算法给出。
auto action = rm_control::aim_at(frame, head_x, head_y, false);
auto result = client.act(action);
```

`act()` 返回独立的 `look_applied`、`fired`、`fire_error`；`ok=true` 不等于已发射。射速冷却、无弹或换弹可以拒绝开火而仍完成视角调整。每个 `fire=true` 最多尝试一发，没有持续扳机模式。网络异常会关闭客户端连接并抛异常，**不自动重试动作**；响应丢失时原动作可能已经执行，应重新连接和取图，不能盲目补发。

## 线上协议

TCP 字节流，一次消息格式为：`uint32_be JSON字节数` + `UTF-8 JSON` + `payload_bytes` 个二进制字节。JSON 头上限 16 KiB；请求不能携带二进制内容；图像响应上限由客户端限定为 8 MiB。必须循环处理部分发送、部分接收，不能把一次 `recv()` 当成一条消息。

每个请求包含 `v:1`、严格递增的正整数 `id`、`type`、`payload_bytes:0`。响应回显 `v`、`id`，含 `ok` 和 `payload_bytes`。请求编号在一次 TCP 连接内不能重复；重复、非法编号或协议版本会关闭连接。单连接最多一个未完成请求；服务端不堆积图像。示例：

```json
{"v":1,"id":1,"type":"hello","token":"YOUR_TOKEN","payload_bytes":0}
{"v":1,"id":2,"type":"observe","payload_bytes":0}
{"v":1,"id":3,"type":"act","frame_id":17,"round_id":2,"yaw_deg":5,"pitch_deg":3,"fire":true,"payload_bytes":0}
{"v":1,"id":4,"type":"reload","frame_id":17,"round_id":2,"payload_bytes":0}
{"v":1,"id":5,"type":"ping","payload_bytes":0}
{"v":1,"id":6,"type":"disconnect","payload_bytes":0}
```

- `hello` 必须是首个请求。错误口令为 `unauthorized`；已有控制器时为 `busy`。两者拒绝并关闭新连接，不影响现有控制器。
- `observe` 获取最新完成渲染的画面，包含当前枪械、基础 HUD 或菜单，**不包含箱阵雷达**。雷达只叠加在本地窗口；程序图像中该区域保留原始场景像素，不用黑块遮盖。JPEG 质量 0.85；保持窗口分辨率，最长边超过 1280 时等比缩小；最高 30 帧／秒。请求等待下一次允许的完成渲染帧，不返回历史队列。
- 图像头包含 `type:observation`、`frame_id`、`round_id`、`timestamp_us`、`width`、`height`、`encoding:jpeg`、`camera`、`state`。时间戳为服务器单调时钟，不可直接与另一台电脑的时钟相减。
- `camera` 包含像素单位的 `fx, fy, cx, cy`。图像左上为原点，x 向右、y 向下；针孔模型，无镜头畸变。中心为 `(width/2,height/2)`。解码后的尺寸和内参一起使用，不应用旧窗口尺寸计算。
- `state` 只包含自身信息：`round_id, phase, paused, game_time_s, remaining_s, settling, weapon, mag, reserve, reloading, can_fire, is_accurate, shot_count, yaw_deg, pitch_deg`。没有人物坐标、框、可见性、头部位置或世界碰撞结果。
- `act` 的角度为有限数值，单次水平范围 ±360°、俯仰增量范围 ±180°；正值向右、向上。玩家累计俯仰限制为 ±1.42 弧度。动作在物理更新中先调整视角，再通过现有武器控制器尝试发射。
- `reload` 返回 `reloaded` 和 `reload_error`，失败原因为 `reloading`、`no_reserve`、`mag_full` 或 `round_finishing`。`act` 的 `fire_error` 可能为 `cooldown`、`reloading`、`mag_empty`、`round_finishing`；未请求射击时为 `not_requested`，成功为空串。
- 非训练、暂停或过期上下文整体拒绝，分别为 `not_training`、`paused`、`stale_observation`；状态切换取消已收到的待执行动作，可能返回 `state_changed`／`resumed`。非法动作返回 `invalid_action`，未知命令为 `unknown_type`。

`frame_id` 必须是当前连接最近一次取图的编号，`round_id` 必须属于当前回合。回合变化、暂停、恢复、断连和重连会使旧画面失效，包括暂停中获取的画面；恢复后重新取图再控制。headless 模式不提供图像，返回 `image_unavailable`。

## 接管与原游戏规则

接管时只禁用训练中的人工鼠标瞄准、左键和 R；WASD、空格跳跃、菜单与 Esc 仍有效。已连接的控制器允许游戏失焦继续运行；Esc 暂停始终优先，接口仍能取图／读状态。断连或两秒无有效请求自动暂停并释放接管；点击继续可恢复人工操作，重新连接后需要重新取图。

人工操作下 AK、M4 支持长按连射，沙鹰保持单发；这不扩展网络控制语义，`act` 仍最多发射一发。接管或释放控制权都会清除人工长按状态，恢复人工操作后需要重新按下左键。空仓／提前换弹共用既定时长，自动选择对应双手动画和音效，协议无新增字段。

游戏仍按真实发射瞬间速度判定：落地且速度比低于 0.34 为精准子弹，否则（包括空中）为 20% 圆盘随机散布。只有头部命中击杀，身体无伤害但阻挡并计入命中。冷却、换弹、弹药、最后一发结算均走原游戏流程；失败点击不缓存补射。

## 依赖与验证边界

C++ SDK 使用随源码分发的 nlohmann/json 3.11.3（MIT，许可证在 `third_party/nlohmann/`）；OpenCV 4 由 Ubuntu 软件包或本地构建提供。协议自身不要求安装 OpenCV，游戏运行不需要 C++ 工具链或 OpenCV。

本机验证、C++ 联调、性能结果及 Ubuntu／实体 NUC 是否实际运行，见 `VALIDATION.md`。`--control-fixture`、`--control-smoke` 仅供仓库验证工具使用，不属于网络 API；网络命令无法选择地图、移动、开局或重开。

## 箱阵考核兼容性

箱阵对手的 AI 在游戏内部运行，接口仍只控制当前玩家。协议版本、取图及单次 act 开火语义不变；不增加地图种子、箱子布局、导航网格、bot 坐标或视线信息。死亡或弹尽先进入在途结算，结束后进入 results，并按阶段变化失效待执行动作。选择和生成地图仍在游戏准备页进行，接口不能启动或重建考核。


## 实体子弹与不限时状态

协议仍为 v1。`fired=true` 代表成功生成一颗实体子弹，**不代表已经命中**。弹速 25 m/s、直线飞行、最远 100 m／4 s；命中在到达头身区域时结算。`act` 不排队或自动补射，不能读取子弹位置或敌方内部状态。

`state.settling` 为新增布尔字段：已停止新射击／换弹，正在等待在途子弹。此时阶段仍是 training，`can_fire=false`；存活玩家可以调整视角，开火／换弹分别返回 `round_finishing`，已死亡玩家 `look_applied=false`。`remaining_s=-1` 表示箱阵训练及结果不限时；倒数仍从 3 开始，另外两图保留 60 秒。`game_time_s` 独立累计本轮训练时间（含在途结算），暂停时冻结，结果保留最终值，新回合清零；不要用 `60-remaining_s` 推算时间。

JSON 不含雷达、双方区域、敌方位置、地图网格或种子。客户端状态仍为可扩展 JSON，旧客户端忽略新增字段即可；算法须考虑真实飞行时间。Ubuntu NUC 跨机结果与本机 Windows 回环结果分别记录，见 VALIDATION.md。

## 方向雷达与战斗声音（2026-11-15）

左上角仅保留方向盘，上方代表当前朝向；琥珀扇区提示敌人在前后左右及四个斜方向之一，没有地图、通道、箱子、距离或高度。方位每 0.5 秒采样，转身即时改变相对方向，边界采用 5° 滞回；水平重合时显示无方向淡环。1280×720 下大小 140×140、边距 24；960×540 下 112×112、边距 16。雷达只在本地箱阵训练／在途结算显示，程序 JPEG 不含雷达。

子弹保持无重力的直线飞行，移动散布只影响初始方向。玩家在所有地图、bot 在箱阵具有脚步声，每实际落地水平移动 1.6 米触发一步；空中及原地顶墙不产生行走声，落地一次轻响。高台／木楼梯为木质声，其他地面为硬地声。敌方脚步为三维定位，24 米听距，遮挡额外降低 8 dB 并低通到约 1.8 kHz；不改变 bot 感知。

沙鹰为厚重低频冲击、AK 为爆裂音、M4 为短促机械音，每枪三个变体。脚步与枪声使用独立随机源，不影响射击散布。音效为原创合成 PCM，可运行 `python tools/prepare_combat_audio.py` 重建；未将合成音源描述为真实枪械录音。暂停冻结播放、重开清空，换弹及命中声继续复用。

音效仅在游戏本地播放；v1 协议仍传输 JPEG 与玩家状态，没有新增音频流或敌方声音事件。
