# RM 急停射击训练场

面向 RM 视觉组入门的 Windows 单机第一人称训练游戏，使用 Godot + GDScript。包含训练馆和原创“旧镇街区”两张地图，三把免费枪械、第一人称双手及同步换弹动画、六个人形训练靶。

**只有爆头立即击杀；非头部命中无伤害，但阻挡子弹并计入命中。** 没有经济或护甲系统，没有玩家受攻击、AI、联网、跳跃、蹲伏或冲刺。

运行 `builds/windows/RMPrecisionLab.exe`，无需 Godot 或 Blender。便携包位于 `builds/RMPrecisionLab-windows-x64.zip`，源工程入口为 `射击游戏/project.godot`。最新结果见 [验证记录](VALIDATION.md)，外观规范见 [UI_DESIGN.md](UI_DESIGN.md)，素材来源见 [素材清单](ASSET_MANIFEST.md)。

本版已实现移动射击与 20% 随机散布。Windows 包内 `media/spread-demo.mp4` 展示移动射击与急停后精准射击的差别，并附对应截图及逐发记录。

## 游戏流程

主菜单 → 选择地图与枪械 → 3 秒倒数 → 60 秒训练 → 成绩结算。

准备页可反复选择地图与枪械，没有等待时间和费用；点击开始后锁定本轮配置。第一次启动默认“旧镇街区 + 沙鹰”，选择在本次启动期间保留，没有存档。

倒数期间不能移动、瞄准、开火或换弹，靶子静止。倒数结束后开始训练。时间结束或全部弹药用尽后结算；最后一发先处理命中与击杀，再显示成绩。“再练一轮”保留地图与枪械并恢复完整弹药、靶子和零成绩，重新倒数；“更换配置”回到准备页。

| 操作 | 功能 |
|---|---|
| WASD | 移动，松键自然减速，反向按键更快减速 |
| 鼠标 | 瞄准 |
| 左键 | 每次点击最多尝试发射一发 |
| R | 手动换弹 |
| Esc | 暂停／继续；准备页返回菜单，操作说明返回原页 |
| Tab / Shift+Tab、Enter / Space | 菜单焦点移动与确认 |

B、E 没有游戏交互。切换到其他窗口会自动暂停。暂停冻结倒数、训练、移动、冷却、换弹及动画、靶子动作和刷新。暂停中打开操作说明不会继续计时。

## 界面

训练中仅保留顶部时间、右下弹夹／备弹、中央准星；换弹时弹药旁出现“换弹中”。停稳时准星收拢为暖白色，移动时展开为琥珀色；冷却、换弹或无弹时降低亮度，准星形态仍表达精度。非头部命中出现浅色标记，爆头为琥珀色标记。没有生命、速度、实时成绩、目标头顶编号或常驻操作说明。

结算仅显示击杀数、命中率及结束原因。命中率 = 命中靶子的发数 / 实际发射数；零分母为 0%。内部仍保留发射、命中和爆头计数用于规则验证。

## 地图

- **旧镇街区**：原创 48 × 44 米街区，以地中海小镇的石板街、旧灰泥、陶瓦、百叶窗、拱门和庭院为外观方向。围绕中央建筑可完整绕行；长街、弯巷和庭院各有一静一动两个人物。道路平坦，不需要跳跃。上层窗户、阳台和门是建筑装饰，不能进入。
- **训练馆**：保留原有室内灰盒训练场、通道、掩体和目标布置，适合固定视线的急停训练。

两图各有三个静止靶和三个沿预设路线往返的移动靶。头部、躯干、颈部、上下臂、手、大腿、小腿及脚均配置骨骼跟随碰撞体。爆头后立即关闭命中区域，播放倒下动作，1 秒后恢复，不重复计分。

## 武器与规则

速度比 = 当前真实水平速度 / 正常最大移动速度。**移动时也可以开枪；速度比严格小于 0.34 时才精准命中准星中心。** 大于或等于 0.34 时每发独立随机散布，不随速度继续扩大；允许散布射击随机命中头部并击杀。

散布半径为沿原瞄准方向距离的 **20%**：在前方 10 米的垂直截面上，落点距离中心不超过 2 米；等效散布锥半角约 11.31°。使用圆盘均匀面积采样 `r = 0.2 × sqrt(U)`、`θ = 2πV`，将偏移转换为射线方向。精度读取实际发射瞬间的真实水平速度，低于门槛立即恢复，不增加恢复延迟。

