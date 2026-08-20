# 发布流程

## 版本来源

App 版本只从 Xcode 项目读取：

- `MARKETING_VERSION`：面向用户的版本，例如 `1.0.1`。
- `CURRENT_PROJECT_VERSION`：构建号，例如 `3`。
- GitHub Release tag：`v<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>`，例如 `v1.0.1-3`。

Runtime 版本从 `arclume-wine-runtime.json` 的 `version` 字段读取。不要手动在 Release Notes 中写死 Runtime 版本。

## 发布前检查

1. 所有功能改动都已有 `CHANGELOG/unreleased/` 记录。
2. README、Runtime 文档、第三方声明和发布说明与实际内容一致。
3. 无签名 Release build、DMG 和 SHA-256 的验证路径已完成。
4. 远端 `main` 已包含所有待发布提交，且本地/远端 SHA 一致。
5. Runtime 变更已完成 Manifest、ABI、SHA-256 与迁移审核。

## GitHub Actions 指令

`release-macos.yml` 仅在 `main` 推送且提交信息包含 `release:` 时开始发布，也可以手动触发。

| 指令 | 行为 |
| --- | --- |
| `release: 1.0.1-3` | 指令版本必须等于项目内部版本；不一致时 workflow 失败。 |
| `release: v1.0.1-3` | 与上相同。 |
| `release: github actions` | workflow 读取项目内部版本并生成 tag。 |
| 手动 workflow | 输入 `github actions` 或明确版本。 |

普通功能提交不得携带该前缀。需要发布时，建议让发布指令成为一个专门、可审查的提交。

## 发布产物

| 资产 | 内容 |
| --- | --- |
| `Arclume-<version>-<build>-with-runtime.dmg` | 包含验证过的 Wine 归档，适合首次或离线初始化。 |
| `Arclume-<version>-<build>-no-runtime.dmg` | 移除 Wine 归档，适合已有 Runtime 的用户。 |
| `*.dmg.sha256` | 对应 DMG 的 SHA-256。 |

每个 DMG 都由 `hdiutil verify` 校验。当前 Actions 不保存 Developer ID 或 Notary 凭据，因此产物未签名、未公证；在宣称面向普通用户正式分发前，必须单独接入签名与公证流程。

## 发布后验证

1. 确认 GitHub Release tag、目标 commit、标题、资产和 SHA-256 全部正确。
2. 验证 `with-runtime` 与 `no-runtime` 资产均可下载且大小合理。
3. 在干净环境验证首次引导；`no-runtime` 缺少 Runtime 时应引导用户到“设置 → 更新”。
4. 对已有用户，确认 App 更新不会移动 Games 容器，Runtime 更新不会覆盖用户 Prefix。
