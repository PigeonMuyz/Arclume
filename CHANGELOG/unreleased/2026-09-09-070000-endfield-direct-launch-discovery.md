# 识别终末地游戏本体并使用已验证的窗口启动方式

- 时间：2026-09-09T07:00:00+08:00
- 类型：fix
- 范围：App 游戏库扫描与启动

## 改动

- 内置 Wine 游戏库刷新时扫描当前容器中的 Endfield.exe，验证 PE 文件头及 Unity 配套文件后添加游戏本体，保留鹰角启动器用于更新。
- 安装后识别不再因存在启动器快捷方式而丢弃终末地游戏本体；重复扫描不会重复添加同一 EXE。
- 内置 Wine 直接启动终末地时，补充国服启动器参数与 1280×720 窗口默认参数；用户显式参数优先，其他游戏及 CrossOver 启动参数不变。

## 用户影响与兼容性

- 不迁移旧启动器入口，不删除或重置 Bottle、游戏文件、缓存、登录与画质设置。不自动开启 FSR 帧生成。
- 默认路径优先探测，其他容器内安装位置沿用有界只读扫描；不跟随游戏目录链接到容器外。
- 撤销本次代码可恢复原扫描/启动行为；已添加的游戏入口可在游戏库中移除。未变更 Runtime、Manifest 或发布版本。

## 验证

- 用户确认相同直接启动命令在关闭 FSR 帧生成后可以进入并游玩。
- 新增隔离临时目录测试：识别与去重、参数默认/覆盖、非目标程序与未完成安装、快捷方式共存、自定义位置与越界链接。
- `./script/pr_preflight.sh`：无签名 Debug build、Runtime SHA-256 与发布工作流检查通过。
- `xcodebuild test -project Arclume.xcodeproj -scheme Arclume -destination 'platform=macOS' -only-testing:ArclumeTests/WindowsGameLaunchRulesTests`（独立 DerivedData、ad hoc 签名）：5 项测试全部通过，未运行 UI XCTest。
- `./script/build_and_run.sh --verify`：开发版构建启动成功；实际游戏库显示独立的终末地与鹰角启动器，持久化入口为 Endfield.exe。
- 尚未重新点击新游戏库入口启动（用户当前游戏保持运行）；已验证其共享启动函数使用同一参数规则。未覆盖 `/Applications/Arclume.app`。
