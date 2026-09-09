# 普通模式 Steam 打开入口

- 普通模式底部增加“打开 Steam”，启动当前 Windows 容器中的 Steam；启动错误直接提示，不再必须进入设置寻找入口。
- 游戏库加载和刷新时同步 Steam 客户端检测及身份状态，重新打开 Arclume 后即可显示入口；同一容器的重新检测不打断正在进行的 Steam 游戏下载监测。
- CrossOver 启动请求显式带入实际容器根目录，避免打开同名的其他容器。
- 本机只读确认内置 Steam 容器中 Steam.exe 已存在；不重装、不启动 Steam，不修改用户游戏与容器数据。验证使用 Debug build / PR preflight，不运行 XCTest。
