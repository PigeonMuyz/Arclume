# YY 频道白屏与加载锁现场（2026-09-09）

## 阴影、重绘与绘图进程边界对照

**最新人工结果：`--run-in-process-gpu` 组合测试已能显示和使用频道。** 用户在登录进入同一频道后明确回复“好了，可以用了”。会话 `/tmp/arclume-yy-dns-probe.pJm5Te` 自检通过，模式读回为 software_cef=1 / disable_webgl=1 / osr_cpu=1 / inspect=0 / in_process_gpu=1；OSR CPU 补丁命中主进程。实际命令行只读取样中 Renderer 子进程仍存在，未看到 `--type=gpu-process` 子进程，未开启本机调试监听。保留该可用会话，不因交付再关闭它。

这支持“软件输出跨进程访问原生窗口”假设，但尚未以函数级跟踪证明精确失败点。本次依旧使用 DNS/OSR 内存补丁和独立实验 Runtime，不代表仅给正式 Arclume 加一个参数即可完整解决。麦克风收发、长期通话、无调试器重复启动，以及去掉实验 Runtime 后的最小必要条件仍需验证，因此本次不修改正式 Adapter 或 Runtime Manifest。

交付检查：MinGW 严格警告编译、启动自检、shell/JS 语法检查、`git diff --check` 通过；`./script/pr_preflight.sh` 无签名 Debug 构建通过（`/tmp/arclume-icon-yy-final-preflight.log`），未运行 XCTest。没有持久修改用户配置或清理数据，也没有提交／推送本轮后续改动。

- 会话 `/tmp/arclume-yy-dns-probe.NzI0zr` 使用此前相同渲染条件，不开调试端口。唯一频道阴影匹配通过，隐藏／恢复异步请求成功；用户报告该阶段没有变化。此初版未在隐藏期间读回可见性，不能据此完全排除阴影；后续版本已增加状态读回。随后窗口枚举确认阴影恢复可见。
- 对唯一频道请求 `RDW_INVALIDATE | RDW_FRAME | RDW_ALLCHILDREN` 异步重绘成功。用户明确补充：重绘后，在白屏中的实际控件位置悬停能够弹出频道资料卡，但主画面仍白。至少部分输入与局部绘图仍工作，不应将其描述为整个频道线程卡死。
- 小尺寸窗口枚举发现可见的分层 QWidget 浮层。Chrome_WidgetWin_0 与 Chrome_RenderWidgetHostHWND 的 DC 裁剪区域均为完整频道大小；父级因子窗口裁剪为空并不异常。跨进程 GetPixel 依旧无效，不能以此判定浏览器画面为空。
- 新假设来自源码交叉检查：Chromium 109 软件直接输出会向目标 HWND `GetDC`/CopyHDC；当前本地 Wine `win32u/dce.c:update_visible_region` 仅在顶层窗口属于本进程时获取其 window surface，否则可能无绘图表面。独立取样程序也在跨进程访问，因此其像素失败可能来自取样方法自身，尚不等于证明 YY 的输出线程命中该分支。
- 下一轮 `--run-in-process-gpu` 仅把 GPU/Viz 线程放入 Browser，保持其余软件渲染条件；不使用 single-process/no-sandbox，不开启远程调试。这会改变 GPU 与 Browser 隔离边界，仅供手动对照，不进入正式设置。需要实际进程类型与频道交互验证。

