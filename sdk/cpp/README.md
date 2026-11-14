# RM C++ 控制客户端

主要目标：Ubuntu 22.04／24.04 x86_64，C++17，CMake ≥3.16，OpenCV 4。游戏运行在 Windows；完整协议和连接步骤见工程／发布包根目录 `CONTROL_API.md`。

在完整工程中使用 `cmake -S sdk/cpp -B build/control`；独立 SDK 压缩包解压后使用 `cmake -S cpp -B build/control`，然后 `cmake --build build/control -j`。依赖安装命令：`sudo apt install build-essential cmake libopencv-dev`。

- `rm_control_probe`：真实 TCP 取图、单发、换弹和耗时联调；不依赖 OpenCV。
- `rm_vision_template`：OpenCV BGR 图像接入模板；默认检测函数为空，不自动射击。`--frames=120` 可限定取图帧数进行验证。
- `rm_camera_test`：像素转角度的坐标和非零俯仰校验；通过 CTest 运行。

`-DRM_WITH_OPENCV=OFF` 可仅构建核心客户端与联调工具。代码也提供 Windows Winsock 实现，便于本机回环验证；MinGW Makefiles 构建请把源码放在英文路径。网络失败不自动重发动作，连接空闲时每秒调用 `ping()`。

`third_party/nlohmann/` 为原版 nlohmann/json 3.11.3 及 MIT 许可证；其余客户端代码适用本目录 MIT 许可证。OpenCV 作为外部系统依赖，不随这个源码包分发二进制。


当前游戏采用实体子弹：`fired=true` 仅代表发射成功，命中可能随后发生。箱阵 `remaining_s=-1` 表示不限时，新增 `settling` 表示等待在途子弹；程序图像包含枪械与基础 HUD，但不包含本地箱阵雷达。空格跳跃仍由人控制，空中射击有散布。状态按 JSON 返回，现有客户端兼容这些新增字段。
