# 2026-08-21 — 隔离 Release 暂存目录

- 为每次 GitHub Actions 发布构建使用按 run ID 与 attempt ID 区分的 DMG 暂存目录。
- 防止可复用 runner 留下的轻量 App 暂存文件阻塞后续正式发布。
