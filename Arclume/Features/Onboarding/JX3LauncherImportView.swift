import SwiftUI
import UniformTypeIdentifiers

/// Shared by welcome/upgrade and the optional setup sheet. Import never launches Wine.
struct JX3LauncherImportView: View {
    let prefix: URL
    var onboarding = false
    let onComplete: () -> Void
    @EnvironmentObject private var library: LibraryPageGlobals
    @State private var busy = false
    @State private var imported = false
    @State private var message: String?
    @State private var pendingFolder: URL?
    @State private var showInstaller = false

    var body: some View {
        Group {
            if onboarding {
                OnboardingStage(title: "导入剑网3启动器", showsBrand: true) {
                    content
                } actions: { actions }
            } else {
                Modal("导入剑网3启动器", showModal: Binding(get: { true }, set: { if !$0 { onComplete() } }),
                      scrollable: false, allowsClose: !busy) {
                    VStack(alignment: .leading, spacing: 22) {
                        content
                        HStack { actions }
                    }.frame(width: 520)
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .confirmationDialog("移动启动器文件夹？", isPresented: Binding(
            get: { pendingFolder != nil }, set: { if !$0 { pendingFolder = nil } }
        ), titleVisibility: .visible) {
            Button("移动并导入") {
                if let folder = pendingFolder { pendingFolder = nil; importLauncher(folder) }
            }
            Button("取消", role: .cancel) { pendingFolder = nil }
        } message: {
            Text("所选文件夹及其中的游戏文件会移动到当前容器，不会重复复制。已有启动器和游戏不会被覆盖。")
        }
        .sheet(isPresented: $showInstaller, onDismiss: { Task { await detect() } }) {
            WindowsInstallerView(title: "运行剑网3安装程序")
        }
        .task { await detect() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if imported {
                Label("剑网3启动器已添加", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("选择 SeasunGame 文件夹、SeasunGame.exe 或 ZIP。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("导入启动器…") { chooseLauncher() }.buttonStyle(.glassProminent)
                    Button("从下载文件夹选择…") { chooseLauncher(inDownloads: true) }.buttonStyle(.glass)
                }
                HStack {
                    Button("打开容器目录") {
                        NSWorkspace.shared.open(prefix.appendingPathComponent("drive_c"))
                    }
                    Button("检查手动导入") { Task { await detect(showMissing: true) } }
                    Button("运行安装程序…") { showInstaller = true }
                }.buttonStyle(.glass)
            }
            if busy { ProgressView("正在导入启动器…") }
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.disabled(busy)
    }

    @ViewBuilder private var actions: some View {
        Button(imported ? "关闭" : "稍后配置") { onComplete() }.buttonStyle(.glass).disabled(busy)
        Spacer()
        if imported {
            Button("继续") { onComplete() }.buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func chooseLauncher(inDownloads: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = "选择 SeasunGame 文件夹、SeasunGame.exe 或 ZIP"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .zip, UTType(filenameExtension: "exe") ?? .item]
        if inDownloads { panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first }
        panel.begin { response in
            guard response == .OK, let source = panel.url else { return }
            if (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               !source.standardizedFileURL.path.hasPrefix(prefix.standardizedFileURL.path + "/") {
                pendingFolder = source
            } else { importLauncher(source) }
        }
    }

    private func importLauncher(_ source: URL) {
        guard !busy, !ArclumeTestEnvironment.isTesting else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try OnlineLauncherImporter.installPreservingExisting(from: source, into: prefix)
                }.value
                await detect(showMissing: true)
            } catch { message = error.localizedDescription }
        }
    }

    private func detect(showMissing: Bool = false) async {
        guard !ArclumeTestEnvironment.isTesting else { return }
        let installation = await Task.detached(priority: .utility) {
            OnlineGameDiscovery.jx3Installation(in: prefix)
        }.value
        guard let launcher = OnlineGameDiscovery.games(from: installation).first else {
            if showMissing { message = "未找到 SeasunGame.exe，请确认启动器已放入容器。" }
            return
        }
        library.registerStandardJX3(launcher, bottle: prefix,
            runtimeKind: StandardGameRuntimeKind.bundledWine.rawValue, crossOverPath: nil)
        OnlineGameInitialConfiguration.startPolling(for: prefix, installation: installation)
        imported = true; message = nil
    }
}