参考：[Chromium 109 软件窗口输出](https://raw.githubusercontent.com/chromium/chromium/109.0.5414.120/components/viz/service/display_embedder/software_output_device_win.cc)、[Chromium GPU 进程模式](https://raw.githubusercontent.com/chromium/chromium/109.0.5414.120/content/browser/gpu/gpu_process_host.cc)。

## CEF 内部画面与桌面窗口不一致（本机调试实测）

- 标准 `--remote-debugging-port` 单独追加后未出现监听，不能据此判断 CEF 未加载。下载组件 131389 的 `yycefcore.dll`（744608 字节，SHA-256 `f6e8ae5399ab714c05bd84ffe9154e9c7e1f7fb283b54edfc1f8f50255c6feb7`）在 RVA `0x3636c` 读取命令行，在 `0x363a0` 使用 `--debugport=`，最终 `0x364a3` 写入 `cef_settings_t.remote_debugging_port`。这是 YY 自有入口，不是新机器码修补。
- 用 YY 参数重启后，会话 `/tmp/arclume-yy-dns-probe.0MuyDb` 的监听确认为测试 Runtime/YY 持有的 `127.0.0.1:39200`，CEF 版本 Chrome/109.0.5414.120。未放宽 Origin、沙箱或 TLS 校验。
- 两个页面均可执行只读 JavaScript 查询。频道页面尺寸 1024×650，DOM 854→870 个元素、6 个 iframe；采样时 iframe 的文档均为 complete。频道根文档为 interactive，不能因此声称所有加载均已完成。
- `Page.captureScreenshot` 返回完整频道界面，同时用户明确确认桌面仍白屏、按钮卡住。截图仅存本机权限受限临时目录，包含频道内容，不纳入 Git 或对外材料。这证明本次 CEF 能生成画面，但不能单凭内部截图证明原生窗口完成呈现或输入链路正常。
- `SystemInfo.getInfo` 确认 gpu_compositing/rasterization/video_decode 为 disabled_software，WebGL/WebGL2/Vulkan 为 disabled_off。ANGLE renderer 字符串仍提及 SwiftShader，不等同于这些功能实际启用。本轮已有内部状态佐证禁用开关，不再只依赖 PEB 参数读回。
- 两次短采样没有收到 Runtime.exceptionThrown；请求存在 200/206 响应，另有历史网络错误及混合内容日志。仅覆盖附加后的时间段，不能排除某个功能的网络/脚本故障，但不支持“整个页面脚本卡死”的判断。
- 同时枚举到响应 WM_NULL 的 QWidget → YYCefWindow → CefBrowserWindow → Chrome_WidgetWin_0 → Chrome_RenderWidgetHostHWND。外侧还有禁用的透明分层 QTool，尚不能认定它遮挡画面。稀疏 GetPixel 取样均为 CLR_INVALID，没有获得可用的 GDI 像素证据。
- 故障范围进一步缩小到 CEF 画面生成之后的原生窗口呈现／合成与输入路径。下一步应对该路径做单变量验证，而不是直接加入全局硬件加速开关；目前尚未修复频道问题。
- 取证结束已关闭测试 YY，并清理本轮残留的 YY 子进程及 RPC 服务；实际核验 39200–39327 无监听、无残留 Wine 程序。未改动正式 Runtime、DLL 文件或用户配置，未清理登录数据。C 严格警告编译、启动自检、Node loopback 过滤测试、shell/JS 语法检查及 `git diff --check` 通过；最终无签名 Debug preflight 通过，日志 `/tmp/arclume-yy-cef-inspection-preflight-final.log`，未运行 XCTest。15 分钟自动退出分支尚未等时实测。

初始化字段与本机绑定机制参考 [CEF 5414 设置结构](https://raw.githubusercontent.com/chromiumembedded/cef/5414/include/internal/cef_types.h) 和 [CEF DevTools 服务实现](https://raw.githubusercontent.com/chromiumembedded/cef/5414/libcef/browser/devtools/devtools_manager_delegate.cc)。YY 定制版本仍以实际监听结果为准。

## 禁用 WebGL 后仍卡顿的现场

- 用户再次报告卡住；本轮未重启 YY，也未添加新的渲染/锁补丁。
- 新线程采样 `/tmp/arclume-yy-no-webgl-stuck-stacks.log`：可见 Qt 主线程在消息等待。登录组件一次采样停在条件等待，后续原生采样为消息循环，不能据此称其持续死锁。会话曾有加载锁超时记录，因此也不能声称该会话完全没有加载锁等待。
- `/tmp/arclume-yy-stuck-input.log`：采样时未发现鼠标捕获、菜单或移动状态；当时焦点/激活句柄为空，可能只是用户在其他应用操作，不能直接判为焦点故障。
- 完整子窗口枚举 `/tmp/arclume-yy-no-webgl-window-tree.log` 确认频道存在可见、启用且响应 WM_NULL 的 YYCefWindow → CefBrowserWindow → Chrome_WidgetWin_0 → Chrome_RenderWidgetHostHWND。此前只枚举顶层/大窗口不足以定位点击的最终接收者。
- 先前 WebGL 两分钟等待未在新日志末尾重现，但用户卡顿仍在。接下来需要网页内部的脚本错误、请求完成状态或页面渲染信息；暂不再增加全局图形开关或强行改写等待指令。

## 独立 Runtime 实测回报

加载锁顺序实验已通过独立 32/64 位并发夹具，但用户在本轮 YY 频道测试仍遇到白屏与卡住。不能把夹具通过等同于 YY 已修复；继续保留为诊断实验，不加入正式 Adapter。下一步需采集新现场，确认原循环等待是否消失及剩余阻塞位置。

## 后续组合对照

组合实测仍卡住（16:09 采样）：相关进程读回 `disable_gpu=1`、`disable_compositing=1`、`disable_webgl=0`；Windows PID 2156 / TID 2160 栈包含 `vk_swiftshader.dll+0x1ab15f → libglesv2.dll+0x229277`，而非此前内置窗口类初始化循环。CEF 在 16:05:48 报告 ReadPixels 停顿，16:07:48 报告 `finishToSerial` 等待超时。对应采样 `/tmp/arclume-yy-combined-stuck-stacks.log`。这些证据确认绘图等待仍存在，但不足以证明所有按钮失效都由它导致。

下一轮使用 `--run-osr-no-webgl`，仅添加禁用 WebGL，保持其余条件。已先关闭上一轮 YY/Wine 进程；不清理缓存、注册表或登录数据。

本轮会话 `/tmp/arclume-yy-dns-probe.k1d454` 自检通过；`/tmp/arclume-yy-osr-no-webgl-readback.log` 已确认主进程和采样子进程 `disable_webgl=1`、`disable_gpu=1`、`disable_compositing=1`、`cef_osr_gpu=0`。`./script/pr_preflight.sh` 无签名 Debug build 通过（日志 `/tmp/arclume-yy-osr-no-webgl-preflight.log`），未运行 XCTest。频道交互和绘制结果仍待用户确认。

- 实验 Runtime 会话的新采样中，主窗口线程处于消息等待，已枚举的窗口响应 WM_NULL；没有再次观察到前述加载锁超时。这只是当前采样，不能据此否定用户看到的卡顿。
- 另一个未归属窗口来自 YY 下载目录的登录组件；补齐范围后确认为隐藏且可响应的 HTTP 消息窗口，不是已证实的白屏覆盖层。
- CEF 日志在 15:57 报告 GPU 子进程异常退出（34）、已崩溃三次，随后 `GpuControl.CreateCommandBuffer` 发送失败。下一轮针对绘图路径进行组合对照，不修改进程锁或强制调整窗口层级。
- 已关闭旧测试进程后，用 `--run-osr-software-cef` 和同一独立 Runtime 重新启动。日志 `/tmp/arclume-yy-dns-probe.AD33WD`；启动自检、DNS/OSR 补丁命中均通过。
- `/tmp/arclume-yy-combined-readback.log` 读回确认主进程及采样到的相关子进程 `disable_gpu=1`、`disable_compositing=1`、`disable_webgl=0`、`cef_osr_gpu=0`。服务进程不在 CEF 参数改写范围。
- 两个 C 诊断工具严格警告编译通过；`./script/pr_preflight.sh` 无签名 Debug 构建通过，未运行 XCTest。频道画面、持续交互和声音尚待用户验证。

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
