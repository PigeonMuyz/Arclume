# 2026-08-21 — 修复轻量 DMG 构建

- 生成不含 Runtime 的 DMG 时改用同卷 APFS 克隆，避免 GitHub Actions 为完整 App 再分配一份运行时文件。
- 从 Runtime Manifest 读取需要移除的归档文件名，并在打包前校验文件存在。
