# 第一人称双手制作源

`deagle.blend`、`ak47.blend`、`m4a1.blend` 保存完整枪械、统一双手骨架、手指、袖筒、材质以及烘焙动画。游戏运行只读取导出的 GLB，不需要 Blender。

## 可重复生成

使用项目缓存中的 Blender 4.5.3：

```powershell
$blenderExe = '.\tools\cache\visuals\blender-4.5.3-windows-x64\blender.exe'
& $blenderExe --background --python-exit-code 1 --python tools/prepare_visuals.py
& $blenderExe --background --python-exit-code 1 --python tools/prepare_first_person.py
```

先运行素材获取步骤（根目录 README），确保原始免费素材已进入 `tools/cache/visuals/`。第一步生成规范化枪械及 `normalized_*.glb` 缓存；第二步始终从该缓存和原始完整双手生成，不把上一次的最终模型当作输入。

每把枪导出 `idle`、`reload_empty`、`reload_tactical` 三条 NLA 动画；沙鹰 2.2 秒、AK 2.5 秒、M4 3.1 秒，120 Hz 烘焙。编辑时对武器、弹匣、机件和 ArmsRig 启用同名 NLA 轨，其他轨保持静音。Godot 导入采样同样为 120 Hz。

`viewmodel_manifest.json` 记录时长、音效事件、左右接触参考点与验收区间。左手参考点绑定腕骨，弹匣参考点绑定真实弹匣；右手参考点绑定右腕。动画时钟及补弹逻辑由游戏控制器负责。

## 几何与许可

- 双手、手套、手指权重及现有 2K 贴图来自 DJMaesen 的 **fps animated smg**，CC BY 4.0；来源及上游改编记录见项目 `ASSET_MANIFEST.md` 和 `assets/licenses/`。
- 保留手套拓扑、UV 与手指骨架，移除上游过度延长的袖子。新增连续封口袖筒、罗纹袖口与几何褶皱，使用相同骨架蒙皮，袖口随手腕渐变至前臂。
- 肩、肘、腕使用固定骨段长度的离线解析约束；所有结果烘焙后导出，游戏运行时没有拉伸骨骼或整体平移手臂来追赶弹匣的修正。
- 本项目新增制作脚本、袖筒几何及动画编排按项目 MIT 许可提供；原始及改编的第三方手套、枪械和贴图继续遵守各自许可证。

源文件能再次生成不代表外观自动通过；实际游戏截图、连续录像及定量检查结果见根目录 `VALIDATION.md`。
