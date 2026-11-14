# RM 急停射击训练场

面向 RM 视觉组入门的 Windows 单机第一人称训练游戏，使用 Godot + GDScript。包含训练馆、原创“旧镇街区”和随机“箱阵考核”三张地图，三把免费枪械、第一人称双手及同步换弹动画。前两图为六靶训练，箱阵为一对一 bot 对战。

**只有爆头立即击杀；非头部命中无伤害，但阻挡子弹并计入命中。** 箱阵中的 bot 会主动寻找并攻击玩家，双方仅爆头致死。没有经济或护甲系统、多人联机、跳跃、蹲伏或冲刺。可选的局域网控制接口允许外部程序接管玩家瞄准、单发与换弹。

运行 `builds/windows/RMPrecisionLab.exe`，无需 Godot 或 Blender。便携包位于 `builds/RMPrecisionLab-windows-x64.zip`，源工程入口为 `射击游戏/project.godot`。最新结果见 [验证记录](VALIDATION.md)，外观规范见 [UI_DESIGN.md](UI_DESIGN.md)，素材来源见 [素材清单](ASSET_MANIFEST.md)。

便携包解压后直接运行根目录 `RMPrecisionLab.exe`。独立 C++ 源码包为 `builds/RMControl-cpp-sdk.zip`，也包含在游戏包的 `sdk/cpp/` 中。

本版已实现移动射击与 20% 随机散布。Windows 包内 `media/spread-demo.mp4` 展示移动射击与急停后精准射击的差别，并附对应截图及逐发记录。

## C++ 视觉程序接入

通过 `-- --control --control-token=YOUR_TOKEN` 启用接口，默认监听 IPv4 `0.0.0.0:47650`。普通启动不监听端口。Ubuntu 上的 C++ 程序可获取 JPEG 第一人称画面并发送视角角度增量、单发和换弹；不提供靶子坐标或检测框。你继续负责开局与 WASD，Esc 暂停始终优先。断连或两秒无有效请求会暂停并恢复人工接管能力。

客户端、OpenCV 算法接入模板和联调工具位于 `sdk/cpp/`；默认检测函数为空，不会自行射击。构建、局域网连接、协议及失效规则见 [CONTROL_API.md](CONTROL_API.md)。

## 游戏流程

主菜单 → 选择地图与枪械 → 3 秒倒数 → 60 秒训练 → 成绩结算。

准备页可反复选择地图与枪械，没有等待时间和费用；点击开始后锁定本轮配置。第一次启动默认“旧镇街区 + 沙鹰”，选择在本次启动期间保留，没有存档。

倒数期间不能移动、瞄准、开火或换弹，靶子静止。倒数结束后开始训练。时间结束或全部弹药用尽后结算；最后一发先处理命中与击杀，再显示成绩。“再练一轮”保留地图与枪械并恢复完整弹药、靶子和零成绩，重新倒数；“更换配置”回到准备页。

| 操作 | 功能 |
|---|---|
| WASD | 移动，松键自然减速，反向按键更快减速 |
| 鼠标 | 瞄准 |
| 左键 | AK、M4 可长按持续射击；沙鹰每次点击一发 |
| R | 手动换弹 |
| Esc | 暂停／继续；准备页返回菜单，操作说明返回原页 |
| Tab / Shift+Tab、Enter / Space | 菜单焦点移动与确认 |

B、E 没有游戏交互。切换到其他窗口会自动暂停。暂停冻结倒数、训练、移动、冷却、换弹及动画、靶子动作和刷新。暂停中打开操作说明不会继续计时。

## 界面

训练中仅保留顶部时间、右下弹夹／备弹、中央准星；换弹时弹药旁出现“换弹中”。停稳时准星收拢为暖白色，移动时展开为琥珀色；冷却、换弹或无弹时降低亮度，准星形态仍表达精度。非头部命中出现浅色标记，爆头为琥珀色标记。没有生命、速度、实时成绩、目标头顶编号或常驻操作说明。

结算仅显示击杀数、命中率及结束原因。命中率 = 命中靶子的发数 / 实际发射数；零分母为 0%。内部仍保留发射、命中和爆头计数用于规则验证。

