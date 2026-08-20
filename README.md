# Arclume

> 基于 [italomandara/Procyon](https://github.com/italomandara/Procyon) 的独立、非官方 macOS 游戏启动器。

> 当前 `main` 分支定位为预发布版本：功能、界面和依赖仍可能调整，不代表稳定版或正式发行版。

[简体中文](#简体中文) · [English](#english)

![Arclume](https://github.com/user-attachments/assets/6ed53e07-5a66-4ada-90d6-f6134e7a275b)

## 简体中文

Arclume 统一管理 macOS 原生游戏、Steam 原生游戏，以及由 CrossOver 或 Arclume Wine Runtime 运行的 Windows 游戏。它不是上游 Procyon 的官方版本，也不代表或获得上游作者背书。

### 主要功能

- 支持导入多个 Steam Library，并分别识别原生 macOS 与 CrossOver 游戏。
- 扫描 `/Applications` 与 `~/Applications` 中声明为 Game 类别的原生 `.app`，作为独立游戏导入管理。
- 为游戏显示「原生」「CrossOver」「未经验证」运行状态标签，并允许在详情页维护兼容性信息。
- 支持每游戏的 CrossOver 图形后端、启动参数、环境变量和其他运行选项；原生 App 提供 Metal HUD 开关。
- 元数据可来自公开 Steam Store 数据、可选的本地 Steam Store 代理，以及原生 App 对应的 App Store 元数据。
- 原生 App 可以在编辑器中从元数据候选图中选择封面 URL；没有封面时安全回退到应用图标或空态。
- 默认提供简体中文界面，也保留英文界面。

### 与上游 Procyon 的差异

| 范围 | Arclume |
| --- | --- |
| 产品定位 | 独立维护的 Arclume 产品线，不是上游正式版本。 |
| 原生游戏 | 支持扫描、导入、编辑和启动 macOS 原生游戏。 |
| 元数据与封面 | 增加本地 Steam Store 代理、App Store 元数据与用户可选封面图。 |
| 游戏库体验 | 支持多个 Steam Library、Steamworks 过滤、加载空态与更明确的平台状态。 |
| 启动链 | 为 CrossOver 游戏回移并改进启动识别与 Steam Cloud 同步等待；原生 App 使用 Bundle ID 生命周期追踪。 |
| Rosetta x87 | 本分支不再捆绑或依赖 rosettaX87 运行时。 |
| 开发方式 | 本分支新增修改允许 AI 辅助与 Vibe Coding；上游的“禁止提交 Vibe Coding 结果”规则不适用于本仓库，但仍适用于向上游提交代码。 |

### 运行时仓库与版本

应用和 Wine 运行时已拆分为两个 GitHub Private Repo：

- `PigeonMuyz/Arclume`：应用 UI、瓶子管理、启动器和内嵌 Runtime Manifest。
- `PigeonMuyz/Arclume-Runtime`：Wine 源码锁定、补丁、构建脚本、运行时 ABI 与发行 Manifest。

App 首次发布仍内嵌已验证的 Runtime，以保障离线初始化；`Runtime.lock.json` 和 App 资源中的 Manifest 固定其版本、ABI、归档 SHA-256 与旧版迁移规则。Runtime 的公开版本遵循 `Arclume Wine 1.0.*`，不直接复用上游 Wine 版本号。

### 自动构建与发布

推送 `v*` 标签，或在 GitHub Actions 手动传入既有标签，可由“构建并发布 macOS DMG”工作流在 `macos-26` runner 上检出 LFS 资源、构建通用 DMG，并把 DMG 与 SHA-256 校验文件上传到对应 Release。该工作流不保存任何签名或公证私钥，所以默认产物未签名、未公证；需要面向普通用户分发时，应另行接入 Developer ID 和 Apple Notary 凭据。

### 从 Procyon+ 迁移

首次打开 Arclume 时，若检测到旧的 `~/Library/Application Support/Procyon`，会在同一磁盘卷内移动到 `~/Library/Application Support/Arclume`，不会复制 Games 容器或 Wine 前缀。旧的偏好域会一次性导入到 Arclume；如果目标目录已存在，只移动不冲突的顶层内容，避免覆盖用户的新数据。

### 运行要求

- macOS 26.0 或更高版本。
- 运行 Windows Steam 游戏时，需要自行安装 CrossOver，并在设置中选择 CrossOver App 与目标 bottle。
- Steam 身份从本机原生 Steam 和当前 CrossOver bottle 的 `loginusers.vdf` 读取，只使用 SteamID、账户名、显示名与最近登录标记；不会读取密码、SSFN 或会话令牌。

### Steam Store 元数据

默认情况下，Arclume 会直接请求公开的 Steam Store API 获取描述、封面和平台元数据，并在请求失败时回退到本地 manifest 或缓存。该请求不需要 Steam 登录凭据。

如需调试或通过本地适配器转发请求，也可以在仓库根目录运行：

```bash
python3 script/local_steam_proxy.py
```

然后在应用的“设置 → 游戏元数据”中选择“本地 Steam Store 代理”，并重新加载游戏库。该代理仍只查询公开商店数据。

### 构建

```bash
xcodebuild -project Arclume.xcodeproj -scheme Arclume -configuration Debug build
```

### AI / Vibe Coding 与贡献说明

Arclume 是一个 AI 辅助开发项目：本项目新增修改可以采用 Vibe Coding 工作流。提交前仍应阅读受影响代码、说明改动来源，并提供可复现的手动验证结果。

上游 Procyon 明确不接受 Vibe Coding 结果。请不要将本仓库的 AI 辅助修改原样提交到上游；如需上游贡献，必须先按上游规则独立审查、重构和验证。

### 许可证与声明

本仓库中的 Arclume 源代码（包括其上游 Procyon 衍生部分）以 [GNU GPL v3.0 only](LICENSE.txt) 发布。请保留上游版权、许可证文本和本仓库的 [NOTICE](NOTICE.md)。发布二进制版本时，必须同时提供对应版本的完整源码。

预编译运行库、字体、游戏相关配置/资源和其他第三方组件不因本项目采用 GPL 就自动转为 GPL；发布时请同时遵守其各自的许可证和再分发条件，详见 [第三方声明](THIRD-PARTY-NOTICES.md)。

---

## English

Arclume is an independent, unofficial macOS game launcher based on [italomandara/Procyon](https://github.com/italomandara/Procyon). It manages native macOS games, native Steam games, and Windows games run through CrossOver or Arclume Wine Runtime. It is not an official upstream release and is not endorsed by the upstream author.

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

Arclume adds native game management, multi-library improvements, metadata and artwork workflows, explicit runtime status, a selective backport of CrossOver launch/Steam Cloud handling, and removes the bundled rosettaX87 runtime dependency.

This fork accepts AI-assisted and Vibe Coding contributions. Upstream Procyon does not accept Vibe Coding results, so changes from this repository must not be submitted upstream unchanged; they require an independent upstream-compliant review, rewrite, and validation.

### Runtime repositories

`PigeonMuyz/Arclume` owns the App, launcher integration and bundled Runtime Manifest. `PigeonMuyz/Arclume-Runtime` owns Wine source locks, patches, build scripts, ABI and release manifests. The App embeds a tested runtime for first-run/offline setup, while `Runtime.lock.json` pins the selected private Runtime release.

### Automated builds and releases

Pushing a `v*` tag, or manually providing an existing tag in GitHub Actions, runs the **Build and release macOS DMG** workflow on `macos-26`. It checks out LFS assets, builds a universal DMG, and uploads the DMG plus a SHA-256 file to the matching Release. The workflow intentionally stores no signing or notarization secret, so its default artifacts are unsigned and unnotarized; Developer ID and Apple Notary credentials are required before general end-user distribution.

### Migration from Procyon+

On first launch, Arclume moves an existing `~/Library/Application Support/Procyon` directory to `~/Library/Application Support/Arclume` on the same volume, so Games containers and Wine prefixes are not copied. Preferences are imported once. If the destination already exists, only non-conflicting top-level entries are moved.

### Requirements

- macOS 26.0 or later.
- CrossOver is required for Windows Steam games and must be selected with a target bottle in Settings.
- Steam identities are discovered from `loginusers.vdf` in native Steam and the current CrossOver bottle. Arclume only uses the SteamID, account/display names, and recent-login flags; it never reads passwords, SSFN files, or session tokens.

### Steam Store metadata

Arclume directly requests the public Steam Store API by default, with local-manifest and stale-cache fallback. These requests do not require Steam credentials.

For debugging or local request adaptation, the optional loopback proxy remains available:

```bash
python3 script/local_steam_proxy.py
```

Choose **Local Steam Store proxy** under **Settings → Game metadata**, then reload the library. The proxy only requests public Steam Store data.

### Build

```bash
xcodebuild -project Arclume.xcodeproj -scheme Arclume -configuration Debug build
```

### License

The Arclume source code in this repository, including its upstream-derived Procyon portions, is licensed under [GPL-3.0-only](LICENSE.txt). Keep the upstream copyright notices and this repository's [NOTICE](NOTICE.md) when redistributing it.

Prebuilt runtime libraries, fonts, game-related configuration/resources, and other third-party components are not relicensed by this project; follow their own license and redistribution terms in the [third-party notices](THIRD-PARTY-NOTICES.md).
