# YY 频道白屏与加载锁现场（2026-09-09）

## 独立 Runtime 实测回报

加载锁顺序实验已通过独立 32/64 位并发夹具，但用户在本轮 YY 频道测试仍遇到白屏与卡住。不能把夹具通过等同于 YY 已修复；继续保留为诊断实验，不加入正式 Adapter。下一步需采集新现场，确认原循环等待是否消失及剩余阻塞位置。

## 已验证与未验证

- DNS 内存补丁配合用户应用绿色适配后可以进入主页面；频道仍白屏。
- 仅加 Chromium `--disable-gpu --disable-gpu-compositing`、再加 `--disable-webgl`，用户均报告白屏。
- `--run-osr-cpu` 的 `OSR_CPU_PATCHED` 确认命中下载组件 131389，运行中所有采集到的 YY 主/子进程 `cef_osr_gpu=0`，没有追加 Chromium GPU/WebGL 参数。用户仍报告频道白屏、按钮稍后卡住。
- 用户报告关闭频道窗口（不是最小化或退出整个 YY）瞬间能够看到正确页面。尚未捕获该瞬间；不能据此直接认定有遮罩层，或强制重设 CEF 窗口父级。
- 已观察到隐藏的 YYCefWindow/CEF 子窗口及可见 Qt 外框。离屏绘制可能本来如此，这一结构本身不是错误证据。

## 明确的线程循环等待

本轮工具输出目录：`/tmp/arclume-yy-dns-probe.7QE0NN`。详细 stderr 可能包含私人信息，不直接对外发布。

在两个 YY 浏览器相关子进程里观察到相同模式（以下均为 Windows PID/TID，不是 macOS PID）：

- PID 3012 / TID 3016（0x0bc8）与 PID 5572 / TID 5576（0x15c8）在加载 wined3d 时等待窗口类初始化。
- Wine 日志明确记录其他线程等待它们持有的 `loader_section`，以 60 秒间隔重试。
- 加载线程栈：`wined3d.dll+0x61b8 → wined3d.dll+0x1d80d6 → user32.dll+0x4830d → win32u.dll+0x11f88`。
- 实际安装的 PE 反汇编确认 `wined3d.dll+0x1d80d0` 调用 `RegisterClassA`；对应源码 `wined3d_dll_init`，由 DLL_PROCESS_ATTACH 调用。该初始化注册 `WineD3D_OpenGL` 窗口类。
- macOS 原生采样对应 `NtUserRegisterClassExWOW → get_desktop_window → pthread_once → _os_once_gate_wait`。本地 Wine 源码中非内置类注册先调用 `get_desktop_window`，后者调用 `register_builtin_classes`，该函数使用 `pthread_once`。
- 另一线程的栈包含 `user32.dll+0xff46`，实际导入表及调用指令确认是在调用 `LdrGetDllFullName`；其上层 ntdll 等待加载锁，与日志标出的锁拥有者一致。窗口类初始化中的光标/图标加载会进入此调用。

因此已确认这批子进程存在 DLL 加载与窗口类一次性初始化的锁顺序问题。它解释了至少一部分后续挂起；尚不能把频道白屏、关闭瞬间正确画面、所有 WebGL/网络错误都归结到同一个原因。

本地诊断附件：`/tmp/arclume-yy-osr-cpu-live-stacks.log`（只含受限模块偏移等）、`/tmp/arclume-yy-loader-91762.sample.txt`（原生线程采样）。临时辅助工具没有修改进程代码；线程取样期间短暂挂起并立即恢复，未清理用户目录。

## 后续边界

- 不把上述三个未解决频道问题的渲染实验加入正式 Adapter 或全局设置。
- 不跳过 RegisterClass、不释放别的线程的锁、不直接改窗口父子关系来掩盖初始化失败。
- 下一步应在独立 Arclume-Runtime 项目核对并修复初始化锁顺序，或验证能够严格保证先后次序的进程级初始化方案。该项目的指导文件、构建和兼容性矩阵需要单独读取；本次没有修改或构建 Runtime。
- 修复需要最小并发复现、32 位 WOW64 验证，再分别确认 YY 登录、频道画面、交互、语音及无调试器重复启动。
