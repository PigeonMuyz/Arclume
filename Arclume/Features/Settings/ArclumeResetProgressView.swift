import AppKit
import SwiftUI

struct ArclumeResetProgressView: View {
    @ObservedObject var coordinator: ArclumeResetCoordinator

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: coordinator.phase == .completed ? "checkmark.circle" : "arrow.counterclockwise")
                .font(.system(size: 48)).foregroundStyle(Color.accentColor)
            Text(coordinator.phase.title).font(.title2.weight(.semibold))
            if coordinator.isRunning {
                ProgressView().controlSize(.large)
                Text("请勿关闭 Arclume 或重新启动 Windows 程序。")
                    .foregroundStyle(.secondary)
            } else {
                if let error = coordinator.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
                if coordinator.trashURL != nil {
                    Text("应用数据已移入废纸篓，仍会占用磁盘空间。需要恢复时请先从废纸篓取回；确认不再需要后，可自行清空废纸篓。清空后无法通过 Arclume 恢复。")
                    Button("在废纸篓中查看") {
                        if let url = coordinator.trashURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }.buttonStyle(.glass)
                } else if coordinator.phase == .completed {
                    Text("设置已清除，没有需要移入废纸篓的应用数据。")
                }
                if coordinator.phase == .failed {
                    Text("本次不再加载游戏库。可以重试，或退出后继续处理。")
                        .foregroundStyle(.secondary)
                } else {
                    Text("下次打开 Arclume 时将重新进入初始化引导。")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    if coordinator.phase == .failed {
                        Button("重试") { coordinator.start() }.buttonStyle(.glass)
                    }
                    Button(coordinator.phase == .completed ? "知道了，退出" : "退出") {
                        if coordinator.acknowledgeExit() { NSApp.terminate(nil) }
                    }.buttonStyle(.glassProminent)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 560).padding(48)
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .accessibilityIdentifier("reset-progress")
    }
}
