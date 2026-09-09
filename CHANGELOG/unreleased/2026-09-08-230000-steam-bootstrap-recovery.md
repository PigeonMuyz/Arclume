# Steam 更新交接恢复与临时 Wine 进程识别

- 结束 Arclume Wine 时，补充识别 Wine 从 `winetemp-*` 临时目录启动的重命名 Windows 进程。必须通过实际映射的 Arclume Runtime `ntdll.so` 证明归属，不能只凭 Steam.exe 等名称判断；发送信号前仍复核进程身份。
- 支持按 WINEPREFIX 限定停止范围；无法读取已归属进程的容器时明确失败，不误报完成或扩大停止范围。临时文件查询有超时和大小限制，不保存进程环境。
- 从应用打开内置 Steam 后，观察本次新增 bootstrap 日志。当更新完成且记录 Shutdown，旧 Steam 进程仍在、没有 steamwebhelper，并持续 30 秒时，工具栏和设置显示“重新启动 Steam”。观察最多 15 分钟，只读取末尾 32 KB，不复制或增长日志。
- 恢复必须由用户确认；执行前再次检查停滞证据，仅结束 Steam 容器并重新打开 Steam，不自动循环重启、不结束 Games 容器、不删除缓存、账户或游戏文件。失败保留明确错误入口。
- 防止日志 URL 文件大小缓存导致遗漏新记录；切换容器或结束 Wine 时取消旧观察；全局结束操作与 Steam 恢复相遇时顺序完成各自的停止范围。

## 验证与影响

- 无 XCTest。使用隔离原生进程加载临时 ntdll fixture，验证重命名加载器归属、WINEPREFIX 读取、Steam 范围停止、保留 Games 和外部 Wine、未知容器安全失败。
- 独立 Swift 验证旧日志忽略、更新完成识别、新启动与 helper 排除、截断日志及 32 KB 读取上限；复跑停止服务的升级信号、短暂空列表与超时检查。
- 执行 Debug build、pr_preflight、git diff --check；真实 Steam 更新交接和按钮交互仍需手工复测，不宣称解决 Steam 内部卡住的根因。
- 不修改 Runtime 归档或版本，不提交、推送或发布。
