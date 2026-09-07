//
//  MicrophoneAuthorization.swift
//  Arclume
//

import AVFoundation
import Foundation

/// Owns the macOS privacy prompt for an application launched through the
/// bundled Wine runtime. Wine's CoreAudio driver only preflights TCC; asking
/// from Arclume itself ensures the user receives the normal macOS prompt.
enum MicrophoneAuthorization {
    @MainActor
    static func requestForBundledWineLaunchIfNeeded() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            console.log("麦克风权限已授权给 Arclume")
        case .notDetermined:
            console.log("正在请求 Arclume 麦克风权限")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            console.log(granted ? "Arclume 麦克风权限已授权" : "用户未授权 Arclume 麦克风权限")
        case .denied:
            console.warn("Arclume 的麦克风权限已被拒绝；内置 Wine 游戏仍可启动，但语音输入不可用")
        case .restricted:
            console.warn("当前 macOS 策略限制了 Arclume 的麦克风权限")
        @unknown default:
            console.warn("无法识别 Arclume 的麦克风权限状态")
        }
    }
}
