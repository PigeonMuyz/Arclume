# YY 软件绘图进程边界对照

- 显式诊断模式 `--run-in-process-gpu` 在已有 OSR CPU、软件绘图、禁用 WebGL 条件下，仅增加 Chromium 进程内 GPU 线程参数，以验证跨进程窗口表面访问假设。
- 不启用远程调试、不使用 single-process/no-sandbox，不改变 Renderer 进程隔离；GPU 与 Browser 的独立故障／隔离边界会变化，因此不自动进入 Adapter 或全局设置。
- 诊断工具只输出图形参数和进程类型布尔值，不打印完整命令行。退出 YY 即撤销，无持久配置或正式 Runtime 变化。
- 本机组合实测：用户确认进入频道后已可使用；Renderer 仍独立，未枚举到 GPU 子进程。仍需语音与无调试器／正式 Runtime 重复验证，不能视作通用补丁验收。
