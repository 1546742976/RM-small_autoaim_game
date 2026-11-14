# 模型、材质与许可清单

本清单适用于本仓库的枪械与人物 GLB、原创地图、换弹音效及界面预览。下表的上游原始作品与改编镜像均保留署名；上游说明中提到的其他武器、功能、检查结果不属于本项目交付或本项目验证结论。

| 交付资产 | 原作者及原始来源 | 许可 | 本项目修改 |
|---|---|---|---|
| `deagle.glb` 枪械 | ELIZION，[Desert Eagle](https://sketchfab.com/3d-models/desert-eagle-cabde59f5cf24effaf80536e35d04e95) | CC BY 4.0 | 转为米制、统一朝向、烘焙部件变换、分离弹匣／滑套、设置枪口与握持点、连接双手；纹理限制至 2K |
| `ak47.glb` 枪械 | taradavies，[AK-47](https://opengameart.org/content/ak-47-1) | 几何 CC0；改编版纹理为 AetherRadar MIT | 使用上游已拆分弹匣和拉机柄的改编模型；统一尺度、烘焙变换、设置握持点；木纹和金属底色保留，补充微表面法线 |
| `m4a1.glb` 枪械 | nisu，[M4A1 Assault Rifle](https://opengameart.org/content/m4a1-assault-rifle)；部分配件来自 Quaternius，[Ultimate Guns Pack](https://poly.pizza/bundle/Ultimate-Guns-Pack-cpgUfI4t2F) | CC0 | 统一尺度与朝向，保留黑色机匣／导轨／伸缩枪托，移除未使用瞄具和消声器，分离弹匣／拉机柄，设置握持点 |
| 三枪中的常驻绑定双手 | DJMaesen，[fps animated smg](https://sketchfab.com/3d-models/fps-animated-smg-ea3dad7478624495a5a46f40127b0579)；AetherRadar 的完整绑定网格改编 | 手套与原贴图 CC BY 4.0；新增袖筒几何、动作制作代码 MIT | 保留手套拓扑、UV 与手指绑定，裁去原畸变长袖；新增封口袖筒、褶皱及腕部权重过渡，复用原 2K 法线；重新定位肩肘并适配三枪握姿；离线烘焙六套换弹，待机与换弹使用同一常驻双手 |
| `assets/audio/reload/*.wav`（9 个） | 本项目原创；生成器 `tools/prepare_reload_audio.py` | MIT | 48 kHz、16-bit、单声道；以确定性滤波噪声、金属共振和接触瞬态合成取匣、插匣与机械收尾声，三枪分别调音；属于游戏音效设计，并非真实枪械录音 |
| `trainee.glb` | EmoPreben，[Bald Man - Rigged](https://opengameart.org/content/bald-man-rigged) | CC0 | FBX 转 GLB，规范化站立高度与脚底位置、绑定姿态，保留面部／服装／鞋靴纹理，区分上衣材质，原创站立呼吸／侧步／倒下动作；没有护甲装备 |

CC BY 署名：**“Desert Eagle” by ELIZION, licensed under CC BY 4.0. “fps animated smg” by DJMaesen, licensed under CC BY 4.0.** 上述资产已经按表格修改，原作者不为本项目背书。

## 获取记录与许可正文

枪械和手部的可下载改编版来自 [AetherRadar/operation-steel-tide](https://github.com/AetherRadar/operation-steel-tide/tree/main/assets/models)，只使用明确列明来源和许可的资产，没有复制该游戏代码。人物直接来自作者在 OpenGameArt 发布的 ZIP。原计划中的其他候选资产没有纳入成品。

`射击游戏/assets/licenses/` 包含 CC BY 4.0、CC0 和 AetherRadar MIT 正文，以及四份上游资产署名／修改记录。`asset-sources.json` 记录精确下载 URL 和源文件 SHA256；`model-inventory.json` 记录本项目 GLB 的 SHA256、三角形数、动画和贴图分辨率。上游获取日期属于上游记录；本项目获取／转换日期为 2026-11-14。

## 材质与制作约定

采用基础颜色、法线、金属度和粗糙度组成的 PBR 材质。金属度按源材质使用纹理或常量。主要纹理为 2048×2048；沙鹰部分原始小部件保留 1024×1024，AK 上游 1K 颜色／粗糙度图在整理时采样到 2K，不将分辨率放大视为新增原始细节。AK 微表面法线由原有材质亮度生成，不引入来源不明纹理。

模型由 Blender 4.5.3 整理，GLB 包含网格、材质和需要的骨骼动作；Godot 导入后把贴图保留在模型资源中。游戏无需安装 Blender。三个枪械场景提供 `Muzzle`、`LeftGrip`、`RightGrip`、`Magazine`、`Slide`、`Bolt` 等部件入口，动画不掌管弹药。

第一人称双手重建脚本为 `tools/prepare_first_person.py`，可编辑 Blender 文件输出到 `tools/source/first_person/`。每枪导出 `idle`、`reload_empty`、`reload_tactical`，音效事件与接触区间记录在 `assets/models/viewmodel_manifest.json`。长袖与手套保持布料／非金属材质，不引入付费或来源不明的纹理；本轮没有改动训练靶人物。

不包含从商业游戏提取的模型、不明许可素材、付费下载或需要登录才能运行的资产。预算支出为 0 元。

## 旧镇街区与界面预览（2026-11-14）

旧镇街区的布局、建筑模块、拱门、门窗、阳台、木箱、木桶、花盆与场景组装由本项目制作，适用项目 MIT。风格参考 Valve 的 [Inferno 官方展示](https://www.counter-strike.net/inferno/)，没有复制地图文件、网格、贴图或标识；不是 Inferno 的地图复刻。

| 材质 | 作者与来源 | 许可与改动 |
|---|---|---|
| 石板道路 | Lennart Demes / ambientCG，[PavingStones036](https://ambientcg.com/a/PavingStones036) | CC0，选用 2K 颜色、OpenGL 法线、粗糙度图；引擎内调整重复比例与色调 |
| 外墙灰泥 | Lennart Demes / ambientCG，[Plaster001](https://ambientcg.com/a/Plaster001) | 同上，按建筑改变底色、降低法线强度 |
| 木门、木箱、木桶 | Lennart Demes / ambientCG，[WoodFloor051](https://ambientcg.com/a/WoodFloor051) | 同上，改用于木制构件 |
| 陶瓦屋顶 | Lennart Demes / ambientCG，[RoofingTiles012A](https://ambientcg.com/a/RoofingTiles012A) | 同上，使用自制双坡屋顶几何 |

来源许可：https://docs.ambientcg.com/license/ 。`assets/licenses/town-materials.json` 保存每个原始 ZIP 的下载链接、SHA256、所用贴图名及改动，CC0 正文随包提供。地图贴图共 12 张，均为 2048×2048；这些非金属表面金属度为 0。

`assets/ui/` 的两张地图图和三张透明背景枪械图均使用本项目的 Godot 场景离线渲染；枪械预览继承对应模型的署名要求。UI 使用 Godot 原生控件和 Noto Sans SC 字体，不引入网页运行时。

## C++ 控制接口依赖

- nlohmann/json **3.11.3**，作者 Niels Lohmann，MIT；[官方源码](https://github.com/nlohmann/json/tree/v3.11.3)。未修改单头文件，随 `sdk/cpp/third_party/nlohmann/` 分发源码及 `LICENSE.MIT`。`json.hpp` SHA256 为 `9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6`。
- OpenCV **4.x**，OpenCV 团队，Apache-2.0；[官方许可](https://github.com/opencv/opencv/blob/4.10.0/LICENSE)。仅由 C++ 图像示例使用，Ubuntu 通过系统软件包提供；Godot 游戏不依赖 OpenCV。本地验证使用的具体构建版本记录于验证报告，不把外部系统依赖打进游戏 EXE。
- C++ SDK、协议实现及示例为本项目代码，适用根目录 MIT 许可证。本轮不新增收费服务或付费素材。

## 箱阵考核资产

场地网格、道路算法、箱堆几何和对战代码为本项目原创，MIT。箱体复用上述 ambientCG 木材贴图，地面复用石板贴图，未新增外部付费素材。`bot_ak47.glb` 从本工程既有 `normalized_ak47.glb` 复制，继承 AK 来源与许可；运行时隐藏其中旧第一人称手臂，仅用于第三人称枪械。人物复用 CC0 的 trainee.glb，运行时增加持枪骨骼约束和弹匣动作，未改动原训练地图人物文件。
