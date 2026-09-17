# 多容器 Wine 预热与退出清理

- 勾选“随 Arclume 启动并预热 Wine”后展示 Steam / Windows 应用、Games / 剑网3 多选；设置页与初始化页共用选择，移除原说明段落。
- 每个容器独立预热、超时和暂停；切换模式不再关闭其他已选择容器的保温。尚未初始化的容器等待就绪，不自动安装或创建。
- 旧版已开启的预热迁移为原模式单个容器；默认仍关闭，显式空选择和已保存的多选不被覆盖。
- 正常退出 Arclume 时先封闭启动入口、释放保温，再等待所属 Runtime 的所有 Wine 进程退出（包括 WineServer 和仍在运行的 Windows 应用）。先请求结束，超时后强制结束；清理失败取消 App 退出并显示错误。其他 Wine / CrossOver 不在清理范围。
- 关闭预热开关或取消单个容器只释放相应保温助手，不因此强制结束游戏；完整清理只在退出 Arclume 或用户手动停止 Wine 时执行。
- 不删除容器、注册表、登录或游戏数据；不修改 Runtime、ABI、App 版本或发布物。回滚此代码恢复原退出行为；已有多选偏好可保留但旧版忽略。强制退出 App、崩溃和断电不保证执行正常退出清理。

## 手工验证

- 开关关闭时不展示子选项；打开后可同时选两个容器，重启保留选择，切换模式不改变选择。
- 已准备好的容器分别显示预热状态，未初始化的容器等待；取消一个不影响另一个。
- 先保存 Windows 应用工作，再正常退出 Arclume，确认所属 Runtime 无残留进程，其他 Wine 安装不受影响。

## 本次验证结果

- `./script/pr_preflight.sh` 无签名 Debug build、Runtime SHA-256 和静态检查通过；`git diff --check` 通过。
- `xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS' -only-testing:ArclumeTests/WineWarmupTests -only-testing:ArclumeTests/WineTerminationTests -only-testing:ArclumeTests/YYLaunchSupportTests -only-testing:ArclumeTests/WindowsGameLaunchRulesTests`：20 项通过。验证多选编解码、旧偏好只迁移一次、退出等待/失败重试/重复请求、启动门禁和临时所属进程清理且不影响无关进程。
- 使用 Debug 隔离窗口验证默认关闭、打开后显示两个复选框、可同时选择、取消一个不影响另一个、主开关收起后重新打开保留选择；偏好写入独立 UUID suite，测试后已清理。未运行 UI XCTest、未启停真实 YY 或游戏。
- 开发版签名校验通过；无 Wine 会话时正常退出 App 已确认。真实双容器预热、带游戏运行的退出清理未做真机端到端验证。
- 未提交、推送、发布或覆盖 `/Applications` 中的安装版。
