# RM-small_autoaim_game · 急停射击训练场

面向 RM 视觉组入门的 Windows 单机第一人称训练游戏，使用 Godot + GDScript。练习准星瞄准、急停时机和弹药管理。地图保持灰盒训练馆，枪械与人物使用带纹理的独立模型。

## 当前版本

已接入银灰沙鹰、木质护木／枪托 AK-47、黑色导轨 M4A1，以及带袖口、手套、手掌和手指的第一人称双手。三把枪分别播放与实际换弹计时同步的动作。验证：273 项规则检查、234 项场景检查，以及两种窗口尺寸各 264 项独立 EXE 检查通过。人形训练靶有面部、服装、四肢和鞋靴，静止靶穿暖色上衣，移动靶穿青色上衣，具有站立、侧步、倒下和刷新动作。

**只有爆头立即击杀。所有其他部位命中无伤害，但阻挡子弹并计入命中。** 护甲状态、护甲购买、伤害测试装置和 E 键交互均已删除。

发布位置：`builds/windows/RMPrecisionLab.exe`；便携包：`builds/RMPrecisionLab-windows-x64.zip`。运行游戏无需 Godot 或 Blender。源工程入口为 `射击游戏/project.godot`。素材清单及改编记录见 [ASSET_MANIFEST.md](ASSET_MANIFEST.md)，验证记录见 [VALIDATION.md](VALIDATION.md)。

未实现：联网、机器人、AI、玩家受攻击、跳跃、蹲伏、冲刺；本轮没有重做地图。人物使用免费游戏角色素材，具体外观以随附游戏内截图为准。

## 游戏流程和操作

主菜单 → 15 秒购买 → 60 秒训练 → 成绩结算 → 重开。每回合恢复 $5000、100 生命和免费沙鹰；正式训练开始时重置玩家位置、六个靶子和统计。

| 操作 | 功能 |
|---|---|
| WASD | 移动；松键自然减速，反向按键更快减速 |
| 鼠标 | 瞄准 |
| 左键 | 每次点击最多尝试发射一发 |
| R | 手动换弹 |
| B | 仅购买阶段打开／关闭装备面板 |
| Esc | 暂停／继续，释放／捕获鼠标 |

切换到其他窗口会自动暂停。暂停冻结移动、冷却、换弹及其动画、靶子动作、刷新和回合倒计时。继续后接着播放；结算、返回菜单和重开会恢复持枪姿势。

## 武器、急停与弹药

速度比 = 当前真实水平速度 / 正常最大移动速度。必须 **严格小于 0.34**，且冷却结束、弹夹非空、未在换弹，才能开火。失败点击不扣弹、不计射击次数、不排队补射。准星中心射线即时命中，墙体及人物身体阻挡射线；没有随机散布、弹道下坠或累积后坐力。

| 武器 | 弹夹 / 备弹 | 射击间隔 | 爆头 / 其他部位 | 换弹时长 | 购买价格 |
|---|---:|---:|---|---:|---:|
| 沙鹰 | 7 / 14 | 225 ms | 立即击杀 / 无伤害 | 2.2 秒 | 默认配发免费 |
| AK-47 | 25 / 50 | 100 ms | 立即击杀 / 无伤害 | 2.5 秒 | $2700 |
| M4A1 | 30 / 60 | 90 ms | 立即击杀 / 无伤害 | 3.1 秒 | $3100 |

- 每回合总弹药固定为三个满弹夹。提前换弹保留余弹，只从备弹扣除补足部分；备弹不足则装入剩余弹药。
- 空弹夹且有备弹时自动换弹，与手动换弹使用同一套动画；满弹夹或无备弹不启动换弹。
- 换弹时允许移动、禁止开火，**结束时才补弹**。最后一发先结算命中与击杀，再检查弹尽并结束回合。
- 沙鹰：侧倾、取匣、插匣、滑套动作、恢复握持；AK：侧转、倾斜取装匣、拉机柄、恢复；M4：内倾、垂直取装匣、上膛收尾、恢复。
- 动画只改变手臂和枪械，不改变相机方向、准星、速度比或射击许可。

## 购买、训练靶和成绩

购买阶段仅可确认一次选择。保留沙鹰不扣钱；AK 或 M4 替换沙鹰。确认后无法重复扣费、换枪或补弹。15 秒后自动开始训练，未确认则使用默认沙鹰；训练阶段不能购买。

六个靶子为三个静止和三个固定路线往返的人形角色，无自主决策或攻击行为。头部碰撞体跟随头部骨骼，躯干、颈部、上下臂、手、大腿、小腿和脚均有阻挡判定。非头部命中保持 100 生命；爆头后立即关闭全部命中区域，播放倒下动作，1 秒后恢复，避免重复计分。

命中率 = 命中靶子的发数 / 实际发射数；爆头率 = 爆头击杀数 / 总击杀数；零分母显示 0%。由于本版本只能爆头击杀，产生击杀后的爆头率为 100%。重开不继承资金、武器、弹药和成绩。

## 开发结构

