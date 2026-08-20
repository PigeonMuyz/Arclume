# Arclume Agent 工作约定

本文件适用于在 Arclume 仓库中工作的自动化 Agent 和维护者。它补充而不替代 [贡献指南](CONTRIBUTING.md)、[测试策略](docs/testing.md) 与 [PR 审核规范](docs/pr-review.md)。

## 工作范围

- `Arclume/` 是 macOS App 源码；`ArclumeTests/` 是核心逻辑测试；`ArclumeUITests/` 是 UI XCTest。
- `Arclume-Runtime` 是独立项目。本仓库只消费 Runtime Manifest 和已验证归档，不在此构建 Wine。
- `Arclume/Resources/OnlineGameDependencies/` 中的 LFS 归档、Runtime Manifest、D3DMetal 与字体属于发布边界，不能顺手重写、删除或改名。
- `Games` 容器、CrossOver Bottle、用户配置、日志和 `~/Library/Application Support/Arclume` 都是用户数据。诊断和实现不得删除、重置或复制它们，除非用户明确授权且目标已确认。

## 变更原则

1. 先定位真实调用链、数据格式和版本来源，再修改。
2. 最小化改动；不因格式化而重写无关文件。
3. Runtime、迁移、启动器和发布变更必须说明兼容性、回滚面和手工验证方式。
4. 每个逻辑改动（一个 PR 或直接提交）都要新增一份 `CHANGELOG/unreleased/` 记录；历史记录不得覆盖或删除。
5. 提交信息默认使用中文。常规提交不得包含 `release:`；该前缀只供经版本审核后的发布提交使用。
6. 未获明确授权，不创建 PR、不合并、不推送、不发布 Release，也不修改远端仓库设置。

## 版本和发布

- App 版本以 Xcode 项目中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 为唯一来源。
- Runtime 版本、ABI、归档名和 SHA-256 以 `arclume-wine-runtime.json` 为唯一来源。
- 发布工作流只接受 `release: <版本>`（必须与项目内部版本一致）或 `release: github actions`（读取项目版本）。
- 发布会生成 `with-runtime` 与 `no-runtime` 两个 DMG；不应在普通 PR 中触发发布。

## 验证与报告

- 默认最小验证是无签名 Debug build；当前不要把 UI XCTest 放入默认验证。
- 需要测试时，先阅读 [docs/testing.md](docs/testing.md)，选择最小测试范围；UI XCTest 必须显式选择，并使用隔离 fixture。
- 变更完成时报告：改动范围、验证命令和结果、未验证部分、用户数据或发布影响。
- 错误、崩溃日志和截图可能含本机路径、账户名或游戏信息；对外引用前先脱敏。

## 交付前检查

```bash
./script/pr_preflight.sh
git diff --check
git status --short
```

如改动涉及 Runtime、发布或迁移，还必须完成 [PR 审核规范](docs/pr-review.md) 中对应的专项检查。
