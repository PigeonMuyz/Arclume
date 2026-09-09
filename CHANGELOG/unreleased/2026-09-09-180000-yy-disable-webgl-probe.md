# YY 频道禁用 WebGL 对照

- 诊断脚本增加 `--run-no-webgl`，在现有 YY 专用 DNS 补丁和 CEF 软件渲染参数上仅追加 `--disable-webgl`。
- 增加参数模式自检及模式日志；不改 libcef 文件、公共 Runtime、注册表或绿色适配数据。关闭本次进程即回滚，不影响从 Arclume 正常启动。
- 频道显示、交互及语音仍需人工验证；依赖 WebGL 的内容可能不可用，未加入正式 Adapter 或设置。
