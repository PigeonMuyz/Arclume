# 发布流程

## 版本来源

App 版本只从 Xcode 项目读取：

- `MARKETING_VERSION`：面向用户的版本，例如 `1.0.4`，每次公开发布必须递增。
- `CURRENT_PROJECT_VERSION`：内部构建号，例如 `9`，保留但不拼接到显示版本和发布名称中。
- GitHub Release tag：`v<MARKETING_VERSION>`，例如 `v1.0.4`；更新器仍兼容历史 `v1.0.3-8` 格式。

Runtime 版本从 `arclume-wine-runtime.json` 的 `version` 字段读取。不要手动在 Release Notes 中写死 Runtime 版本。
运行资源下载基础地址必须通过 GitHub Actions Secret `ARCLUME_RESOURCE_BASE_URL` 提供，并在构建时注入；源码和文档不得写入实际服务地址。

## 发布前检查

1. 所有功能改动都已有 `CHANGELOG/unreleased/` 记录。
2. README、Runtime 文档、第三方声明和发布说明与实际内容一致。
3. 已确认唯一发布 DMG `Arclume-<version>.dmg` 及其 SHA-256 文件会随 Release 上传；应用内更新以 SHA-256、Bundle ID 和版本/构建号作为安装前校验。
4. 远端 `main` 已包含所有待发布提交，且本地/远端 SHA 一致。
5. Runtime 变更已完成 Manifest、ABI、SHA-256 与迁移审核。

## GitHub Actions 指令

`release-macos.yml` 仅在 `main` 推送且提交信息包含 `release:` 时开始发布，也可以手动触发。

| 指令 | 行为 |
| --- | --- |
| `release: 1.0.4` | 指令版本必须等于项目内部版本；不一致时 workflow 失败。 |
| `release: v1.0.4` | 与上相同。 |
| `release: github actions` | workflow 读取项目内部版本并生成 tag。 |
| 手动 workflow | 输入 `github actions` 或明确版本。 |

普通功能提交不得携带该前缀。需要发布时，建议让发布指令成为一个专门、可审查的提交。

## 发布产物

| 资产 | 内容 |
| --- | --- |
| `Arclume-<version>.dmg` | 唯一安装包；不包含 Wine、D3D 运行组件或资源归档。App 按需从配置的对象存储资源源下载运行资源。 |
| `Arclume-<version>.dmg.sha256` | 安装包的 SHA-256。 |

DMG 由 `hdiutil verify` 校验。发布流程还会检查 App Bundle 中没有资源归档、DLL、Wine/D3D 运行组件或复制到 Resources 的 dylib。Manifest、JSON、INI 和第三方声明仍随 App 保留；已排除的独立 OTF 字体继续保持排除。应用内更新会校验下载 DMG 的 SHA-256、Bundle ID、版本和构建号，然后使用暂存替换和回滚路径覆盖当前 App；不会校验发布 App 的开发者签名。

`ARCLUME_RESOURCE_BASE_URL` 是发布所必需的 Secret。若仓库另行配置下列签名 Secrets，workflow 会导入 Developer ID 证书并签名 Archive 和 DMG：

- `MACOS_APP_CERTIFICATE_P12_BASE64`
- `MACOS_APP_CERTIFICATE_PASSWORD`
- `MACOS_DEVELOPER_TEAM_ID`
- `MACOS_SIGNING_IDENTITY`（可选；默认 `Developer ID Application`）

未配置时仍会产出未签名 DMG，并可由应用内更新器安装。此流程不包含 Apple Notary 凭据；公证需要在后续单独接入。

## 发布后验证

1. 确认 GitHub Release tag、目标 commit、标题、资产和 SHA-256 全部正确。
2. 验证唯一 DMG、SHA-256 和 Release 资产均正确。
3. 在干净环境验证首次引导及 OSS 运行资源下载、完整性校验和失败重试。
4. 对已有用户，确认 App 更新不会移动 Games、Steam 或 CrossOver 容器，Runtime 更新不会覆盖用户 Prefix。
