# 补齐 Windows 游戏麦克风授权声明

- 时间：2026-09-02T10:00:00+08:00
- 类型：fix
- 范围：App

## 改动

- 在 Arclume 主 App 的 `Info.plist` 中加入 `NSMicrophoneUsageDescription`，说明访问用于 Windows 游戏及语音聊天。
- 为 Debug 与 Release 启用 Xcode 的音频输入资源访问设置。

## 用户影响与兼容性

- 首次由内置 Wine 中的游戏访问麦克风时，macOS 现在可以显示 Arclume 的麦克风授权提示。
- 不重置既有 macOS 隐私授权，不修改 Games、Bottle、Wine Runtime 或游戏文件。

## 验证

- 已签名 Debug `xcodebuild build` 通过；安装后的 App 为 `1.0.2 (7)`。
- 已确认安装包含 `NSMicrophoneUsageDescription` 与 `com.apple.security.device.audio-input`，并通过深度签名校验。
- `git diff --check` 通过；未重置用户的 macOS 麦克风授权。

## 后续

- 无。
