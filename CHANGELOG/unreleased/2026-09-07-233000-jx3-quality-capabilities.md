# 修复画质设置与 DLSS 能力声明混用

- `machine_config.ini` 的 `DLSS=1/2` 仅声明 DLSS / DLSS FG 能力，不代表实际启用游戏中的超分或帧生成。启动设置改名为「DLSS FG 支持」，兼容已有偏好键。
- 初始化保留已有的 `DLSS=1/2`；画质保存和预设导入不再修改能力声明或重启初始化轮询。
- 画质面板只写修改过的控件，打开面板不触发写入；保留原有正数 `AAOPTION_DLSSOption`、未编辑和未知配置。
- 分离 DLSS、FSR2、NIS 锐度；FSR 档位仅修改 FSR2Option，不再覆盖 FSR3 参数。删除错误连接到 FSR2Option 的 DLSS 档位控件，待客户端枚举映射确认后再提供。
- 切换抗锯齿时清除竞争算法的启用标志；导入预设取消尚未执行的自动保存，防止旧设置覆盖预设；快速关闭面板时保存最后一次修改。INI 读取兼容 UTF-8 BOM 和键名大小写，写入保留 BOM 和换行格式。
- 验证：运行 PR 前置审核（无签名 Debug build，不运行 XCTest）；临时 INI fixture 检查增量写入、算法切换、能力声明保留和 CRLF 保留。
- 手工验证：在 Arclume 画质面板依次调整帧率、锐度和抗锯齿，关闭后重开确认；检查机器能力声明不变，再重启游戏确认画质。未替换 Applications 中的 App，也未发布 Runtime。