## 地图

- **箱阵考核**：72 × 42 米长方形，玩家与一个 bot 分居长轴两端。中段三条至少 4 米宽的曲折主路、四条横向连接口；2 米立方体箱子堆叠 1～3 层。每次开始／重开改变道路拐角、连接位置和箱高，暂停恢复不换图。箱子不可破坏或推动，阻挡人物和子弹。

- **旧镇街区**：原创 48 × 44 米街区，以地中海小镇的石板街、旧灰泥、陶瓦、百叶窗、拱门和庭院为外观方向。围绕中央建筑可完整绕行；长街、弯巷和庭院各有一静一动两个人物。道路平坦，不需要跳跃。上层窗户、阳台和门是建筑装饰，不能进入。
- **训练馆**：保留原有室内灰盒训练场、通道、掩体和目标布置，适合固定视线的急停训练。

前两张训练地图各有三个静止靶和三个沿预设路线往返的移动靶。头部、躯干、颈部、上下臂、手、大腿、小腿及脚均配置骨骼跟随碰撞体。爆头后立即关闭命中区域，播放倒下动作，1 秒后恢复，不重复计分。

## 武器与规则

速度比 = 当前真实水平速度 / 正常最大移动速度。**移动时也可以开枪；速度比严格小于 0.34 时才精准命中准星中心。** 大于或等于 0.34 时每发独立随机散布，不随速度继续扩大；允许散布射击随机命中头部并击杀。

散布半径为沿原瞄准方向距离的 **20%**：在前方 10 米的垂直截面上，落点距离中心不超过 2 米；等效散布锥半角约 11.31°。使用圆盘均匀面积采样 `r = 0.2 × sqrt(U)`、`θ = 2πV`，将偏移转换为射线方向。精度读取实际发射瞬间的真实水平速度，低于门槛立即恢复，不增加恢复延迟。

仍须满足训练阶段、冷却结束、弹夹非空且未在换弹。被拒绝的短按不扣弹、不计射击次数、不排队补射，也不消耗散布随机数；步枪持续按住时按射速等待下一发，松开后不补射。精准射击同样不消耗随机数。射线最大长度仍为 100 米，由墙体及人物身体阻挡，不改变相机方向，不增加弹道下坠或累积后坐力。

| 免费武器 | 弹夹 / 备弹 | 射击间隔 | 换弹时间 |
|---|---:|---:|---:|
| 沙鹰 | 7 / 14 | 225 ms | 2.2 秒 |
| AK-47 | 25 / 50 | 100 ms | 2.5 秒 |
| M4A1 | 30 / 60 | 90 ms | 3.1 秒 |

玩家每回合总弹药为三个满弹夹。提前换弹保留余弹，只扣除补足所需备弹；备弹不足则装入剩余弹药。空弹夹且有备弹时自动换弹，满弹夹或无备弹不启动换弹。换弹中可移动、不能开火，结束时才补弹。

AK、M4 按住左键按各自射速持续射击，松开即停止；沙鹰长按只发射一发。手动或自动换弹都会结束本次持续射击，换弹完成后必须重新按下左键，换弹中的点击不会排队。暂停、结算、菜单和控制权切换也会清除长按状态。程序接口仍为一次 `act` 最多一发。

三枪使用统一绑定的战术长袖、全指手套双手，分别提供空仓与提前换弹动作。空仓换弹包含机械收尾，提前换弹省略该动作；两种动作均保持表中时长。取匣、插匣、机械收尾配有同步音效。动画与音效跟随换弹时钟，暂停时冻结，中断时复位；不改变镜头或命中判定。

移动最大速度 6 m/s，普通加速度 30 m/s²，松键减速度 12 m/s²，反向加速度 48 m/s²；物理频率 120 Hz。

## 开发结构

