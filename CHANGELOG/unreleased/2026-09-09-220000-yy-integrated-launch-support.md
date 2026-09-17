# YY 9.58 专用兼容启动

- YY JSON 规则新增受限 `launchSupport` 标识，仅允许固定 YY 目录与入口；未知标识、版本或文件哈希不执行补丁。
- Arclume 自动启动随包提供的 GUI 子系统辅助程序，复用经检查的 DNS／OSR 内存修补和进程内软件绘图组合，无需 Homebrew、终端或手动脚本。
- 正式 Wine Runtime 对照已由用户确认：可进入频道，画面和按钮正常。因此不携带或替换此前混合构建的实验 Runtime，不修改 Manifest、ABI 或 Runtime 归档。
- 辅助程序只管理它新建的 YY 进程树；拒绝重复启动，不开放 CEF 调试端口，文件不匹配时停止本次启动。已知组件被更新后应提交新版适配，不尝试猜测新地址。
- 原 DLL、注册表、缓存、登录数据与其他 Windows 程序不改动。退出 YY 后内存修补消失；回滚 App 即撤销该启动逻辑，不需要还原用户文件。
- 待验证：正式辅助程序经 Arclume 启动、再次启动、语音收发与长期稳定性。此次不发布 Release。

## 自动验证

- 无签名 Debug `./script/pr_preflight.sh` 通过，Runtime SHA-256 不变。
- `ArclumeCore` 定向运行 `YYLaunchSupportTests`、`WindowsProgramPresentationTests`、`WindowsGameLaunchRulesTests`，14 项通过；不运行 UI XCTest。
- 正式 GUI 辅助程序在既有正式 Wine 上 `--self-test` 通过；存在 YY 时返回 7 并拒绝新启动，原进程保持运行。两次重建 SHA-256 一致。
- `bash script/build_and_run.sh verify` 构建并启动开发版 App 成功，随包辅助程序哈希和 App 签名校验通过。未覆盖 `/Applications` 中已安装的发布版。
