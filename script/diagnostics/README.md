# YY DNS 内存补丁实验

这是手工兼容性诊断工具，不是通用内存编辑器，不随 Arclume 自动启动，也不修改 Arclume-Runtime。

```bash
bash script/diagnostics/yy_dns_probe.sh --self-test
bash script/diagnostics/yy_dns_probe.sh --run
bash script/diagnostics/yy_dns_probe.sh --run-software-cef
bash script/diagnostics/yy_dns_probe.sh --run-no-webgl
bash script/diagnostics/yy_dns_probe.sh --run-osr-cpu
```

需要 Homebrew MinGW 的 `x86_64-w64-mingw32-gcc`、已安装的 Arclume Runtime、已构建 Debug App 及已展开的 D3DMetal 缓存。脚本拒绝在 Windows 程序仍运行时启动，不自动结束进程、不初始化新容器。只使用当前用户标准 Steam 容器中的 `C:\PortableApps\YYSpeak\YY.exe`。

## 匹配与原理

- 只接受 `9.58.0.0/components/com.yy.processservice/197124/gslb.dll`，大小 291688 字节，SHA-256 `5813bd9c8c0b6d7360f9b369e744ab0fac2a0294aa2b10fc43b1927fbe40e108`。
- `--run` 先对自身私有分配内存进行写入、读回复核及不匹配拒绝测试，并只读校验真实 DLL 的 SHA-256。
- 启动 YY 调试树，收到目标 DLL 的加载事件时，用事件文件句柄重新验证完整 SHA-256，在进程暂停期间检查模块基址 + RVA `0x20050` 的六字节 `e9 4b 90 ff ff cc`。
- 将该导出入口临时替换为 `b8 ff ff ff ff c3`，即 `mov eax,-1; ret`。现有函数有 `-1` 失败分支和 cdecl 返回；此实验**尚不证明调用方能完整降级**。不修改崩溃处 RVA `0x17218` 的内存写指令，不禁用 DLL 加载，不绕过 TLS/证书校验或登录认证。
- 写入后读回复核、刷新指令缓存并恢复页面保护。仅触碰本次新启动调试树中、路径和哈希完全匹配的模块；不附加到已有程序，不按名称全局扫描内存。
- 调试器只消费初始断点，其他异常交回程序处理；输出二次异常、子进程退出码和 `PATCHED`/`REFUSED`。不打印 `OutputDebugString` 内容或内存转储。

