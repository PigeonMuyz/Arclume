# 重置设置与应用数据，移除 CXPBottles 默认路径

- 设置新增“重置”页面，明确容器内游戏、程序、存档与登录数据也在范围内；二次确认并输入“重置”后，经 Wine 退出门禁提交重置意图并退出。
- 下次启动在旧数据迁移、游戏库扫描和预热之前，检查 Wine 已退出，将仅 Application Support/Arclume 移至废纸篓，清除 Arclume 两个偏好域，保留防止旧 Procyon 数据/设置再次导入的标记。设置不保留；文件可从废纸篓恢复。外部游戏、其他应用偏好、系统 TCC 授权和 Library/Logs 不在范围内。
- 停止或提交失败取消重置，启动清理失败不加载正常界面并保留重试意图；不跟随根目录符号链接，不递归删除用户数据。
- 移除游戏库启动时自动创建 CXPBottles 和补丁默认路径覆盖。旧 CrossOver 显式配置继续读取；缺失配置使用 CrossOver 自己的默认路径。下次正常启动用 rmdir 仅移除空 CXPBottles，非空目录及符号链接保留，不递归删除已有旧容器。
- 若有另一个 Arclume 实例运行，拒绝提交或执行重置，避免旧实例再次写回状态。
- 不执行本机真实重置、不修改 Runtime/ABI、不发布。回滚版本若忽略待处理重置标记，不会执行重置；完成重置后用户需重新初始化，可从废纸篓手动恢复文件。

## 验证结果

- `./script/pr_preflight.sh` 无签名 Debug build、Manifest SHA-256、workflow 静态检查通过；`git diff --check` 通过。
- `xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS' -derivedDataPath /tmp/arclume-context-menu-tests -only-testing:ArclumeTests/ArclumeResetTests -only-testing:ArclumeTests/WineTerminationTests -only-testing:ArclumeTests/ArclumeDataMigrationTests DEVELOPMENT_TEAM=8JFR5LUFAJ`：14 项通过。
- 全部使用私有偏好域和临时目录/进程，验证重置范围、双偏好清理、防迁移标记、目录缺失、移动失败保留状态、宽泛路径和符号链接拒绝、退出顺序/失败取消、空 CXPBottles 清理且非空和符号链接保留。Fixture 以临时目录模拟废纸篓，不触碰用户废纸篓。
- 未运行 UI XCTest、未实际点击重置/触发真实废纸篓操作、未覆盖 /Applications 安装版，未提交或推送。首次手工验收应使用独立测试账户，不用实际游戏容器验证有损操作。
