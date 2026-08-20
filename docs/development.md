# 开发环境与架构

## 前置条件

- 支持 macOS 26 SDK 的 Xcode。
- Git 与 Git LFS。
- 可选：`jq` 用于 Runtime Manifest 与预检脚本。
- 仅在需要本地 Steam Store 代理时使用 Python 3。

不要把用户实际游戏、Bottle 或 `~/Library/Application Support/Arclume` 当作开发 fixture。测试和调试应使用临时目录、受控样本或 App 内置的 Debug fixture。

## 仓库地图

| 区域 | 责任 |
| --- | --- |
| `Arclume/Components` | SwiftUI 页面、设置、工具栏与可见交互。 |
| `Arclume/Services` | 游戏发现、Steam、元数据、运行状态与业务服务。 |
| `Arclume/OnlineGame*.swift` | 剑网 3 发现、Bottle、配置、迁移、进程监控与启动。 |
| `Arclume/BundledWineRuntime.swift` | 已验证 Runtime 的安装、校验、启动环境与原子更新。 |
| `Arclume/Resources/OnlineGameDependencies` | LFS 管理的 Runtime、D3DMetal、字体和依赖。 |
| `ArclumeTests` | 纯逻辑、文件格式、迁移与进程识别测试。 |
| `ArclumeUITests` | SwiftUI 可访问性与首启流程 UI XCTest。 |

## 本地命令

基础无签名构建：

```bash
xcodebuild \
  -project Arclume.xcodeproj \
  -scheme Arclume \
  -configuration Debug \
  -derivedDataPath /tmp/arclume-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`./script/pr_preflight.sh` 只读取 Git LFS 状态，并校验发布 Runtime 归档的 SHA-256；它不会运行 `git lfs fsck`，因此不会为检查而移动本地 LFS 对象。

常用开发启动：

```bash
./script/build_and_run.sh run
```

该脚本需要本地 `Arclume/Config.xcconfig`；不要提交它。

## Runtime 接入

本仓库不构建 Wine。Runtime Release 必须先由独立 Runtime 项目生成并验证，再使用：

```bash
./script/embed_runtime_release.sh \
  --archive /path/to/arclume-wine-*.tar.xz \
  --manifest /path/to/arclume-wine-*.runtime.json
```

脚本会检查 Runtime ID、文件名和 SHA-256，但不会自动删除旧归档。删除旧资源必须是独立、可审查的 App 变更。

## 可访问性与 UI fixture

UI 自动化依赖稳定的 accessibility identifier。新交互控件应提供语义化、稳定的 identifier，而不是文案或坐标。

Debug 模式下，`ARCLUME_UI_TEST_FIXTURE=1` 可加载受控游戏库；`ARCLUME_UI_TEST_MODE` 选择模式；`ARCLUME_UI_TEST_RESET_MODE=1` 仅用于首启状态。它们只能服务于测试，不能进入 Release 行为。