机制参考：[Microsoft 调试事件](https://learn.microsoft.com/en-us/windows/win32/debug/debugging-events)、[WriteProcessMemory](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-writeprocessmemory)。

## 结果与回滚

### 独立 Runtime 加载锁实验

经显式选择，可用 `ARCLUME_YY_TEST_RUNTIME=/绝对路径/测试Runtime bash script/diagnostics/yy_dns_probe.sh --run-osr-cpu` 启动一轮。目标必须带 `.arclume-yy-lock-test` 标记，内容为 `builtin-loader-lock-v1`。正式安装 Runtime、App 选择和图形版本不变；退出所有旧 YY/Wine 测试进程后再启动，不能与同一前缀的旧 wineserver 混跑。

2026-09-09 已在独立 ArclumeRuntime 项目完成加载锁顺序实验：旧版 32/64 位夹具均复现等待，实验版均通过。补丁仅保存在该项目 `patches/experimental/`，不自动进入常规构建。本轮仍保留上一轮 OSR CPU / DNS 内存补丁参数，以便单独对比 Runtime；频道画面、交互及声音尚待人工确认。

本机本轮产物：`ArclumeRuntime/work/build/yy-patched-runtime.Ql5tuS/arclume-wine-runtime-x86_64`；会话日志 `/tmp/arclume-yy-dns-probe.yswqIJ`。启动自检及 DNS 补丁命中已确认，Arclume 无签名 Debug preflight 通过。回到普通启动时不设置覆盖变量即可，不需要清理用户容器。

### 频道白屏的软件渲染对照

`--run-in-process-gpu` 保留 OSR CPU/软件绘图/禁用 WebGL，仅增加 `--in-process-gpu` 来验证软件输出跨进程访问窗口表面的影响。此模式不启用调试端口、不使用 `--single-process` 或 `--no-sandbox`；GPU/Browser 的进程隔离及故障边界发生变化，不能视作默认安全等价配置或全局修复。需核验实际进程类型与人工频道表现，正常启动即恢复。

2026-09-09 用户已确认此模式配合独立实验 Runtime 能正常显示、使用频道，详见 `yy_channel_findings.md`。这是已验证的组合，不等于单一参数已在正式 Runtime 上验证；语音收发与无调试器重启还未验收。

`yy_window_state.exe --shadow-preview` 只读查找唯一的频道阴影：QTool、透明分层、禁用、与 QWidget 频道同进程且四边各扩大 30 像素，频道必须包含 YYCefWindow。`--shadow-hide` 才临时隐藏此窗口 30 秒，随后对仍有效的原窗口请求无激活恢复。不要中途终止探针；如意外终止，关闭并重新打开频道恢复阴影。它不修改频道或浏览器窗口的父子关系、样式或配置，且不证明遮挡就是根因。人工确认画面及交互后再判断结果。

`--repaint-channel` 仅对唯一匹配频道请求异步重绘（含子窗口），不改样式或强行同步调用可能阻塞的窗口过程。`--all-visible-windows` 只读列出所有尺寸的可见 YY 窗口，用于观察小型浮层；不打印标题或其他应用窗口。

`--run-cef-inspect` 仅在明确同意本轮网页诊断后使用：保留 `--run-osr-no-webgl` 条件，为每个匹配的 CEF 进程追加独立的本机调试端口（39200–39327），不放宽 Origin、沙箱或网页安全策略。自检不打开端口。必须用 `lsof` 核验实际监听地址是 `127.0.0.1` 后再连接；若出现通配或非本机地址，立即关闭本次 YY。该端口可访问登录页面，其他本机进程也可能访问，因此只短时使用，不导出 Cookie、认证信息、原始 URL/请求正文。调试器退出及 15 分钟到期会终止其测试进程；完成后关闭 YY 并核验监听消失。该模式不写入正式启动配置。

YY 定制 CEF 109 的 `yycefcore.dll` 另行解析 `--debugport=` 并传给 `CefSettings.remote_debugging_port`；本模式同时提供此 YY 参数与标准 CEF 参数。不能因 PEB 参数读回成功就认定浏览器已采用参数。连接使用 `node script/diagnostics/yy_cef_inspect.mjs`（Node 22+）：拒绝非 loopback 监听，只报告 DOM 计数、页面求值是否超时、错误类型及网络统计，不操作页面、不读取 Cookie/Storage 或导出请求正文。网络统计只覆盖附加后的时间段，不是完整加载历史。

只有显式 `--capture-channel` 才另外捕获 CEF 内部频道画面：写入随机临时目录的 0600 PNG，可能含账户、频道或聊天信息，禁止提交或公开。默认不截图。`yy_window_state.exe --pixels` 仅统计窗口稀疏采样的像素分类，不捕获正文；GetPixel 对某些表面不可用，CLR_INVALID 不能作为白屏证据。该工具编译需要 `-lpsapi -lgdi32`。

`yy_window_state.exe --input` 只读记录可见 YY 窗口的 GUI 线程状态与坐标命中，含窄主窗口，不发送点击，不修改焦点、捕获或窗口属性。用来区分鼠标捕获、遮挡与页面无响应；单次结果不能证明应用已恢复。

`--run-osr-no-webgl` 在下述组合模式基础上仅追加 `--disable-webgl`，用于隔离已观察到的 SwiftShader WebGL 等待。保持同一实验 Runtime、OSR CPU 和 DNS 补丁，不增加沙箱降级参数。部分依赖 WebGL 的内容可能缺失，因此仅供诊断，不是默认适配。

`--run-osr-software-cef` 组合既有 OSR CPU 路径与 `--disable-gpu --disable-gpu-compositing`，但不禁用 WebGL，不改变浏览器沙箱。可配合独立 Runtime 覆盖做下一轮验证；原有各单项模式保留。模式解析的自检覆盖所有合法组合及非法参数。

加载锁实验会话中，CEF 在 15:57 报告 GPU 子进程异常退出（exit_code=34），其后绘图命令缓冲区创建失败；这并不证明所有白屏都由 GPU 导致。此次组合对照需同时读回 `cef_osr_gpu=0`、禁用 GPU 参数，再确认频道画面与交互，不能仅看启动自检通过。

`yy_window_state.c` 是独立人工采样工具：`--windows` 只枚举窗口及 WM_NULL 响应；无参数只报告既定图形参数；其他参数采集 YY 线程上下文并立即恢复线程。除固定安装目录外，仅允许当前 APPDATA 下已知版本的 YY 下载登录组件，不扫描其他程序的内存，不打印窗口标题或完整命令行。线程帧链在恢复后读取，仅能用作非原子采样线索，不是精确崩溃转储。

`--run-osr-cpu` 是另一条独立对照：只保留 DNS 补丁，不追加 Chromium GPU/WebGL 参数。先给新启动的 YY 设置进程级 `cef_osr_gpu=0`，再在 `yycefdev2.dll` 加载暂停期间将 RVA `0x2996` 的 `push "1"` 改为 `push "0"`。现有读取配置、`qputenv`、析构和后续流程不变，避免 YY 自身配置再次把变量改回 `1`。模块内既有字符串分别位于 RVA `0x6694`/`0x6648`；支持加载事件发生在重定位前或后，保留重定位逻辑。

只允许下列两个完整路径版本（详见源码），大小均为 48800 字节：

- 安装目录 `com.yy.cefdev2/131387/yycefdev2.dll`，SHA-256 `9b80204d577eaaadfda10c12d367c2255c9860fb9b7bbce8f9ddf41d9a9be676`。
- YY 下载组件目录 `com.yy.cefdev2/131389/yycefdev2.dll`，SHA-256 `7efd6300506acf029dbf7f68adf9479e18c5dafad08e1a895528f309590b6ec7`。

写入前验证完整哈希、指令和字符串，写后读回并恢复页保护。自检在自身私有内存验证改写和重复拒绝。该模式测试 YY 自己的离屏共享纹理选择，不禁用整个浏览器、不修改窗口父子关系，也不修改公共 libcef。仍须读回运行时变量并验证实际频道画面；`OSR_CPU_PATCHED` 不等于显示或语音已修复。退出本轮进程即丢弃修改。

`--run-no-webgl` 只比 `--run-software-cef` 多加 `--disable-webgl`，其他参数和 DNS 补丁保持相同，用于分离频道 WebGL 等待问题。该开关关闭所有版本 WebGL，不关闭 JavaScript、登录校验或浏览器沙箱，可能影响依赖 WebGL 的频道内容。依据 [Chromium 开关定义](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/content/public/common/content_switches.cc)。自检覆盖两种完整参数字符串和 64 位进程拒绝；启动日志标记本次模式。

前一轮软件渲染测试仍白屏，用户报告频道窗口无法点击、主窗口正常。运行中读回确认参数仍在；CEF 日志随后出现 WebGL `ReadPixels` 停顿及 ANGLE Vulkan `finishToSerial` 等待超时。该证据不能单独认定硬件 GPU 仍被使用，也不证明 YY 桥接死锁。新实验只检查禁用 WebGL 后页面、交互和语音是否可用，不应未经验证进入全局设置。

`--run-software-cef` 在 DNS 实验基础上，给本次调试树内固定安装路径的根 `YY.exe`、9.58 `YY.exe` 和 `yyexternal.exe` 追加 `--disable-gpu --disable-gpu-compositing`。不接触其他程序或版本，也不增加 `--no-sandbox` 等安全降级参数。

这是针对当前 Wine WOW64 的启动参数实验，不是跨版本 libcef 通用补丁。依据本机 Wine 的 `ProcessWow64Information` 和 `RTL_USER_PROCESS_PARAMETERS32` 布局，在进程创建暂停事件中读取参数；若尚未就绪，仅在初始断点重试。要求标准化参数、有限长度和完整读写；新缓冲区位于 32 位地址空间，参数描述符及内容均读回验证。原缓冲区不释放，失败尝试恢复描述符，无法确认恢复时保留新分配以免悬空指针。日志只打印 PID/结果，不打印原命令行（可能含登录凭据）。

`CEF_ARGS_APPLIED` 仅证明启动参数已写入，不证明应用没有重建参数、CEF 已启用软件渲染或频道已经可用。必须结合新 CEF 日志和人工频道测试；不能据此直接启用全局设置。正常的 Chromium 软件渲染仍可能存在 GPU 命名的子进程，不能仅按进程名称判定失败。

`PATCHED` 只证明补丁写入并复核成功，不代表 YY 已修复。首次实测已进入主界面，但用户选择语音频道后进程以 `0xe06d7363` 未处理 C++ 异常退出；本方案尚未通过验证，不能加入生产 Adapter。已补充第二次异常的受限诊断：记录时间、映像中的 RTTI 类型名及 x86 EBP 链中的可执行模块偏移，不导出栈原始内容或异常对象。新诊断需再复现验证。

仍需人工测试登录后主页面至少一分钟、进入语音频道、麦克风、退出及再次启动。调试器本身可能影响时序，最终接入 Adapter 前还需无调试器运行验证。DNS 模块初始化的其他副作用也可能影响联网，失败时不应扩大绕过范围。

正常退出本次 YY 即丢弃内存补丁；之后从 Arclume 正常启动不会应用此实验。工具没有写入 DLL、注册表或永久环境变量；YY 自身仍会正常写日志和设置。原 DLL 前后哈希应保持一致。

编译产物和日志放在打印出的 `/tmp/arclume-yy-dns-probe.<随机值>` 中，目录 0700、日志 0600。会话日志还接收 Wine/YY 的 stderr，可能包含私人信息，不应直接公开。临时产物不自动清理，不进入 App 或发布包。
