# 允许未签名 Release 自动更新

- 时间：2026-09-01T10:45:00+08:00
- 类型：fix
- 范围：App、CI、文档

## 改动

- 应用内更新不再要求当前 App 与更新 App 具有同一 Developer ID 签名。
- 保留 DMG SHA-256、Bundle ID、营销版本与构建号校验，以及暂存替换和失败回滚。
- 未配置 Developer ID 证书的 GitHub Actions DMG 现在也可作为自动更新来源。

## 用户影响与兼容性

- 更新流程仍会在替换前校验 GitHub Release 提供的 DMG 完整性和目标 App 身份；不会触及 Games、Steam、CrossOver 容器或 Wine Runtime。
- Developer ID 签名和公证仍可用于 macOS 分发信任，但不再阻止应用内更新。

## 验证

- 无签名 Debug `xcodebuild build` 通过；已确认生成 `Arclume.app`。
- `git diff --check` 通过；`release-macos.yml` 已通过 YAML 解析。

## 后续

- 无。
