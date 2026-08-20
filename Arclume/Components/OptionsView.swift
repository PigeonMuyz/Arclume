//
//  OptionsView.swift
//  Procyon
//

import SwiftUI
import UniformTypeIdentifiers

struct OptionsView: View {
    @State private var bottles: [URL] = []
    @State private var progress: Double = 0
    @State private var progressLabel = L10n.string("Processing...")
    @State private var downloading = false
    @State private var creatingBottle = false
    @State private var newBottleName = ""
    @State private var createBottleProcess: Process?
    @State private var launcherImportMessage: String?
    @State private var dependencyImportMessage: String?
    @State private var dependencyInstallMode: DependencyInstallMode = .automatic
    @State private var pendingCrossOverURL: URL?
    @State private var showDependencyModeDialog = false
    @State private var showNativeGameImport = false
    @State private var showModeSelection = false
    @State private var patchErrorMessage: String?

    @AppStorage(ArclumeUpdatePreferences.automaticallyCheck, store: UserDefaults(suiteName: suiteName))
    private var automaticallyCheckUpdates = true
    @AppStorage(ArclumeUpdatePreferences.checkAtEveryLaunch, store: UserDefaults(suiteName: suiteName))
    private var checkUpdatesAtEveryLaunch = false
    @AppStorage(ArclumeUpdatePreferences.mirrorMode, store: UserDefaults(suiteName: suiteName))
    private var updateMirrorMode = ArclumeUpdateMirrorMode.automatic.rawValue
    @AppStorage(ArclumeUpdatePreferences.customMirrorPrefix, store: UserDefaults(suiteName: suiteName))
    private var customUpdateMirrorPrefix = ""

    @AppStorage("steamMetadataSource", store: UserDefaults(suiteName: suiteName))
    private var steamMetadataSource = SteamMetadataSource.steamStore.rawValue
    @AppStorage("appleAppStoreMetadataEnabled", store: UserDefaults(suiteName: suiteName))
    private var appleAppStoreMetadataEnabled = true

    @EnvironmentObject private var appGlobals: AppGlobals
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject private var containerSteamStore: ContainerSteamStore
    @EnvironmentObject private var modeStore: ArclumeModeStore
    @EnvironmentObject private var updateService: ArclumeUpdateService
    @MainActor var load: @Sendable () async -> Void

    private var isOnlineMode: Bool {
        modeStore.selectedMode?.isOnlineGameMode == true
    }

    var body: some View {
        Modal(
            L10n.string("Options"),
            showModal: $libraryPageGlobals.showOptions,
            scrollable: !isOnlineMode
        ) {
            if isOnlineMode {
                onlineSettingsContent
            } else {
                standardSettingsContent
            }
        }
        .onAppear {
            if isOnlineMode {
                OnlineGameRuntimeKind.migrateLegacyCrossOverConfigurationIfNeeded(
                    appGlobals: appGlobals
                )
                OnlineGameRuntimeKind.restoreActiveBottleIfAvailable(
                    appGlobals: appGlobals
                )
            }
            restoreCrossOverSelection()
        }
        .sheet(isPresented: $showNativeGameImport) {
            NativeGameImportView(isPresented: $showNativeGameImport)
                .environmentObject(libraryPageGlobals)
        }
        .sheet(isPresented: $showModeSelection) {
            ModeSelectionView(allowsCancel: true) { mode in
                modeStore.select(mode)
                showModeSelection = false
                libraryPageGlobals.showOptions = false
            }
            .frame(width: 860, height: 560)
        }
        .confirmationDialog(
            "准备 CrossOver 依赖",
            isPresented: $showDependencyModeDialog,
            titleVisibility: .visible
        ) {
            Button("自动下载（推荐）") {
                prepareCrossOver(dependencyMode: .automatic)
            }
            Button("手动导入压缩包") {
                prepareCrossOver(dependencyMode: .manual)
            }
            Button("取消", role: .cancel) {
                pendingCrossOverURL = nil
            }
        } message: {
            Text("GStreamer 和 DXMT 可自动从网络获取；网络不稳定时，可分别选择本地压缩包导入。")
        }
    }

