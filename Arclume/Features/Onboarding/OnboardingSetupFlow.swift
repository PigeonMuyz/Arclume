import SwiftUI

/// Optional setup stays in the welcome canvas. Wine installers retain their own windows.
struct OnboardingSetupFlow: View {
    let steam: Bool
    let jx3: Bool
    let onFinish: () -> Void
    @EnvironmentObject private var globals: AppGlobals
    @EnvironmentObject private var steamStore: ContainerSteamStore
    @ObservedObject private var resourceStore: DownloadableResourceStore
    private let demonstrationOnly: Bool
    private let isUpgrade: Bool
    @State private var resourcesFinished = false
    @State private var jx3Finished = false
    @State private var showJX3Installer = false
    @State private var preparing = false
    @State private var progress: Double?
    @State private var message: String?
    @State private var error: String?
    @State private var installed = false
    @State private var runtimePrepared = false
    private var resourcePurpose: DownloadableResourceCatalog.Purpose { jx3 ? .jx3 : steam ? .steam : .runtime }
    private var resourcesReady: Bool { resourceStore.status(for: resourcePurpose).isReady }
    private var configuringJX3: Bool { jx3 && !jx3Finished }
    private var busy: Bool { preparing || steamStore.steamSetupBusy || resourceStore.isBusy || resourceStore.isSwitchingRuntime }

    init(steam: Bool, jx3: Bool, resourceStore: DownloadableResourceStore = .shared,
         demonstrationOnly: Bool = false, isUpgrade: Bool = false, onFinish: @escaping () -> Void) {
        self.steam = steam; self.jx3 = jx3; self.resourceStore = resourceStore
        self.demonstrationOnly = demonstrationOnly; self.onFinish = onFinish
        self.isUpgrade = isUpgrade
    }

    var body: some View {
        Group {
            if !resourcesFinished {
                resourcesStage
            } else if configuringJX3 && showJX3Installer {
                WindowsInstallerView(title: "配置剑网3启动器", onboarding: true, onComplete: advance)
            } else {
                OnboardingStage(title: configuringJX3 ? "配置剑网3启动器" : "配置 Steam", showsBrand: true) {
                    VStack(spacing: 18) {
                        Text(installed ? "已安装，可以继续。" : configuringJX3
                             ? "准备运行环境后，选择官网下载的 Windows 安装包。"
                             : "将 Steam 安装到统一运行环境，游戏库会自动扫描。")
                            .foregroundStyle(.secondary)
                        if busy {
                            ProgressView(value: resourceStore.isBusy
                                ? resourceStore.progress
                                : preparing ? progress : steamStore.steamSetupProgress) {
                                Text(resourceStore.isBusy
                                    ? (resourceStore.message ?? "正在下载运行环境及组件…")
                                    : preparing ? (message ?? "正在准备运行环境…")
                                    : (steamStore.steamSetupMessage ?? "正在安装 Steam…"))
                            }
                        }
                        if let error = error ?? resourceStore.error ?? steamStore.steamSetupError {
                            Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                        }
                        if steamStore.steamSetupDownloading {
                            Button("取消下载") { steamStore.cancelSteamDownload() }.buttonStyle(.glass)
                        }
                    }
                } actions: {
                    Button("稍后配置") { advance() }.buttonStyle(.glass).disabled(busy)
                    Spacer()
                    Button(installed && resourcesReady
                        ? "继续"
                        : resourcesReady
                            ? (configuringJX3 ? "准备并选择安装包" : "安装 Steam")
                            : "下载运行环境并继续") {
                        if installed && resourcesReady { advance() } else { prepare() }
                    }.buttonStyle(.glassProminent).disabled(busy).keyboardShortcut(.defaultAction)
                }
            }
        }
        .task(id: configuringJX3) { await detect() }
    }

    private var resourcesStage: some View {
        OnboardingStage(title: isUpgrade ? "升级 Arclume" : "准备运行环境", showsBrand: true) {
            VStack(spacing: 24) {
                RuntimeProviderPicker(store: resourceStore, showsDetails: false)
                    .disabled(busy)
                if busy || runtimePrepared {
                    ProgressView(value: runtimePrepared ? 1 : resourceStore.progress) {
                        Text(runtimePrepared ? "准备完成" : (resourceStore.message ?? "正在准备运行环境…"))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("onboarding-runtime-progress")
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if demonstrationOnly {
                    Label("隔离演示 · 下载和安装均为模拟", systemImage: "eye")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: 440)
        } actions: {
            Button("稍后配置") { onFinish() }.buttonStyle(.glass).disabled(busy)
            Spacer()
            Button(busy ? "正在准备…" : error != nil ? "重试" : resourcesReady
                ? (steam || jx3 ? "继续" : "开始使用") : "开始准备") {
                if resourcesReady {
                    preparing = true
                    Task {
                        defer { preparing = false }
                        do { try await resourceStore.activateSelection(); error = nil }
                        catch { self.error = preparationError(error); return }
                        if steam || jx3 { resourcesFinished = true }
                        else { onFinish() }
                    }
                } else {
                    prepareRuntime()
                }
            }
            .buttonStyle(.glassProminent).disabled(busy).keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("onboarding-resource-action")
        }
        .accessibilityIdentifier("onboarding-resources")
        .onAppear { resourceStore.refresh() }
        .onChange(of: resourceStore.selectedProvider) { _, _ in
            error = nil
            runtimePrepared = false
        }
    }

    private func prepareRuntime() {
        guard !busy else { return }
        preparing = true
        error = nil
        runtimePrepared = false
        Task {
            defer { preparing = false }
            do {
                // The explicit primary action starts automatic checks and preparation.
                try await resourceStore.download(purpose: resourcePurpose)
                runtimePrepared = true
            } catch {
                self.error = preparationError(error)
            }
        }
    }

    private func preparationError(_ error: Error) -> String {
        if let error = error as? NefinitaBuildError, case .missingTools = error {
            return "缺少构建工具，请在运行环境设置中查看。"
        }
        if let error = error as? ResourceDownloadError, case .busyRuntime = error {
            return "请先结束正在运行的 Windows 程序。"
        }
        return "准备未完成，请重试。"
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
        #if DEBUG
        if demonstrationOnly {
            guard !busy else { return }
            preparing = true; error = nil; progress = 0
            Task {
                for (value, label) in [(0.25, "正在初始化 Windows 容器…"), (0.65, "正在配置第三方组件…"), (0.9, configuringJX3 ? "正在配置剑网3启动器…" : "正在安装 Steam…")] {
                    progress = value; message = label
                    try? await Task.sleep(for: .milliseconds(650))
                }
                installed = true; preparing = false; progress = 1
            }
            return
        }
        #endif
        guard !busy, !ArclumeTestEnvironment.isTesting else { return }
        preparing = true; error = nil
        let isJX3 = configuringJX3
        let report: BundledWineRuntime.ProgressHandler = { value, label in
            Task { @MainActor in progress = value; message = label }
        }
        Task {
            defer { preparing = false }
            do {
                try await resourceStore.download(purpose: isJX3 ? .jx3 : .steam)
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
            } catch {
                self.error = resourceStore.error ?? error.localizedDescription
            }
        }
    }
}