| 文件 / 目录（工程内） | 职责 |
|---|---|
| `scripts/main.gd` | 回合、购买、输入协调、射线、统计和音效 |
| `scripts/game_rules.gd` | 集中武器参数、仅爆头伤害、购买计算 |
| `scripts/weapon_controller.gd` | 射击许可、冷却、弹药和换弹时间 |
| `scripts/player_controller.gd` | WASD、相机、真实水平速度、持枪场景切换 |
| `scripts/weapon_view.gd` | 持枪姿态、骨骼换弹、弹匣接触、滑套／拉机柄和复位 |
| `scenes/weapons/` | 三把枪各自的独立场景 |
| `scripts/trainee_visual.gd` | 角色骨骼、服装识别色和动作采样 |
| `scripts/training_target.gd` | 骨骼命中区域、固定路线、击杀和刷新 |
| `scripts/arena.gd` | 原有训练馆、碰撞、材质适配灯光和六个靶子 |
| `scripts/game_hud.gd` | 中文菜单、购买、速度、准星、换弹状态和结算 |
| `assets/models/` | 规范化 GLB（内嵌纹理、材质及骨骼） |
| `assets/licenses/` | 模型许可证和上游署名 |
| `tests/` | 规则、场景、画面采集与性能验证入口 |

通过 Godot 信号传递开火、命中、成绩和阶段变化。武器控制器掌管弹药与换弹时长，显示模块只按计时采样动画；界面不结算伤害。没有外部 API。

移动最大速度 6 m/s，普通加速度 30 m/s²，松键减速度 12 m/s²，反向加速度 48 m/s²；物理频率 120 Hz。枪械后移仅作视觉反馈。

## 运行与导出

已使用 **Godot 4.7.2 Standard**（无需 .NET）验证。保留 Forward Plus、Windows D3D12、Jolt Physics 配置。默认窗口 1280×720，最小窗口 960×540；中文字体随包提供。

在 Godot 项目管理器导入 `射击游戏/project.godot`，等待资源导入完成后按 F5。主场景为 `scenes/main.tscn`，场地、玩家和界面在运行时创建。

以下命令在仓库根目录运行；将引擎路径替换为实际安装路径：

```powershell
$godotExe = 'D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path '.\射击游戏' --editor --import --quit
& $godotExe --path '.\射击游戏'
& $godotExe --headless --path '.\射击游戏' --script res://tests/test_rules.gd
& $godotExe --headless --path '.\射击游戏' -- --smoke-test

# 首次准备匹配的官方 Windows 模板；已有缓存可跳过
python -m pip install requests
python tools/fetch_windows_template.py
.\tools\build_windows.ps1 -GodotPath $godotExe
```

导出预设 `Windows Desktop` 使用 `tools/cache/4.7.2-stable/windows_release_x86_64.exe`，把资源嵌入 EXE。可在编辑器内改用本机匹配版本的 Release 模板。构建脚本完成资源导入、规则及场景检查、导出和许可证复制；发布包中的 `licenses/` 必须随游戏分发。

修改模型时可使用以下素材流水线；**日常运行和导出不需要 Blender**：

```powershell
python tools/acquire_visual_assets.py --blender
$blenderExe = '.\tools\cache\visuals\blender-4.5.3-windows-x64\blender.exe'
& $blenderExe --background --python-exit-code 1 --python tools/prepare_visuals.py
& $blenderExe --background --python-exit-code 1 --python tools/prepare_actor.py
```

首次素材获取需要网络；脚本保存下载地址与 SHA256，Blender ZIP 按官方 SHA256 校验。缓存位于 `tools/cache/`，临时文件、录像及日志位于 `artifacts/`，均不纳入 Git。已交付 GLB 可直接编辑和运行，不依赖素材站点在线服务。

## 里程碑和验收

- [x] 文档与规则：仅爆头击杀、取消护甲、移除测试装置及 E 交互。
- [x] 三把独立枪械场景、PBR 材质、第一人称双手和部件入口。
- [x] 三套换弹按 2.2 / 2.5 / 3.1 秒驱动，手动／自动共用，结束补弹。
- [x] 有面部、服装和四肢的训练靶，站立／侧步／倒下动作。
- [x] 骨骼头部判定、身体阻挡、零伤害及死亡立即关闭判定。
- [x] 0.339 / 0.34 / 0.341 边界、射速、弹药、购买、统计和重开回归。
- [x] 暂停冻结动画，结算、菜单及重开恢复持枪状态。
- [x] 两种窗口尺寸的最终画面及导出包检查，结果见 VALIDATION.md。
- [x] 本机 60 FPS 目标的测量记录，结果见 VALIDATION.md。
- [x] Windows EXE、便携包、三枪截图和换弹演示最终交付。

## 许可证

项目代码为 MIT；外部模型不自动适用项目 MIT。模型的作者、原始来源、获取镜像、许可证、改编内容和纹理规格集中记录在 [ASSET_MANIFEST.md](ASSET_MANIFEST.md)。Godot 声明见 `THIRD_PARTY_NOTICES.md`，Noto Sans SC 为 SIL OFL 1.1。素材预算实际为 0 元。
