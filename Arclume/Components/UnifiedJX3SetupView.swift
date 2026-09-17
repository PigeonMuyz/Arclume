import SwiftUI

/// Optional setup in the shared container; never re-enables the retired JX3 mode.
struct UnifiedJX3SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appGlobals: AppGlobals
    @State private var ready = false
    @State private var busy = false
    @State private var installed = false
    @State private var showInstaller = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("配置剑网3启动器", systemImage: "gamecontroller")
                .font(.title2.weight(.semibold))
            Text(installed ? "已找到剑网3启动器，可以直接在游戏库中打开。" : "使用官网下载的 Windows 安装包，将启动器安装到 ALBottles。")
                .foregroundStyle(.secondary)
            if busy { ProgressView("正在准备运行环境…") }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("稍后配置") { dismiss() }.buttonStyle(.glass).disabled(busy)
                Spacer()
                if installed {
                    Button("完成") { dismiss() }.buttonStyle(.glassProminent)
                } else if ready {
                    Button("选择安装包…") { showInstaller = true }.buttonStyle(.glassProminent)
                } else {
                    Button("准备运行环境") { prepare() }.buttonStyle(.glassProminent).disabled(busy)
                }
            }
        }
        .padding(32).frame(width: 530)
        .interactiveDismissDisabled(busy)
        .task { await detect() }
        .sheet(isPresented: $showInstaller, onDismiss: { Task { await detect() } }) {
            WindowsInstallerView(title: "配置剑网3启动器")
        }
    }

    private func detect() async {
        guard !ArclumeTestEnvironment.isTesting else { return }
        let state = await Task.detached(priority: .utility) {
            let prefix = BundledWineRuntime.prefixURL
            return (BundledWineRuntime.isValidPrefix(at: prefix),
                    OnlineGameDiscovery.jx3Installation(in: prefix).isDetected)
        }.value
        ready = state.0
        installed = state.1
    }

    private func prepare() {
        guard !busy, !ArclumeTestEnvironment.isTesting else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                let prefix = try await Task.detached(priority: .userInitiated) {
                    try BundledWineRuntime.preparePrefix()
                }.value
                try OnlineGameBottleConfiguration.apply(to: prefix)
                OnlineGameRuntimeKind.activate(.bundledWine, with: prefix, appGlobals: appGlobals)
                await detect()
            } catch { message = error.localizedDescription }
        }
    }
}
