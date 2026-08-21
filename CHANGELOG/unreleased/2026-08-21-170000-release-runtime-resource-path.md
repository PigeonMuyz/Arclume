# 2026-08-21 — 修正 Release Runtime 资源路径

- Release 工作流按 Xcode Archive 中的实际 `Contents/Resources` 平铺路径定位内置 Wine 归档。
- 不再将源码中的 `OnlineGameDependencies` 目录层级误用于 App Bundle。
