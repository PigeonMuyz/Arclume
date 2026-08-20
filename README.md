# Procyon+

> 基于 [italomandara/Procyon](https://github.com/italomandara/Procyon) 的独立、非官方 macOS 游戏启动器分支。

> 当前 `main` 分支定位为预发布版本：功能、界面和依赖仍可能调整，不代表稳定版或正式发行版。

[简体中文](#简体中文) · [English](#english)

![Procyon+](https://github.com/user-attachments/assets/6ed53e07-5a66-4ada-90d6-f6134e7a275b)

## 简体中文

Procyon+ 统一管理 macOS 原生游戏、Steam 原生游戏，以及由 CrossOver 运行的 Windows Steam 游戏。它不是上游 Procyon 的官方版本，也不代表或获得上游作者背书。

### 主要功能

- 支持导入多个 Steam Library，并分别识别原生 macOS 与 CrossOver 游戏。
- 扫描 `/Applications` 与 `~/Applications` 中声明为 Game 类别的原生 `.app`，作为独立游戏导入管理。
- 为游戏显示「原生」「CrossOver」「未经验证」运行状态标签，并允许在详情页维护兼容性信息。
- 支持每游戏的 CrossOver 图形后端、启动参数、环境变量和其他运行选项；原生 App 提供 Metal HUD 开关。
- 元数据可来自公开 Steam Store 数据、可选的本地 Steam Store 代理，以及原生 App 对应的 App Store 元数据。
- 原生 App 可以在编辑器中从元数据候选图中选择封面 URL；没有封面时安全回退到应用图标或空态。
- 默认提供简体中文界面，也保留英文界面。

### 与上游 Procyon 的差异

| 范围 | Procyon+ |
| --- | --- |
| 产品定位 | 独立的社区维护分支，不是上游正式版本。 |
| 原生游戏 | 支持扫描、导入、编辑和启动 macOS 原生游戏。 |
| 元数据与封面 | 增加本地 Steam Store 代理、App Store 元数据与用户可选封面图。 |
| 游戏库体验 | 支持多个 Steam Library、Steamworks 过滤、加载空态与更明确的平台状态。 |
| 启动链 | 为 CrossOver 游戏回移并改进启动识别与 Steam Cloud 同步等待；原生 App 使用 Bundle ID 生命周期追踪。 |
| Rosetta x87 | 本分支不再捆绑或依赖 rosettaX87 运行时。 |
| 开发方式 | 本分支新增修改允许 AI 辅助与 Vibe Coding；上游的“禁止提交 Vibe Coding 结果”规则不适用于本仓库，但仍适用于向上游提交代码。 |

### 运行要求

- macOS 26.2 或更高版本。
- 运行 Windows Steam 游戏时，需要自行安装 CrossOver，并在设置中选择 CrossOver App 与目标 bottle。
- Steam 身份从本机原生 Steam 和当前 CrossOver bottle 的 `loginusers.vdf` 读取，只使用 SteamID、账户名、显示名与最近登录标记；不会读取密码、SSFN 或会话令牌。

### Steam Store 元数据

默认情况下，Procyon+ 会直接请求公开的 Steam Store API 获取描述、封面和平台元数据，并在请求失败时回退到本地 manifest 或缓存。该请求不需要 Steam 登录凭据。

如需调试或通过本地适配器转发请求，也可以在仓库根目录运行：

```bash
python3 script/local_steam_proxy.py
```

然后在应用的“设置 → 游戏元数据”中选择“本地 Steam Store 代理”，并重新加载游戏库。该代理仍只查询公开商店数据。

### 构建

```bash
xcodebuild -project Procyon.xcodeproj -scheme Procyon -configuration Debug build
```

### AI / Vibe Coding 与贡献说明

Procyon+ 是一个 AI 辅助开发分支：本分支新增修改可以采用 Vibe Coding 工作流。提交前仍应阅读受影响代码、说明改动来源，并提供可复现的手动验证结果。

上游 Procyon 明确不接受 Vibe Coding 结果。请不要将本仓库的 AI 辅助修改原样提交到上游；如需上游贡献，必须先按上游规则独立审查、重构和验证。

### 许可证与声明

本仓库中的 Procyon 源代码以 [GNU GPL v3.0 only](LICENSE.txt) 发布。请保留上游版权、许可证文本和本仓库的 [NOTICE](NOTICE.md)。发布二进制版本时，必须同时提供对应版本的完整源码。

预编译运行库、字体、游戏相关配置/资源和其他第三方组件不因本项目采用 GPL 就自动转为 GPL；发布时请同时遵守其各自的许可证和再分发条件，详见 [第三方声明](THIRD-PARTY-NOTICES.md)。

---

## English

Procyon+ is an independent, unofficial macOS game-launcher fork of [italomandara/Procyon](https://github.com/italomandara/Procyon). It manages native macOS games, native Steam games, and Windows Steam games run through CrossOver. It is not an official upstream release and is not endorsed by the upstream author.

The `main` branch is currently a pre-release line. Features, UI, and dependencies may change before a stable or formal release.

### Highlights

- Multiple Steam Library folders with native macOS and CrossOver game discovery.
- Import and management of native `.app` games from `/Applications` and `~/Applications` when they declare the Game application category.
- Native, CrossOver, and Unverified runtime tags, with per-game compatibility information.
- Per-game CrossOver launch settings and a Metal HUD setting for native apps.
- Public Steam Store metadata, an optional loopback-only Steam Store proxy, and App Store metadata/image candidates for native apps.
- User-selectable metadata artwork URLs with safe app-icon and empty-state fallbacks.
- Simplified Chinese is the default documentation language; English is included here.

### How this fork differs from upstream

Procyon+ adds native game management, multi-library improvements, metadata and artwork workflows, explicit runtime status, a selective backport of CrossOver launch/Steam Cloud handling, and removes the bundled rosettaX87 runtime dependency.

This fork accepts AI-assisted and Vibe Coding contributions. Upstream Procyon does not accept Vibe Coding results, so changes from this repository must not be submitted upstream unchanged; they require an independent upstream-compliant review, rewrite, and validation.

### Requirements

- macOS 26.2 or later.
- CrossOver is required for Windows Steam games and must be selected with a target bottle in Settings.
- Steam identities are discovered from `loginusers.vdf` in native Steam and the current CrossOver bottle. Procyon+ only uses the SteamID, account/display names, and recent-login flags; it never reads passwords, SSFN files, or session tokens.

### Steam Store metadata

Procyon+ directly requests the public Steam Store API by default, with local-manifest and stale-cache fallback. These requests do not require Steam credentials.

For debugging or local request adaptation, the optional loopback proxy remains available:

```bash
python3 script/local_steam_proxy.py
```

Choose **Local Steam Store proxy** under **Settings → Game metadata**, then reload the library. The proxy only requests public Steam Store data.

### Build

```bash
xcodebuild -project Procyon.xcodeproj -scheme Procyon -configuration Debug build
```

### License

The Procyon source code in this repository is licensed under [GPL-3.0-only](LICENSE.txt). Keep the upstream copyright notices and this repository's [NOTICE](NOTICE.md) when redistributing it.

Prebuilt runtime libraries, fonts, game-related configuration/resources, and other third-party components are not relicensed by this project; follow their own license and redistribution terms in the [third-party notices](THIRD-PARTY-NOTICES.md).