仍须满足训练阶段、冷却结束、弹夹非空且未在换弹。被拒绝的点击不扣弹、不计射击次数、不排队补射，也不消耗散布随机数；精准射击同样不消耗随机数。射线最大长度仍为 100 米，由墙体及人物身体阻挡，不改变相机方向，不增加弹道下坠或累积后坐力。

| 免费武器 | 弹夹 / 备弹 | 射击间隔 | 换弹时间 |
|---|---:|---:|---:|
| 沙鹰 | 7 / 14 | 225 ms | 2.2 秒 |
| AK-47 | 25 / 50 | 100 ms | 2.5 秒 |
| M4A1 | 30 / 60 | 90 ms | 3.1 秒 |

每回合总弹药为三个满弹夹。提前换弹保留余弹，只扣除补足所需备弹；备弹不足则装入剩余弹药。空弹夹且有备弹时自动换弹，满弹夹或无备弹不启动换弹。换弹中可移动、不能开火，结束时才补弹。三枪分别使用对应的取匣、装匣、滑套／拉机柄动作，动作不改变镜头或命中判定。

移动最大速度 6 m/s，普通加速度 30 m/s²，松键减速度 12 m/s²，反向加速度 48 m/s²；物理频率 120 Hz。

## 开发结构

| 模块 | 职责 |
|---|---|
| `scripts/main.gd` | menu / setup / countdown / training / results，输入、射线和统计 |
| `scripts/game_hud.gd`、`reticle.gd` | Godot 原生界面、静态预览、几何准星与短暂反馈 |
| `scripts/arena.gd` | 地图目录与切换，一次只持有一张地图及六个靶子 |
| `scenes/maps/`、`scripts/*hall.gd`、`old_town.gd` | 地图几何、灯光、出生变换、目标路线和验证路径 |
| `scripts/map_geometry.gd` | 地图共享几何辅助函数 |
| `scripts/game_rules.gd`、`weapon_controller.gd` | 武器参数、射击许可、弹药和换弹时间；射击许可不依赖速度 |
| `scripts/shot_direction.gd` | 精度门槛与射线散布；由命中模块在实际发射时调用 |
| `scripts/player_controller.gd`、`weapon_view.gd` | 玩家、镜头、握持与换弹表现 |
| `scripts/training_target.gd`、`trainee_visual.gd` | 命中区域、运动端点、击杀刷新与人物表现 |
| `assets/models/`、`assets/town/`、`assets/ui/` | GLB、2K 地图材质、离线渲染的地图与枪械预览 |
| `tests/` | 规则、真实场景检查、实机录制与实时性能测量 |

地图提供 ID、名称、预览路径、出生位置／朝向和六组目标配置。目标配置含位置、朝向、移动类型及两个运动端点。地图切换释放旧地图节点、灯光与目标。界面通过信号提交选择，不结算伤害；没有外部 API。

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
& $blenderExe --background --python-exit-code 1 --python tools/prepare_actor.py
& $godotExe --path '.\射击游戏' -- --previews "--capture-dir=$PWD/射击游戏/assets/ui"
& $godotExe --headless --path '.\射击游戏' --editor --import --quit
```

`--spread-demo --capture-dir=<绝对路径>` 生成移动射击与急停精准射击对比，可配合 `--write-movie` 录制；校准板、落点标记与标题只出现在演示模式，不改变正常游戏界面。

本次规则检查包含固定种子的 10,000 发圆盘分布检查；场景检查覆盖两图 × 三枪的精度边界、真实散布头身命中、墙体遮挡和最后一发结算。独立 EXE 使用 `-- --smoke-test --capture-dir=<绝对路径>` 可执行相同场景检查并保存画面，详见 `VALIDATION.md`。

`--showcase --capture-dir=<绝对路径>` 录制流程及地图截图；使用 Godot `--write-movie` 可输出固定步长 AVI。`--benchmark` 独立测量两图、两种尺寸，各预热 240 帧并测量 30 秒，包含行走与换弹。录制时的帧率不当作实时性能证据。

## 许可证

项目代码与原创地图为 MIT；外部模型按各自许可证分发，参见 [ASSET_MANIFEST.md](ASSET_MANIFEST.md)。地图材质为 ambientCG CC0；字体为 Noto Sans SC / SIL OFL 1.1。Godot 声明见 `THIRD_PARTY_NOTICES.md`。新增素材支出为 0 元。
