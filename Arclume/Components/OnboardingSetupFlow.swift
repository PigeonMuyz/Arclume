import SwiftUI

/// Optional setup stays in the welcome canvas. Wine installers retain their own windows.
struct OnboardingSetupFlow: View {
    let steam: Bool
    let jx3: Bool
    let onFinish: () -> Void
    @EnvironmentObject private var globals: AppGlobals
    @EnvironmentObject private var steamStore: ContainerSteamStore
    @State private var jx3Finished = false
    @State private var showJX3Installer = false
    @State private var preparing = false
    @State private var progress: Double?
    @State private var message: String?
    @State private var error: String?
    @State private var installed = false
    private var configuringJX3: Bool { jx3 && !jx3Finished }
    private var busy: Bool { preparing || steamStore.steamSetupBusy }

    var body: some View {
        Group {
            if configuringJX3 && showJX3Installer {
                WindowsInstallerView(title: "配置剑网3启动器", onboarding: true, onComplete: advance)
            } else {
                OnboardingStage(title: configuringJX3 ? "配置剑网3启动器" : "配置 Steam", showsBrand: true) {
                    VStack(spacing: 18) {
                        Text(installed ? "已安装，可以继续。" : configuringJX3
                             ? "准备运行环境后，选择官网下载的 Windows 安装包。"
                             : "将 Steam 安装到统一运行环境，游戏库会自动扫描。")
                            .foregroundStyle(.secondary)
                        if busy {
                            ProgressView(value: preparing ? progress : steamStore.steamSetupProgress) {
                                Text(preparing ? (message ?? "正在准备运行环境…") : (steamStore.steamSetupMessage ?? "正在安装 Steam…"))
                            }
                        }
                        if let error = error ?? steamStore.steamSetupError {
                            Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                        }
                        if steamStore.steamSetupDownloading {
                            Button("取消下载") { steamStore.cancelSteamDownload() }.buttonStyle(.glass)
                        }
                    }
                } actions: {
                    Button("稍后配置") { advance() }.buttonStyle(.glass).disabled(busy)
                    Spacer()
                    Button(installed ? "继续" : configuringJX3 ? "准备并选择安装包" : "安装 Steam") {
                        if installed { advance() } else { prepare() }
                    }.buttonStyle(.glassProminent).disabled(busy).keyboardShortcut(.defaultAction)
                }
            }
        }
        .task(id: configuringJX3) { await detect() }
    }

    private func advance() {
        if configuringJX3, steam {
            jx3Finished = true; installed = false; error = nil; message = nil
        } else { onFinish() }
    }

    private func detect() async {
        guard !ArclumeTestEnvironment.isTesting else { return }
        let jx3 = configuringJX3
        installed = await Task.detached(priority: .utility) {
            let prefix = BundledWineRuntime.standardSteamPrefixURL
            if jx3 { return OnlineGameDiscovery.jx3Installation(in: prefix).isDetected }
            return ContainerSteamService().detect(in: prefix).installation != nil
        }.value
    }

    private func prepare() {
        guard !busy, !ArclumeTestEnvironment.isTesting else { return }
        preparing = true; error = nil
        let isJX3 = configuringJX3
        let report: BundledWineRuntime.ProgressHandler = { value, label in
            Task { @MainActor in progress = value; message = label }
        }
        Task {
            defer { preparing = false }
            do {
                let prefix = try await Task.detached(priority: .userInitiated) {
                    try BundledWineRuntime.prepareStandardSteamPrefix(progress: report)
                }.value
                if isJX3 { try OnlineGameBottleConfiguration.apply(to: prefix) }
                StandardGameRuntimeKind.activate(.bundledWine, with: prefix, appGlobals: globals)
                if isJX3 { showJX3Installer = true }
                else {
                    steamStore.installSteamClient(in: prefix, using: .bundledWine) { bottle in
                        steamStore.refreshClientDetection(bottleURL: bottle)
                        globals.windowsSteamFolder = steamStore.installation?.steamRootURL
                        installed = true
                    }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}
