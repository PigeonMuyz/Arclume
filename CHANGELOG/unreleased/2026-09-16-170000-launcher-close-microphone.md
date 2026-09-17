# 修复启动器关闭命中与麦克风主动申请

- 收紧剑网3首页轮播图图片布局和最终点击范围，提升关闭区域层级，增加关闭按钮无障碍名称和 Escape 快捷键；不重新设计卡片。
- 移除剑网3启动流程中的麦克风申请，改为设置 → 通用中的显式授权操作。已决定的权限不再请求，并发操作合并为一次；不修改或重置系统隐私授权，不影响音频输出。
- 本次仅修复 Arclume 主动请求路径；若重复弹窗来自 Wine 子进程或系统签名身份变化，还需弹窗中的应用名与系统日志进一步定位。
- Application Support 不是完整应用状态：主要偏好保存在 group.io.github.pigeonmuyz.arclume 域，旧 Procyon 数据/偏好还有迁移逻辑。CXPBottles 是游戏库 onAppear 创建的旧兼容目录。本次不重置、删除或迁移任何用户数据，不改变旧兼容目录行为。
- Runtime、安装版和发布状态不变；回滚源码即可恢复原交互，新增权限入口无独立持久化设置。

## 验证结果

- `./script/pr_preflight.sh` 通过：无签名 Debug build、Runtime SHA-256 和 workflow 静态检查。
- `xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS' -derivedDataPath /tmp/arclume-context-menu-tests -only-testing:ArclumeTests/MicrophoneAuthorizationTests -only-testing:ArclumeTests/OnlineGameTests DEVELOPMENT_TEAM=8JFR5LUFAJ`：32 项通过。麦克风用注入的模拟状态验证已授权/拒绝/限制不请求、并发请求合并，不触发真实 TCC 弹窗。
- 用户确认反复申请弹窗名称为 Arclume；已移除其游戏启动时的主动申请入口，但未对真实权限弹窗或轮播图点击做端到端复测，未运行 UI XCTest。
- 本机只读确认两个 Arclume Preferences plist 仍存在、Application Support/Arclume/CXPBottles 存在；未读取其中账户内容、未清理数据或覆盖安装版。
