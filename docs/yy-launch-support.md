# YY 专用启动适配

`GameAdaptations/yyspeak.json` 的 `launchSupport: yy-9.58-v1` 是审核过的固定处理器标识，不接受任意脚本、下载地址或机器码。第三方提交新版适配需要同时提供模块版本、SHA-256、原始指令和重复启动证据。

## 正常启动链

Arclume 验证安装路径、入口及关键 DLL 哈希 → 正式内置 Wine 运行 `yy-launch-support.exe` → 辅助程序创建 YY 调试进程树，在 DLL 初始化前写入经哈希及原始字节确认的内存补丁。YY 主/浏览器程序追加关闭 GPU、GPU 合成、WebGL 及 `--in-process-gpu`；不使用 `--single-process`、`--no-sandbox` 或远程调试端口。

这是持续驻留到 YY 退出的 Windows 辅助程序，不是无调试器运行。它以 GUI 子系统构建，不分配控制台；发生未知组件、写入失败或未处理异常时停止自己创建的进程树，报告日志和错误，不吞掉错误继续运行。其他既有 YY 会话会阻止新启动，不会被强制结束。当前固定组合不支持额外自定义命令行参数。

## 源码与构建

- 源码：`script/diagnostics/yy_dns_probe.c`，正式构建定义 `YY_LAUNCH_SUPPORT`，入口仅接受正常组合和自检。诊断模式仍是人工工具，不会自动运行。
- 生成：安装 MinGW-w64 后运行 `bash script/build_yy_support.sh`，审核输出并更新 `YYLaunchSupport.helperSHA256`。最终用户不需要编译器。
- 产物：`Arclume/Resources/yy-launch-support.exe`；Swift 启动前校验其 SHA-256，定向测试验证随包资源完整。
- 使用与 App 相同的 GPL 许可；构建链接 MinGW-w64 的 Windows CRT 启动代码，随包许可证见 `Arclume/Resources/yy-support-mingw-w64.txt`。

## 版本与安全边界

主程序固定为 YY 9.58.0.0，安装位置 `C:\PortableApps\YYSpeak`。DNS 与 OSR 模块使用完整路径、文件大小和完整 SHA-256 双重确认，写入后读回并恢复页保护。下载 OSR 组件只接受已验证的 131389 版本，并从本次 Wine 用户的 APPDATA 定位，不写死 macOS 用户名。新版本会拒绝而非泛化修补。

正式 Runtime 1.1.1 加此组合已通过用户频道画面与交互对照，不再使用实验 Runtime。WebGL 内容可能不可用；麦克风收发、长时间通话与更多机器仍需真机验证。回滚旧 App 后启动器不再应用补丁；无需清理或重装 YY。

应用只把已选择 YY 的诊断输出保存在本机 `Arclume/WindowsProgramLogs`，不上传日志；日志仍可能含软件自己输出的个人数据。不得公开原始日志。
