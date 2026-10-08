# 恢复启动器卸载入口

- 在启动器“更多操作”末尾恢复 Windows 自定义游戏/程序的“卸载…”入口，沿用原游戏卡片的适用范围。
- 打开现有卸载预览与确认界面，固定捕获被选中的项目；不直接删除文件，不改变目录校验、运行中保护或数据保留选项。
- 不修改 Runtime、容器格式或游戏安装；移除新增菜单和弹层绑定即可回退。原生 App 和 Steam 项目不引入新的卸载行为。
- 手工验证：选择 Windows 项目，打开“更多操作 → 卸载…”，检查目标并取消；不应移除游戏。真实卸载需用户另行确认。
- 验证：`./script/pr_preflight.sh`（含无签名 Debug 构建）、`git diff --check` 通过；`ArclumeCore` 的 `LauncherRemovalTests` 与 `GameAssociatedDataTests` 共 13 项通过。未运行 UI XCTest 或真实卸载。
