import AVFoundation
import AppKit
import SwiftUI

struct MicrophonePermissionView: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var isRequesting = false
    @State private var requestMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    private var statusText: String {
        switch status {
        case .authorized: "已允许"
        case .notDetermined: "未申请"
        case .denied: "已拒绝"
        case .restricted: "被系统策略限制"
        @unknown default: "未知状态"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("麦克风").font(.headline)
            Text(statusText).foregroundStyle(.secondary)
            Text("需要游戏语音时再授权；启动游戏或预热 Wine 不会由 Arclume 主动申请权限。")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                if status == .notDetermined {
                    Button("允许使用麦克风…") {
                        isRequesting = true
                        Task { @MainActor in
                            let granted = await MicrophoneAuthorization.shared.requestFromUserAction()
                            status = AVCaptureDevice.authorizationStatus(for: .audio)
                            requestMessage = granted ? "已授权" : "未获得授权；可在系统设置中检查。"
                            isRequesting = false
                        }
                    }.disabled(isRequesting)
                }
                Button("打开系统麦克风设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if let requestMessage { Text(requestMessage).font(.caption) }
        }
        .onAppear { status = AVCaptureDevice.authorizationStatus(for: .audio) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { status = AVCaptureDevice.authorizationStatus(for: .audio) }
        }
    }
}
