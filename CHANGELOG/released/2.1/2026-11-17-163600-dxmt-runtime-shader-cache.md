# Arclume Runtime 的 DXMT 0.80 方案与游戏着色器目录

- 移除 MetalSharp Wine 和 KosmicKrisp 的运行环境入口。旧 MetalSharp 选择回退到 Arclume Runtime，保留原实验运行时和容器数据。
- 在游戏的「运行设置」中增加 Arclume Runtime 搭配 DXMT 0.80，与 GPTK 的 D3DMetal 4 Beta 3 共用当前游戏容器。DXMT 按已校验的组件清单准备资源。切换时保存和恢复图形模块，容器内仍有进程时要求先正常退出游戏。
- 使用 DXMT 启动游戏时，将观察到的着色器保存到应用支持目录中的 `Shaders/<游戏标识>/DXMT-0.80/<容器标识>/`。游戏菜单提供「优化着色器」，可选择并记住外置 DXMT 数据库或 Metal `.metallib` 文件及其目录。外置内容作为读取来源。
- 打开 Arclume 时读取已安装游戏的着色器记录。发现尚未在当前 GPU 和 macOS 版本下预优化的记录时，提示用户提前处理，并显示优化进度和可取消操作。
- Metal 库和可用计算管线可以提前准备。DXMT 0.80 的完整图形管线仍依赖游戏的实际渲染状态。优化完成记录以 GPU、系统版本和着色器内容为依据。
- 保留 Pakv4 与渲染 DLL 的 DXBC 和变种扫描，通过固定版本的 DXMT 0.80 请求实际 Metal 编译，再交给原生预优化工具。VS、PS、CS 已验证生成 Metal 库，GS、HS、DS 缺少关联状态时计入未完成项。逐条等待编译，限制内存积压。
- 优化面板只显示「读取着色器数量」和「正在优化着色器（进度/数量）」两个阶段，外置来源选择放在运行设置中。
- 手工验证可在正常退出 Windows 游戏后切换 GPTK 与 DXMT、启动并退出游戏，再打开 Arclume 检查提示与缓存目录。开发构建先运行 `bash script/build_game_metal_shader_tools.sh`，发布构建同样执行工具构建。回滚可重新选择 GPTK，原有游戏文件保留。
