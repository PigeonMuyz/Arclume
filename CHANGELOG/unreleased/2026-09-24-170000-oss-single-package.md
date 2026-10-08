# 2026-09-24 — OSS 运行资源单包分发

- Release 只生成 `Arclume-<version>.dmg` 与 SHA-256；运行归档和 Arclume/Libs 下的 Wine、D3D 组件不进入 App Bundle。
- GitHub Actions 要求配置 `ARCLUME_RESOURCE_BASE_URL` Secret，并只通过 Xcode 构建设置注入；源码不保存服务地址。
- 保留 Runtime Manifest、JSON、INI 和第三方声明；保持现有独立 OTF 字体排除规则。预检保留 Manifest 结构校验，不要求离线工作区已有 Wine 归档内容，并在 Debug build 后检查 App Bundle。
- 验证：`bash -n script/pr_preflight.sh`、发布 workflow YAML 解析、`plutil -lint` 与 `git diff --check`；未执行 Xcode 构建或实际 Release。
- 未验证：macOS 构建后的 Bundle 内容、GitHub Secret 注入与 OSS 下载实测；需在集成后由 CI/设备验收。
