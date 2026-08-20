# 贡献指南

感谢你为 Arclume 提交改进。本仓库欢迎经过审查、可复现验证的人工或 AI 辅助贡献；贡献者仍需对代码、许可证、测试证据和用户影响负责。

## 开始前

1. 阅读 [AGENTS.md](AGENTS.md)、[开发环境](docs/development.md) 和 [测试策略](docs/testing.md)。
2. 安装 Git LFS，并确认资源已取回：

   ```bash
   git lfs install
   git lfs pull
   ```

3. 使用支持 macOS 26 SDK 的 Xcode 版本。
4. 不要提交 `DerivedData/`、个人配置、游戏目录、Bottle、日志、下载归档或凭据。

## 选择正确的仓库

| 改动 | 目标 |
| --- | --- |
| SwiftUI、游戏库、Bottle、启动器、迁移、App 更新 | `Arclume` |
| Wine 源码、补丁、构建、Runtime ABI、Runtime Release | `Arclume-Runtime` |
| Runtime 被 App 使用的版本 | 两个仓库各自完成审核后，通过 Manifest 和 `script/embed_runtime_release.sh` 接入 |

不要直接替换 `Arclume/Resources/OnlineGameDependencies` 中的 Runtime 归档。必须先验证 Runtime Manifest、归档名和 SHA-256。

## 提交流程

1. 从最新 `main` 建立短生命周期分支，例如 `fix/launcher-monitor` 或 `docs/testing-plan`。
2. 保持一个 PR 聚焦一个逻辑问题；拆开重构、功能和发布变更。
3. 每个 PR 新增一份 `CHANGELOG/unreleased/YYYY-MM-DD-HHMMSS-english-kebab-case.md`。条目正文可使用中文；详情见 [CHANGELOG/README.md](CHANGELOG/README.md)。
4. 运行与改动匹配的验证，并在 PR 模板中粘贴命令和结果。
5. 使用中文、清楚的提交信息，例如 `修复启动器进程监听`。常规开发提交不要使用 `release:` 前缀。
6. 发起非草稿 PR 前，执行：

   ```bash
   ./script/pr_preflight.sh
   ```

## 验证要求

| 改动范围 | 最低要求 |
| --- | --- |
| 文档、模板、Issue 配置 | 差异检查、Markdown 链接与 preflight 静态检查 |
| Swift / SwiftUI | 无签名 Debug build |
| 纯逻辑、解析、迁移 | 对应核心测试；若暂缺测试，在 PR 写明原因和后续测试计划 |
| UI | Debug build、fixture 或手工交互证据；UI XCTest 仅按测试策略显式执行 |
| Runtime / Manifest / LFS 资源 | Manifest、ABI、SHA-256、迁移和回滚说明 |
| 发布工作流 | 指令解析、内部版本一致性、DMG/校验和流程审核 |

当前默认预检不会运行 XCTest。新的测试分层仍在规划中，详见 [docs/testing.md](docs/testing.md)。

## AI 辅助开发

可以使用 AI 进行分析、起草或实现，但 PR 必须披露其使用情况，并由贡献者完成：

- 受影响调用链和资源协议的人工审查；
- 真实构建或测试证据；
- 用户数据、隐私、许可证、版权和第三方归属检查；
- 对无法验证内容的明确说明。

AI 辅助变更必须经过独立审查后，才能作为 Arclume 的社区贡献合并。

## 发布

发布由维护者执行，完整规则见 [docs/release.md](docs/release.md)。只有内部版本已更新、变更记录已整理、远端提交 SHA 已确认后，才可以使用 `release:` 指令。

## 获取帮助

使用 [SUPPORT.md](SUPPORT.md) 中的渠道；安全问题请遵循 [SECURITY.md](SECURITY.md)，不要公开漏洞细节。
