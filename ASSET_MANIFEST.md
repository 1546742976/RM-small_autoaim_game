# 模型、材质与许可清单

本清单适用于本仓库生成的五个 GLB。下表的上游原始作品与改编镜像均保留署名；上游说明中提到的其他武器、功能、检查结果不属于本项目交付或本项目验证结论。

| 交付资产 | 原作者及原始来源 | 许可 | 本项目修改 |
|---|---|---|---|
| `deagle.glb` 枪械 | ELIZION，[Desert Eagle](https://sketchfab.com/3d-models/desert-eagle-cabde59f5cf24effaf80536e35d04e95) | CC BY 4.0 | 转为米制、统一朝向、烘焙部件变换、分离弹匣／滑套、设置枪口与握持点、连接双手；纹理限制至 2K |
| `ak47.glb` 枪械 | taradavies，[AK-47](https://opengameart.org/content/ak-47-1) | 几何 CC0；改编版纹理为 AetherRadar MIT | 使用上游已拆分弹匣和拉机柄的改编模型；统一尺度、烘焙变换、设置握持点；木纹和金属底色保留，补充微表面法线 |
| `m4a1.glb` 枪械 | nisu，[M4A1 Assault Rifle](https://opengameart.org/content/m4a1-assault-rifle)；部分配件来自 Quaternius，[Ultimate Guns Pack](https://poly.pizza/bundle/Ultimate-Guns-Pack-cpgUfI4t2F) | CC0 | 统一尺度与朝向，保留黑色机匣／导轨／伸缩枪托，移除未使用瞄具和消声器，分离弹匣／拉机柄，设置握持点 |
| 三枪中的静态双手与 `reload_arms.glb` | DJMaesen，[fps animated smg](https://sketchfab.com/3d-models/fps-animated-smg-ea3dad7478624495a5a46f40127b0579)；AetherRadar 的静态姿态和换弹改编 | CC BY 4.0 | 使用带手指骨骼、袖口和手套的双手；缩放并分别适配握持点；换弹保留所需的三条左手动作，移除审计用全身手臂网格，按实际枪械接触点调整弹匣与手部运动，约束肘部使前臂保持在镜头下方，按游戏时长采样 |
| `trainee.glb` | EmoPreben，[Bald Man - Rigged](https://opengameart.org/content/bald-man-rigged) | CC0 | FBX 转 GLB，规范化站立高度与脚底位置、绑定姿态，保留面部／服装／鞋靴纹理，区分上衣材质，原创站立呼吸／侧步／倒下动作；没有护甲装备 |

CC BY 署名：**“Desert Eagle” by ELIZION, licensed under CC BY 4.0. “fps animated smg” by DJMaesen, licensed under CC BY 4.0.** 上述资产已经按表格修改，原作者不为本项目背书。

## 获取记录与许可正文

枪械和手部的可下载改编版来自 [AetherRadar/operation-steel-tide](https://github.com/AetherRadar/operation-steel-tide/tree/main/assets/models)，只使用明确列明来源和许可的资产，没有复制该游戏代码。人物直接来自作者在 OpenGameArt 发布的 ZIP。原计划中的其他候选资产没有纳入成品。

`射击游戏/assets/licenses/` 包含 CC BY 4.0、CC0 和 AetherRadar MIT 正文，以及四份上游资产署名／修改记录。`asset-sources.json` 记录精确下载 URL 和源文件 SHA256；`model-inventory.json` 记录本项目 GLB 的 SHA256、三角形数、动画和贴图分辨率。上游获取日期属于上游记录；本项目获取／转换日期为 2026-11-14。

## 材质与制作约定

采用基础颜色、法线、金属度和粗糙度组成的 PBR 材质。金属度按源材质使用纹理或常量。主要纹理为 2048×2048；沙鹰部分原始小部件保留 1024×1024，AK 上游 1K 颜色／粗糙度图在整理时采样到 2K，不将分辨率放大视为新增原始细节。AK 微表面法线由原有材质亮度生成，不引入来源不明纹理。

模型由 Blender 4.5.3 整理，GLB 包含网格、材质和需要的骨骼动作；Godot 导入后把贴图保留在模型资源中。游戏无需安装 Blender。三个枪械场景提供 `Muzzle`、`LeftGrip`、`RightGrip`、`Magazine`、`Slide`、`Bolt` 等部件入口，动画不掌管弹药。

不包含从商业游戏提取的模型、不明许可素材、付费下载或需要登录才能运行的资产。预算支出为 0 元。
