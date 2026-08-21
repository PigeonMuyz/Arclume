# Fankit 式 App 更新与普通模式 Arclume Wine

- 时间：2026-08-21T11:00:00+08:00
- 类型：feature、安全、发布
- 范围：应用更新、普通 Windows 游戏运行时、GitHub Release
- 发布版本：Arclume 1.0.2 (4)
- PR / 提交：待提交

## 改动

- 应用更新从“下载 DMG 到下载目录”改为 Fankit 式流程：下载 SHA-256 校验、只读挂载、校验 Bundle ID、版本、构建号和同一开发团队签名、原子替换、必要时请求一次管理员权限，并自动重启。
- 普通模式新增独立的 `CrossOver` / `Arclume Wine` 运行时选择；内置 Wine 使用独立 Steam 容器，可安装 `SteamSetup.exe`、打开 Steam、安装及启动 Windows Steam 游戏，不再要求 CrossOver。
- CrossOver Bottle、剑网 3 Games 容器与 Arclume Wine Steam 容器彼此隔离；切换普通运行时不会移动、复制或删除既有容器。
- Release workflow 可选导入 Developer ID 证书签名 App/DMG；未配置签名凭据时保留手动安装产物，但应用内自动更新会拒绝未验证来源。

## 用户影响与兼容性

- 首次选择普通模式的 Arclume Wine 时需要准备独立 Steam 容器；已有 CrossOver Steam Bottle 保持不变。
- 要启用自动覆盖安装，维护者需要配置发布签名 Secrets；未签名历史 Release 仍可手动下载安装。

## 验证

- `xcodebuild -project Arclume.xcodeproj -scheme Arclume -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= SWIFT_EMIT_LOC_STRINGS=NO build`：通过。
- 未运行 XCTest（按当前项目约定）。
