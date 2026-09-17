# 普通模式程序右键菜单

- 普通模式的剑网3启动器进入通用程序列表，支持卡片编辑、资料补全、编辑、隐藏和卸载入口；保留稳定 ID、剑网3专用启动流程及所属 Games 容器，扫描不覆盖自定义资料或恢复隐藏项。
- 普通模式右键新增“打开安装目录”：Windows 快捷方式解析真实目标，Steam 优先使用安装清单目录，原生 App 打开所在文件夹；路径缺失时禁用，不创建目录。
- 剑网3专用模式保持发现式列表。卸载仍经过原有适配与安全检查；未适配的安装目录不会直接删除。
- 不修改 Runtime、版本或用户安装文件，不发布或覆盖安装版。回滚后新增的自定义库记录仍在偏好中，需留意旧版可能重复显示剑网3入口。

## 验证结果

- `./script/pr_preflight.sh` 通过：无签名 Debug build、Runtime SHA-256 和静态检查；`git diff --check` 通过。
- `xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS' -derivedDataPath /tmp/arclume-context-menu-tests -only-testing:ArclumeTests/LibraryProgramLocationTests -only-testing:ArclumeTests/OnlineGameTests DEVELOPMENT_TEAM=8JFR5LUFAJ`：35 项通过。测试目标旧团队缺少证书，仅命令行覆盖为主 App 团队，工程签名配置未改。
- 新增 5 项隔离测试覆盖真实快捷方式目标、缺失路径、原生 App、Steam 目录与路径穿越、普通模式剑网3属性、隐藏及资料保留；修正 fixture 目录 URL 缺少目录尾斜杠导致的比较失败后全通过。
- 未运行 UI XCTest、真实 Finder 点按或卸载；仍需手工检查普通模式右键菜单和 Finder 跳转，以及专用模式菜单不变。