    private var onlineSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeSelectionCard
            updateCard
            appearanceCard
            aboutCard
        }
        .frame(width: 390)
        .padding(.top, 16)
        .padding(.bottom, 2)
    }

    private var standardSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeSelectionCard
            updateCard
            settingsCard { crossOverSection }
            settingsCard { steamBottleSection }
            settingsCard { GameLibrariesList(load: load) }
            if !appGlobals.selectedBottle.isEmpty {
                settingsCard { steamPathSection }
            }
            settingsCard { nativeGamesSection }
            settingsCard { metadataSection }
            settingsCard { dependencySection }
            appearanceCard
            aboutCard
        }
        .frame(width: 390)
        .padding(.top, 16)
        .padding(.bottom, 2)
    }

    private var modeSelectionCard: some View {
        settingsCard {
            Text("运行模式")
                .font(.headline)

            Button {
                showModeSelection = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: modeStore.selectedMode?.systemImage ?? "gamecontroller.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                    Text(modeStore.selectedMode?.title ?? "剑网3模式")
                        .font(.body.weight(.semibold))

                    Spacer(minLength: 8)

                    Text("切换")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var appearanceCard: some View {
        settingsCard {
            Text("外观")
                .font(.headline)

            HStack(spacing: 12) {
                Label("语言", systemImage: "character.bubble")
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 8)
                Picker("语言", selection: $appSettings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var updateCard: some View {
        settingsCard {
            HStack(spacing: 12) {
                Text("更新")
                    .font(.headline)
                Spacer()
                Button(updateService.isChecking ? "检查中…" : "检查更新") {
                    Task { await updateService.checkForUpdates() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(updateService.isChecking)
            }

            updateItem(
                title: "Arclume",
                systemImage: "app.badge",
                status: applicationUpdateStatus
            ) {
                if updateService.isApplicationUpdateAvailable {
                    Button(updateService.isDownloadingApplication ? "下载中…" : "下载 DMG") {
                        Task { await updateService.downloadApplicationUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(updateService.isDownloadingApplication)
                }
            }

            if let message = updateService.applicationDownloadMessage {
                updateMessage(message, color: .green)
            }
            if let message = updateService.applicationError {
                updateMessage(message, color: .red)
            }

            Divider()
                .overlay(.white.opacity(0.12))

            updateItem(
                title: "Arclume Wine",
                systemImage: "wineglass",
                status: runtimeUpdateStatus
            ) {
                if updateService.isRuntimeUpdateAvailable {
                    Button(updateService.isUpdatingRuntime ? "更新中…" : "更新 Runtime") {
                        Task { await updateService.updateRuntime() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        updateService.isUpdatingRuntime
                            || libraryPageGlobals.jx3RuntimeActivity.state != .idle
                    )
                }
            }

            if let progress = updateService.runtimeProgress,
               let label = updateService.runtimeProgressLabel
            {
                ProgressView(value: progress) {
                    Text(label)
                }
                .controlSize(.small)
                .font(.footnote)
            }
            if let message = updateService.runtimeError {
                updateMessage(message, color: .red)
            }

            Divider()
                .overlay(.white.opacity(0.12))

            Toggle("自动检查更新", isOn: $automaticallyCheckUpdates)
            Toggle("每次启动检查", isOn: $checkUpdatesAtEveryLaunch)
                .disabled(!automaticallyCheckUpdates)

            HStack(spacing: 12) {
                Label("下载源", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 8)
                Picker("下载源", selection: $updateMirrorMode) {
                    ForEach(ArclumeUpdateMirrorMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if updateMirrorMode == ArclumeUpdateMirrorMode.customMirror.rawValue {
                TextField("https://mirror.example/", text: $customUpdateMirrorPrefix)
                    .textFieldStyle(.roundedBorder)
                if !customUpdateMirrorPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   ArclumeUpdateSource.normalizedPrefix(customUpdateMirrorPrefix) == nil
                {
                    updateMessage("自定义下载源需使用 HTTPS URL 前缀。", color: .orange)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.78))
    }

    private func updateItem<Action: View>(
        title: String,
        systemImage: String,
        status: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 6)
            Text(status)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .truncationMode(.middle)
            action()
        }
    }

    private func updateMessage(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var applicationUpdateStatus: String {
        guard let release = updateService.latestApplicationRelease else {
            return updateService.isChecking ? "正在检查" : "尚未检查"
        }
        return updateService.isApplicationUpdateAvailable
            ? "\(release.version) 可用"
            : "已是最新"
    }

    private var runtimeUpdateStatus: String {
        guard let release = updateService.latestRuntimeRelease else {
            return updateService.isChecking ? "正在检查" : "尚未检查"
        }
        return updateService.isRuntimeUpdateAvailable
            ? "\(release.manifest.version) 可用"
            : "已是最新"
    }

    private var aboutCard: some View {
        settingsCard {
            Text("关于")
                .font(.headline)

            HStack(spacing: 12) {
                Label("Arclume", systemImage: "app.badge")
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 8)
                Text(applicationVersion)
                    .monospacedDigit()
            }

            Divider()
                .overlay(.white.opacity(0.12))

            HStack(spacing: 12) {
                Label("内置 Wine", systemImage: "wineglass")
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 8)
                Text(BundledWineRuntime.runtimeVersion)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()
                .overlay(.white.opacity(0.12))

            HStack(spacing: 12) {
                Label("诊断日志", systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 8)
                Text(ArclumeGameLogStore.storageUsageText)
                    .monospacedDigit()
                Button("打开") {
                    showFolder(url: ArclumeGameLogStore.directoryForUser())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.bottom, 8)
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.58))
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.09), lineWidth: 1)
            }
    }

    private var applicationVersion: String {
        let info = Bundle.main.infoDictionary
        let marketingVersion = info?["CFBundleShortVersionString"] as? String ?? "未知版本"
        guard let buildVersion = info?["CFBundleVersion"] as? String,
              buildVersion != marketingVersion
        else {
            return marketingVersion
        }
        return "\(marketingVersion) (\(buildVersion))"
    }

    private var crossOverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CrossOver")
                .font(.headline)
            Button(
                URL(string: appGlobals.cxAppPath ?? "")?.lastPathComponent
                    ?? L10n.string("Select a CrossOver App...")
            ) {
                chooseCrossOver()
            }
            if downloading {
                ProgressView(value: progress, total: 100) {
                    Text(progressLabel).font(.footnote)
                }
            }
            if let patchErrorMessage {
                Text(patchErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Text(
                isOnlineMode
                    ? "剑网3模式不会读取 Steam，只使用下方选择的 CrossOver Bottle 扫描 SeasunGame。"
                    : "普通模式会使用下方选择的 CrossOver Bottle 扫描 Steam 游戏，也支持添加自定义游戏。"
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var steamBottleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steam Bottle")
                .font(.headline)

            if appGlobals.cxAppPath == nil {
                Text("请先选择 CrossOver。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if bottles.isEmpty {
                Text("没有找到可用 Bottle。你可以新建一个，或在 CrossOver 中创建后重新打开此页面。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("选择 Steam Bottle", selection: $appGlobals.selectedBottle) {
                    Text("不选择 Bottle").tag("")
                    ForEach(bottles, id: \.absoluteString) { bottle in
                        let components = bottle.pathComponents
                        let label = Array(components.suffix(2)).joined(separator: "/")
                        Text(label).tag(bottle.absoluteString)
                    }
                }
                .onChange(of: appGlobals.selectedBottle) { _, value in
                    selectStandardBottle(value)
                }
            }

            HStack {
                TextField("新 Bottle 名称", text: $newBottleName)
                Button("新建") { createSelectedBottle() }
                    .disabled(
                        creatingBottle
                            || appGlobals.cxAppPath == nil
                            || newBottleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
            if creatingBottle {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var steamPathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appGlobals.selectedBottle.isEmpty {
                ProminentButton(
                    L10n.string("Set Steam path"),
                    image: "steam-fill"
                ) {
                    guard
                        let bottlePath = OnlineGameDiscovery.selectedBottleURL(
                            from: appGlobals.selectedBottle
                        ),
                        let url = openFolderSelectorPanel(
                            type: .directory,
                            initialDirectory: bottlePath.appendingPathComponent("drive_c"),
                            title: L10n.string(
                                "Select your Steam folder (where steam.exe is located)"
                            )
                        )
                    else {
                        return
                    }

                    containerSteamStore.setSteamOverride(url, for: bottlePath)
                    syncStandardSteamState(loadAfterSync: true)
                }
                Text(
                    containerSteamStore.installation?.steamExecutableURL.path
                        ?? L10n.string("Steam not detected")
                )
                .font(.footnote)
                .foregroundStyle(
                    containerSteamStore.isReady ? Color.secondary : Color.orange
                )
            }
        }
    }

    private var nativeGamesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Native Games"))
                .font(.headline)
            ProminentButton(
                L10n.string("Scan Native Games"),
                systemImage: "gamecontroller"
            ) {
                showNativeGameImport = true
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Game metadata"))
                .font(.headline)
            Picker(L10n.string("Game metadata"), selection: $steamMetadataSource) {
                ForEach(SteamMetadataSource.allCases) { source in
                    Text(source.title).tag(source.rawValue)
                }
            }

            Toggle(
                L10n.string("Use Apple App Store metadata for native apps"),
                isOn: $appleAppStoreMetadataEnabled
            )
            .onChange(of: appleAppStoreMetadataEnabled) { _, _ in
                Task { await load() }
            }

            Text(L10n.string(
                "Native apps use their bundle identifier to look up App Store descriptions, developers, and genres in the selected language."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)

            if steamMetadataSource == SteamMetadataSource.localProxy.rawValue {
                Text(L10n.string("Start local_steam_proxy.py from the project folder before reloading the library."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if steamMetadataSource == SteamMetadataSource.localOnly.rawValue {
                Text(L10n.string("Games use local Steam manifests and do not request online metadata."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if steamMetadataSource == SteamMetadataSource.steamStore.rawValue {
                Text(L10n.string("Game details are fetched directly from the public Steam Store API. No Steam password or session token is used."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: steamMetadataSource) { _, _ in
            Task { await load() }
        }
    }

    private var bottleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bottle")
                .font(.headline)
            if appGlobals.cxAppPath == nil {
                Text("请先选择 CrossOver。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if bottles.isEmpty {
                Text("没有找到可用 Bottle。你可以新建一个，或在 CrossOver 中创建后重新打开此页面。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("用于扫描剑网3的 Bottle", selection: $appGlobals.selectedBottle) {
                    Text("请选择 Bottle").tag("")
                    ForEach(bottles, id: \.absoluteString) { bottle in
                        Text(bottle.lastPathComponent).tag(bottle.absoluteString)
                    }
                }
                .onChange(of: appGlobals.selectedBottle) { _, value in
                    persistUsrDefOptionString(key: "selectedBottle", value: value)
                    if let bottleURL = OnlineGameDiscovery.selectedBottleURL(from: value) {
                        try? OnlineGameBottleConfiguration.apply(to: bottleURL)
                    }
                    Task { await load() }
                }
            }

            HStack {
                TextField("新 Bottle 名称", text: $newBottleName)
                Button("新建") { createSelectedBottle() }
                    .disabled(
                        creatingBottle
                            || appGlobals.cxAppPath == nil
                            || newBottleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
            if creatingBottle {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var launcherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("剑网 3 启动器")
                .font(.headline)
            HStack {
                Button("导入启动器（EXE、文件夹或 ZIP）") { importLauncher() }
                Button("重新扫描") { Task { await load() } }
            }
            Text("导入即表示安装完成。选择文件夹时会直接移动到当前 Bottle，避免复制完整游戏；单个 EXE 或 ZIP 会先暂存导入。导入后只添加“剑网 3 启动器”卡片，不会立即运行。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let launcherImportMessage {
                Text(launcherImportMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dependencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("补丁依赖")
                .font(.headline)
            Picker("依赖来源", selection: $dependencyInstallMode) {
                ForEach(DependencyInstallMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Text(dependencyInstallMode == .automatic
                ? "选择 CrossOver 时自动下载 GStreamer 和 DXMT。"
                : "选择 CrossOver 时使用下面导入的本地压缩包，不会再发起网络下载。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("导入 GStreamer 压缩包") { importDependency(.gstreamer) }
                Button("导入 DXMT 压缩包") { importDependency(.dxmt) }
            }
            Text("在 GitHub 或镜像下载不通时，可手动下载 Release 压缩包并在这里导入。导入的文件会先检查压缩包路径并保存到本地缓存。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let dependencyImportMessage {
                Text(dependencyImportMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseCrossOver() {
        guard let sourceURL = openFolderSelectorPanel(type: .application) else { return }
        guard OnlineGameRuntimeKind.isValidCrossOverApplication(at: sourceURL) else {
            patchErrorMessage = "请选择可用的 CrossOver.app。"
            return
        }
        pendingCrossOverURL = sourceURL
        showDependencyModeDialog = true
    }

    private func prepareCrossOver(dependencyMode: DependencyInstallMode) {
        guard let sourceURL = pendingCrossOverURL else { return }
        pendingCrossOverURL = nil
        dependencyInstallMode = dependencyMode

        if dependencyMode == .manual {
            guard importDependency(.gstreamer), importDependency(.dxmt) else {
                patchErrorMessage = "未完成手动依赖导入，已取消准备 CrossOver。"
                return
            }
        }

        appGlobals.selectedBottle = ""
        patchErrorMessage = nil
        Task { @MainActor in
            do {
                let patchedAppURL = try await makeCrossoverPatchedCopy(
                    sourceCXPath: sourceURL,
                    dependencyMode: dependencyMode,
                    setProgress: { value, label in
                        progress = value
                        progressLabel = label
                    },
                    setLoading: { downloading = $0 }
                )
                appGlobals.cxAppPath = patchedAppURL.path
                persistUsrDefOptionString(key: "cxAppPath", value: patchedAppURL.path)
                persistUsrDefOptionString(key: "cxCompleteAppPath", value: patchedAppURL.path)
                if DEBUG_ENABLED {
                    console.saveLogs()
                }
                refreshBottles(at: patchedAppURL)
            } catch {
                patchErrorMessage = error.localizedDescription
                progressLabel = "准备 CrossOver 失败"
            }
        }
    }

    private func restoreCrossOverSelection() {
        guard let storedPath = readUsrDefOptionString(key: "cxCompleteAppPath") else {
            return
        }
        let url = URL(fileURLWithPath: storedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            appGlobals.cxAppPath = nil
            return
        }
        appGlobals.cxAppPath = url.path
        refreshBottles(at: url)
        if !isOnlineMode {
            syncStandardSteamState(loadAfterSync: false)
        }
    }

    private func refreshBottles(at appURL: URL) {
        do {
            bottles = try getAllBottles(appDir: appURL)
            let selected = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle)
            let preservesBundledWinePrefix = isOnlineMode
                && OnlineGameRuntimeKind.selected() == .bundledWine
            if !preservesBundledWinePrefix,
               (selected == nil || !bottles.contains(where: {
                   $0.standardizedFileURL == selected?.standardizedFileURL
               })) {
                appGlobals.selectedBottle = ""
            }
            if !isOnlineMode, !appGlobals.selectedBottle.isEmpty {
                syncStandardSteamState(loadAfterSync: false)
            }
        } catch {
            bottles = []
            console.error("Unable to load CrossOver bottles: \(String(reflecting: error))")
        }
    }

    private func selectStandardBottle(_ value: String) {
        guard !isOnlineMode else { return }
        guard let bottleURL = OnlineGameDiscovery.selectedBottleURL(from: value) else {
            containerSteamStore.refresh(bottleURL: nil)
            appGlobals.windowsSteamFolder = nil
            appGlobals.refreshSteamIdentity(containerInstallation: nil)
            libraryPageGlobals.folders.removeAll()
            persistUsrDefOptionString(key: "selectedBottle", value: "")
            Task { await load() }
            return
        }

        persistUsrDefOptionString(key: "selectedBottle", value: value)
        syncStandardSteamState(for: bottleURL, loadAfterSync: true)
    }

    private func syncStandardSteamState(loadAfterSync: Bool) {
        guard let bottleURL = OnlineGameDiscovery.selectedBottleURL(
            from: appGlobals.selectedBottle
        ) else {
            containerSteamStore.refresh(bottleURL: nil)
            appGlobals.windowsSteamFolder = nil
            appGlobals.refreshSteamIdentity(containerInstallation: nil)
            libraryPageGlobals.folders.removeAll()
            if loadAfterSync {
                Task { await load() }
            }
            return
        }
        syncStandardSteamState(for: bottleURL, loadAfterSync: loadAfterSync)
    }

    private func syncStandardSteamState(for bottleURL: URL, loadAfterSync: Bool) {
        let legacyOverride = readUsrDefOptionString(key: "windowsSteamFolder")
            .map(fileURL(from:))
        containerSteamStore.refresh(
            bottleURL: bottleURL,
            legacyOverride: legacyOverride
        )
        appGlobals.windowsSteamFolder = containerSteamStore.installation?.steamRootURL
        appGlobals.refreshSteamIdentity(
            containerInstallation: containerSteamStore.installation
        )
        libraryPageGlobals.folders.removeAll()
        resetPersistedFolderAccess()
        let steamLibrariesURLs = containerSteamStore.installation?.libraries
            .compactMap(\.steamAppsURL) ?? []
        steamLibrariesURLs.forEach { url in
            validateAddSteamFolder(url, to: &libraryPageGlobals.folders)
        }
        if loadAfterSync {
            Task { await load() }
        }
    }

    private func createSelectedBottle() {
        guard !isOnlineMode, let crossOverPath = appGlobals.cxAppPath else { return }
        let name = newBottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        creatingBottle = true
        createBottleProcess = try? createBottle(cxAppPath: crossOverPath, bottleName: name)
        createBottleProcess?.terminationHandler = { _ in
            DispatchQueue.main.async {
                creatingBottle = false
                if let currentPath = appGlobals.cxAppPath {
                    let appURL = URL(fileURLWithPath: currentPath)
                    refreshBottles(at: appURL)
                    if let created = bottles.first(where: {
                        $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
                    }) {
                        appGlobals.selectedBottle = created.absoluteString
                        persistUsrDefOptionString(key: "selectedBottle", value: created.absoluteString)
                        if isOnlineMode {
                            try? OnlineGameBottleConfiguration.apply(to: created)
                            Task { await load() }
                        } else {
                            syncStandardSteamState(for: created, loadAfterSync: true)
                        }
                    }
                }
            }
        }
        if createBottleProcess == nil { creatingBottle = false }
    }

    private func importLauncher() {
        let panel = NSOpenPanel()
        panel.title = "选择 SeasunGame.exe、启动器文件夹或 ZIP"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "exe") ?? .data,
            .zip,
            .folder
        ]
        guard let sourceURL = panel.runModal() == .OK ? panel.url : nil,
              let bottleURL = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle)
        else { return }

        do {
            let launcherURL = try OnlineLauncherImporter.installLauncher(
                from: sourceURL,
                into: bottleURL
            )
            launcherImportMessage = "已安装 \(launcherURL.lastPathComponent)，剑网 3 启动器卡片已添加。"
            Task { await load() }
        } catch {
            launcherImportMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func importDependency(_ asset: DependencyAsset) -> Bool {
        let panel = NSOpenPanel()
        panel.title = "导入 \(asset.displayName) 压缩包"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .zip,
            UTType(filenameExtension: "gz") ?? .data,
            UTType(filenameExtension: "xz") ?? .data,
            UTType(filenameExtension: "tar") ?? .data
        ]
        guard let sourceURL = panel.runModal() == .OK ? panel.url : nil else { return false }
        do {
            let record = try DependencyArchiveStore.importArchive(sourceURL, for: asset)
            dependencyImportMessage = "已导入 \(asset.displayName)：\(record.fileName)（SHA-256：\(record.sha256.prefix(12))…）"
            return true
        } catch {
            dependencyImportMessage = error.localizedDescription
            return false
        }
    }
}

#Preview {
    OptionsView(load: { })
}
