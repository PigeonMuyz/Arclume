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
| `Arclume/App` | App 入口、场景、生命周期与模式状态。 |
| `Arclume/Features` | 按功能划分的启动器、引导、设置、项目编辑、导入和剑网 3 页面。 |
| `Arclume/Components/Shared` | 跨页面复用的基础 UI 组件。 |
| `Arclume/Models` | 游戏、Steam、兼容性等共享数据类型。 |
| `Arclume/Services` | 按领域划分的发现、启动、迁移、元数据、下载和更新服务。 |
| `Arclume/Services/Runtime/BundledWineRuntime.swift` | 已验证 Runtime 的安装、校验、启动环境与原子更新。 |
| `Arclume/Support` | 文件、配置、本地化等基础工具；Testing 中存放隔离预览与测试宿主。 |
| `Arclume/Resources/OnlineGameDependencies` | LFS 管理的 Runtime、D3DMetal、字体和依赖。 |
| `ArclumeTests` | 纯逻辑、文件格式、迁移与进程识别测试。 |
| `ArclumeUITests` | SwiftUI 可访问性与首启流程 UI XCTest。 |

完整分组和新增文件放置规则见 [项目目录](project-structure.md)。目录仅用于组织代码，不改变 Swift 模块或数据路径。

## 本地命令

基础无签名构建：

```bash
xcodebuild \
  -project Arclume.xcodeproj \
  -scheme Arclume \
  -configuration Debug \
  -derivedDataPath /tmp/arclume-derived \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`./script/pr_preflight.sh` 只读取 Git LFS 状态，并检查 Runtime Manifest 结构和 SHA-256 字段格式、App 资源打包边界；它不读取大型归档进行哈希校验，也不会运行 `git lfs fsck` 或移动本地 LFS 对象。

常用开发启动：

```bash
./script/build_and_run.sh run
```

`Arclume/Config.xcconfig` 是已纳入版本管理的默认配置；私有配置写入被忽略的 `Arclume/Config.local.xcconfig`，不要提交私有地址或凭据。

运行脚本默认使用 Xcode 项目配置的 Apple Development 签名，需要对应团队的本地有效证书。
不要用临时签名构建验证麦克风授权是否持久保存：临时签名的代码身份随构建变化，系统可能重新询问授权。
没有证书时可以显式运行 `ARCLUME_CODE_SIGN_IDENTITY=- ./script/build_and_run.sh run`，但该产物不能作为隐私授权的验收版本。
无签名预检仍保留，不需要开发证书。从临时签名切换到证书签名时可能需要重新授权一次；不得修改或重置 TCC 数据库来掩盖此差异。

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