| 模块 | 职责 |
|---|---|
| `scripts/main.gd` | menu / setup / countdown / training / results，输入、射线和统计 |
| `scripts/game_hud.gd`、`reticle.gd` | Godot 原生界面、静态预览、几何准星与短暂反馈 |
| `scripts/arena.gd` | 地图目录与切换，一次只持有一张地图；训练图六靶、考核图独立对手 |
| `scripts/yard_layout.gd`、`assessment_yard.gd` | 随机道路、箱堆、网格寻路及场地生成 |
| `scripts/assessment_duel.gd`、`duel_bot.gd` | 考核胜负、玩家头身区域、对手感知与射击 |
| `scenes/maps/`、`scripts/*hall.gd`、`old_town.gd` | 地图几何、灯光、出生变换、目标路线和验证路径 |
| `scripts/map_geometry.gd` | 地图共享几何辅助函数 |
| `scripts/game_rules.gd`、`weapon_controller.gd` | 武器参数、射击许可、弹药和换弹时间；射击许可不依赖速度 |
| `scripts/shot_direction.gd` | 精度门槛与射线散布；由命中模块在实际发射时调用 |
| `scripts/player_controller.gd`、`weapon_view.gd` | 玩家、镜头、握持与换弹表现 |
| `scripts/training_target.gd`、`trainee_visual.gd` | 命中区域、运动端点、击杀刷新与人物表现 |
| `assets/models/`、`assets/town/`、`assets/ui/` | GLB、2K 地图材质、离线渲染的地图与枪械预览 |
| `tests/` | 规则、真实场景检查、实机录制与实时性能测量 |

地图提供 ID、名称、预览路径和出生位置／朝向；两张训练图另提供六组目标配置，考核图提供独立对手出生点及道路网格。目标配置含位置、朝向、移动类型及两个运动端点。地图切换释放旧地图节点、灯光与目标。界面通过信号提交选择，不结算伤害。`control_bridge.gd` 负责可选 TCP 接口、取图及控制权；外部射击仍通过原武器与命中流程。

## 运行、构建与素材重建

使用 **Godot 4.7.2 Standard**，无需 .NET。保留 Forward+、Windows D3D12、Jolt Physics。默认窗口 1280×720，最小 960×540；中文字体随包提供。在 Godot 导入 `射击游戏/project.godot`，完成导入后按 F5。

在仓库根目录运行：

```powershell
$godotExe = 'D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path '.\射击游戏' --editor --import --quit
& $godotExe --path '.\射击游戏'
& $godotExe --headless --path '.\射击游戏' --script res://tests/test_rules.gd
& $godotExe --headless --path '.\射击游戏' -- --smoke-test
# 首次构建需匹配的 Windows 模板
python -m pip install requests
python tools/fetch_windows_template.py
.\tools\build_windows.ps1 -GodotPath $godotExe
```

构建脚本导入、执行规则和场景检查、导出嵌入资源的 EXE，并复制文档与许可证。`licenses/` 必须随游戏分发。游戏及构建均不依赖素材网站在线服务。

素材已随工程提供，以下仅用于重新获取和制作：

```powershell
python tools/acquire_map_materials.py
python tools/acquire_visual_assets.py --blender
$blenderExe = '.\tools\cache\visuals\blender-4.5.3-windows-x64\blender.exe'
& $blenderExe --background --python-exit-code 1 --python tools/prepare_visuals.py
& $blenderExe --background --python-exit-code 1 --python tools/prepare_first_person.py
python tools/prepare_reload_audio.py
& $blenderExe --background --python-exit-code 1 --python tools/prepare_actor.py
& $godotExe --path '.\射击游戏' -- --previews "--capture-dir=$PWD/射击游戏/assets/ui"
& $godotExe --headless --path '.\射击游戏' --editor --import --quit
```

`--spread-demo --capture-dir=<绝对路径>` 生成移动射击与急停精准射击对比，可配合 `--write-movie` 录制；校准板、落点标记与标题只出现在演示模式，不改变正常游戏界面。

本次规则检查包含固定种子的 10,000 发圆盘分布检查；场景检查覆盖两图 × 三枪的精度边界、真实散布头身命中、墙体遮挡和最后一发结算。独立 EXE 使用 `-- --smoke-test --capture-dir=<绝对路径>` 可执行相同场景检查并保存画面，详见 `VALIDATION.md`。

`--showcase --capture-dir=<绝对路径>` 录制流程及地图截图；使用 Godot `--write-movie` 可输出固定步长 AVI。`--benchmark` 独立测量两图、两种尺寸，各预热 240 帧并测量 30 秒，包含行走与换弹。录制时的帧率不当作实时性能证据。

