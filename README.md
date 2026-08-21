# Arclume

> 独立、社区驱动的 macOS 游戏启动器。

[简体中文](#简体中文) · [English](#english)

![Arclume](https://github.com/user-attachments/assets/6ed53e07-5a66-4ada-90d6-f6134e7a275b)

## 简体中文

Arclume 用一个本地游戏库管理 macOS 原生游戏、Steam 原生游戏，以及通过 CrossOver 或 Arclume Wine Runtime 启动的 Windows 游戏。它由 Arclume 社区独立维护，不隶属于 CrossOver、CodeWeavers、Steam 或金山，也不获得其背书。

### 功能

- 导入多个 Steam Library，并区分 macOS 原生游戏、CrossOver 游戏和 Arclume Wine 游戏。
- 扫描 `/Applications` 和 `~/Applications` 中声明为 Game 的原生 App。
- 提供原生、CrossOver 与未经验证的运行状态，以及每游戏的兼容性记录。
- 支持每游戏的 CrossOver 图形后端、启动参数、环境变量与其他运行选项。
- 提供 Arclume Wine Runtime：D3DMetal 3 / 4、DXVK、msync、Metal HUD 和剑网 3 的独立 Games 容器。
- 使用公开 Steam Store 数据、可选本地代理和 App Store 元数据补充游戏信息与封面。
- 提供应用和 Runtime 的独立更新检查、镜像源与自定义更新源。

### 系统要求

- macOS 26.0 或更高版本。
- Windows Steam 游戏可在设置中选择 CrossOver，或使用 Arclume Wine 的独立 Steam 容器；后者不需要安装 CrossOver。
- Arclume Wine Runtime 仅面向 x86_64 Windows 游戏；Apple Silicon Mac 通过 Rosetta 运行其 Wine 进程。

### 安装与更新

Release 提供两种 DMG：

| 文件 | 适用场景 |
| --- | --- |
| `with-runtime` | 首次安装或需要离线初始化 Arclume Wine 的用户。 |
| `no-runtime` | 已安装 Runtime 或希望减小下载体积的用户；可在“设置 → 更新”下载 Runtime。 |

每个 DMG 都附带 SHA-256 文件。配置 Developer ID 证书的 Release 会签名 App，并支持应用内“下载、签名验证、覆盖安装、重启”更新；未配置证书的 Actions 产物只可手动安装。公证状态以对应 Release 说明为准。

应用内更新不会覆盖用户的 `Games`、Steam 或 CrossOver 容器。Runtime 更新会检查 Manifest、ABI 与 SHA-256，并以原子替换方式更新运行时本体。

### 项目结构

| 路径 | 内容 |
| --- | --- |
| `Arclume/` | SwiftUI App、启动器、Bottle、游戏库与资源。 |
| `ArclumeTests/` | 核心逻辑测试，主要使用 Swift Testing。 |
| `ArclumeUITests/`、`ArclumeUITestsLaunchTests.swift` | 需要交互桌面会话的 UI XCTest。 |
| `script/` | 本地构建、Runtime 嵌入和开发辅助脚本。 |
| `CHANGELOG/` | 不可覆盖的变更记录；每个逻辑改动必须新增条目。 |
| `docs/` | 架构、开发、测试、Runtime、发布与审核规范。 |

Wine 的源代码锁定、补丁与独立归档由 `Arclume-Runtime` 项目维护；本仓库通过 Runtime Manifest 固定 ABI、版本、归档名和 SHA-256。详见 [Runtime 文档](docs/runtime.md)。

### 开发

先安装 Git LFS，并取得所有 LFS 资源：

```bash
git lfs install
git lfs pull
```

基础构建：

```bash
xcodebuild \
  -project Arclume.xcodeproj \
  -scheme Arclume \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

贡献前请阅读：

- [贡献指南](CONTRIBUTING.md)
- [Agent 工作约定](AGENTS.md)
- [开发环境](docs/development.md)
- [测试策略与新 XCTest 计划](docs/testing.md)
- [PR 审核规范](docs/pr-review.md)
- [发布流程](docs/release.md)

### 参与共建

Arclume 是独立项目，在本仓库维护和发布。欢迎通过 Issue、讨论和 PR 一起维护启动体验、兼容性、Runtime 集成、文档与测试；所有贡献均按本仓库的 [贡献指南](CONTRIBUTING.md) 和 [行为准则](CODE_OF_CONDUCT.md) 审核。

### 社区与支持

- 功能或兼容性请求：使用 Issue 模板，并附上脱敏后的诊断日志。
- 安全问题：请遵循 [安全策略](SECURITY.md)，不要公开漏洞细节。
- 使用问题与日志隐私：见 [支持说明](SUPPORT.md)。
- 行为规范：见 [行为准则](CODE_OF_CONDUCT.md)。

### 许可证与第三方组件

Arclume 源代码采用 [GNU GPL v3.0 only](LICENSE.txt)。发布二进制时必须提供相应版本的完整源码，并保留现有源文件中的版权、许可证及适用的附加法律声明。

Wine、DXVK、D3DMetal、字体和游戏相关资源拥有各自的许可证与再分发条件；它们不会因 Arclume 使用 GPL 自动改变许可证。D3DMetal 不是 Arclume 开源代码，也不因本仓库公开而改变其 Apple 条款。每个二进制 Release 均在同一 GitHub Release 页面指向对应源码与第三方声明；详见 [第三方声明](THIRD-PARTY-NOTICES.md)。

---

## English

Arclume is an independent, community-driven macOS game launcher. It manages native macOS games, native Steam games, and Windows games launched through CrossOver or the Arclume Wine Runtime. It is independently maintained by the Arclume community and is not affiliated with or endorsed by CrossOver, CodeWeavers, Steam, or Kingsoft.

### Highlights

- Multiple Steam Library imports, native/CrossOver discovery, and native Game-app scanning.
- Per-game compatibility data, launch options, graphics backends, environment variables, and metadata artwork.
- An independently versioned Arclume Wine Runtime with D3DMetal 3/4, DXVK, msync, Metal HUD, and a dedicated JX3 Games prefix.
- Separate application and Runtime update checks, automatic fallback, built-in mirrors, and custom HTTPS update sources.

### Requirements

- macOS 26.0 or later.
- CrossOver is user-supplied for Windows Steam games.
- The bundled Runtime targets x86_64 Windows software; Wine runs through Rosetta on Apple Silicon Macs.

### Distribution

Each Release contains two unsigned, unnotarized DMGs and matching SHA-256 files:

- `with-runtime` includes the verified Wine archive for first-run or offline setup.
- `no-runtime` is smaller and is intended for users who already have a Runtime; the Runtime can be downloaded in **Settings → Updates**.

Application updates never replace a user's `Games` prefix. Runtime updates validate their Manifest, ABI and SHA-256, then atomically replace only the immutable runtime files.

### Contributing

Arclume is maintained and released here. Start with [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md), and the [documentation index](docs/development.md). Every logical change must add a new immutable entry under [CHANGELOG/](CHANGELOG/README.md).

### License

Arclume source code is licensed under [GPL-3.0-only](LICENSE.txt). Runtime libraries, fonts, and game-related resources retain their own licenses; see [NOTICE.md](NOTICE.md) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
