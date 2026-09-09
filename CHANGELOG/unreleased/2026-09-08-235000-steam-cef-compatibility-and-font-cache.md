# 内置 Steam 界面兼容启动与字体准备缓存

- 内置 Wine 打开 Steam 或处理 Steam 安装链接时加入 `-cef-disable-gpu` 和 `-cef-disable-gpu-compositing`，尝试绕过 Steam CEF GPU 进程反复崩溃、界面黑屏的问题。不修改游戏图形后端、不全局覆盖 DLL、不关闭沙箱，CrossOver 启动参数保持不变。
- Steam 字体修补增加容器内完成标记，记录修补版本、字体 SHA-256、Runtime 路径/版本/文件时间以及容器 Windows 目录创建时间。已有且匹配的修补不再每次运行两次 reg export 和两次 reg import。
- 字体文件缺失或内容变化、Runtime/修补版本变化、容器重建、标记缺失或损坏会重新准备；仅在两个注册表视图均导入成功后写入标记，失败和取消不会记录成功。
- 摘要读取在后台分块执行；首次升级仍需一次完整字体准备。删除本功能的完成标记可强制重新准备，不涉及清除游戏、账户或缓存。

## 验证与边界

- 独立 Swift fixture 检查兼容参数范围、字体标记命中、字体损坏/丢失、版本变更和标记损坏失效；Debug build、pr_preflight、git diff --check，不运行 XCTest。
- 此次为针对已观察到的 CEF GPU 崩溃的兼容修补，真实 Steam 登录界面和启动耗时仍待用户复测；不宣称已解决网络登录失败或底层驱动缺陷。
- 不改 Runtime 归档及版本，不提交、推送或发布；不自动结束用户正在运行的 Steam。