第一人称版本的检查与演示可通过以下命令重新执行（图形检查使用导出的 EXE）：

```powershell
python tools/update_asset_inventory.py
python tools/run_viewmodel_validation.py --engine builds/windows/RMPrecisionLab.exe --mode checks
python tools/run_viewmodel_validation.py --engine builds/windows/RMPrecisionLab.exe --mode captures
python tools/run_viewmodel_validation.py --engine builds/windows/RMPrecisionLab.exe --mode records
python tools/run_viewmodel_validation.py --engine builds/windows/RMPrecisionLab.exe --mode benchmark
python tools/run_export_regression.py
# 联调前按 sdk/cpp/README.md 构建 C++ 客户端到 artifacts/cpp-build
python tools/run_control_validation.py --game builds/windows/RMPrecisionLab.exe --export --case probe --resolution 1280x720 --out artifacts/first-person/cpp-probe
# 当前完整版本打包使用末尾“箱阵考核规则与复现”中的命令
```

结果存放于 `artifacts/first-person/`；打包前还需完成最终 EXE 的输入、完整流程和程序控制回归，并写入实际画面检查记录。模型制作源文件另附 `builds/RMPrecisionLab-first-person-source.zip`，包含三份可编辑 Blender 文件、制作脚本及许可证。GLB 动画采用 120 Hz 烘焙与导入，运行时无需 Blender。

## 许可证

项目代码与原创地图为 MIT；外部模型按各自许可证分发，参见 [ASSET_MANIFEST.md](ASSET_MANIFEST.md)。地图材质为 ambientCG CC0；字体为 Noto Sans SC / SIL OFL 1.1。Godot 声明见 `THIRD_PARTY_NOTICES.md`。新增素材支出为 0 元。


## 箱阵考核规则与复现

3 秒倒数后开始最多 60 秒的一对一对战，不循环刷新。击倒对手获胜、玩家被爆头失败；双方在同一物理帧发出的子弹均结算，同时死亡为平局。玩家弹尽且未击杀则失败，超时未击杀为未分胜负。最后一发击杀优先于弹尽和超时。

标准 bot：3.5 米／秒移动，120° 水平视野、45 米发现距离，0.45 秒连续可见反应时间；每轮三发点射、轮间 0.6 秒，瞄准偏差最大 1.2°，转向上限 180°／秒。必须停稳才开火；失去视线立即停火，仅记忆最后位置 2 秒。固定 AK、25 发弹匣、2.5 秒换弹、无限备弹；玩家弹药保持原规则。对手使用已有角色和枪械，持枪采用骨段长度约束，换弹有取匣表现。

地图采用同一整数网格生成几何和寻路，保留三条独立主路并连接相邻道路。每局布局指纹与上一局不同；固定种子仅用于本地检查：启动参数 `-- --assessment-seed=123`。这会有意重复同一布局，不用于普通随机训练。地图种子、箱堆、路径和 bot 坐标不进入 C++ 协议；死亡和重开使旧帧动作失效。

本轮检查与演示：

```powershell
python tools/run_assessment.py --export
python tools/run_assessment.py --export --size 960x540
python tools/run_assessment.py --export --mode demo
python tools/run_assessment.py --export --mode benchmark
python tools/run_assessment.py --export --mode benchmark --size 960x540
python tools/run_export_regression.py --out artifacts/assessment/regression
python tools/run_control_validation.py --game builds/windows/RMPrecisionLab.exe --export --case probe --map assessment_yard --resolution 1280x720 --out artifacts/assessment/cpp-probe
python tools/package_assessment.py
```

结果在 `artifacts/assessment/`，实际检查范围见 VALIDATION.md。便携包内本轮媒体在 `media/assessment/`；其他媒体为之前版本的历史记录。完整 Godot 源工程另打包为 `builds/RMPrecisionLab-godot-source.zip`。

性能验收目前为**独占环境待复测**：采样时另一款游戏同时占用显卡，保留诊断数据，但不据此确认稳定 60 FPS。已按用户选择先完成交付。
