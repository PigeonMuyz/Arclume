//
//  OptionsView.swift
//  Procyon
//

import SwiftUI
import UniformTypeIdentifiers

struct OptionsView: View {
    @State private var selectedSettingsPage = "通用"
    @AppStorage("jx3CompactHome", store: UserDefaults(suiteName: suiteName))
    private var compactJX3Home = false

    @State private var bottles: [URL] = []
    @State private var progress: Double = 0
    @State private var progressLabel = L10n.string("Processing...")
    @State private var downloading = false
    @State private var creatingBottle = false
    @State private var newBottleName = ""
    @State private var createBottleProcess: Process?
    @State private var preparingBundledSteamPrefix = false
    @State private var bundledSteamProgress: Double?
    @State private var bundledSteamProgressLabel: String?
    @State private var launcherImportMessage: String?
    @State private var dependencyImportMessage: String?
    @State private var dependencyInstallMode: DependencyInstallMode = .automatic
    @State private var pendingCrossOverURL: URL?
    @State private var showDependencyModeDialog = false
    @State private var showNativeGameImport = false
    @State private var showModeSelection = false
    @State private var showApplicationUpdateConfirmation = false
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
    @AppStorage(StandardGameRuntimeKind.defaultsKey, store: UserDefaults(suiteName: suiteName))
    private var standardGameRuntimeRaw = StandardGameRuntimeKind.bundledWine.rawValue

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

    private var standardGameRuntime: StandardGameRuntimeKind {
        .bundledWine
    }

    var body: some View {
        Modal(
            L10n.string("Options"),
            showModal: $libraryPageGlobals.showOptions,
            scrollable: false,
            subdued: true
        ) {
            settingsContent
        }
        .onAppear {
            if let requestedPage = libraryPageGlobals.requestedSettingsPage {
                selectedSettingsPage = requestedPage
                libraryPageGlobals.requestedSettingsPage = nil
            }
            if isOnlineMode {
                OnlineGameRuntimeKind.migrateLegacyCrossOverConfigurationIfNeeded(
                    appGlobals: appGlobals
                )
                OnlineGameRuntimeKind.restoreActiveBottleIfAvailable(
                    appGlobals: appGlobals
                )
            }
            if !isOnlineMode, standardGameRuntime == .bundledWine {
                restoreBundledSteamPrefixIfAvailable()
            }
        }
        .sheet(isPresented: $showNativeGameImport) {
            NativeGameImportView(isPresented: $showNativeGameImport)
                .environmentObject(libraryPageGlobals)
        }
        .sheet(isPresented: $showModeSelection) {
            ModeSelectionView(allowsCancel: true) { mode in
                if mode != modeStore.selectedMode {
                    if let current = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle) {
                        if isOnlineMode {
                            OnlineGameRuntimeKind.recordBottle(current, for: .selected())
                        } else {
                            StandardGameRuntimeKind.recordBottle(current, for: .selected())
                        }
                    }
                    let target = mode.isOnlineGameMode
                        ? OnlineGameRuntimeKind.configuredBottleURL(for: .selected())
                        : StandardGameRuntimeKind.configuredBottleURL(for: .selected())
                    appGlobals.selectedBottle = target?.absoluteString ?? ""
                    persistUsrDefOptionString(key: "selectedBottle", value: appGlobals.selectedBottle)
                    containerSteamStore.refresh(bottleURL: mode.isOnlineGameMode ? nil : target)
                    appGlobals.windowsSteamFolder = containerSteamStore.installation?.steamRootURL
                    appGlobals.refreshSteamIdentity(containerInstallation: containerSteamStore.installation)
                }
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
        .alert(
            "安装 Arclume 更新？",
            isPresented: $showApplicationUpdateConfirmation
        ) {
            Button("更新并重启") {
                Task { await updateService.installApplicationUpdate() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将下载并校验 DMG 的 SHA-256，确认 Arclume 版本后自动替换当前 App 并重新启动。")
        }
    }

    private var settingsPages: [(String, String)] {
        var pages = [("通用", "gearshape")]
        if !isOnlineMode {
            pages += [("运行时", "shippingbox"), ("游戏库", "square.stack")]
        }
        return pages + [("更新", "arrow.triangle.2.circlepath"), ("关于", "info.circle")]
    }

    private var settingsContent: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 4) {
                ForEach(settingsPages, id: \.0) { page in
                    Button {
                        selectedSettingsPage = page.0
                    } label: {
                        Label(page.0, systemImage: page.1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                selectedSettingsPage == page.0 ? Color.white.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSettingsPage == page.0 ? [.isSelected] : [])
                }
                Spacer()
            }
            .frame(width: 125)
            .padding(.trailing, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedSettingsPage {
                    case "运行时":
                        settingsCard { standardRuntimeSection }
                        if standardGameRuntime == .crossOver {
                            settingsCard { crossOverSection }
                            settingsCard {
                                steamBottleSection
                                if !appGlobals.selectedBottle.isEmpty {
                                    Divider()
                                    steamInstallationSection
                                }
                            }
                            settingsCard { dependencySection }
                        } else {
                            settingsCard { bundledSteamPrefixSection }
                        }
                    case "游戏库":
                        settingsCard { GameLibrariesList(load: load) }
                        if !appGlobals.selectedBottle.isEmpty {
                            settingsCard { steamPathSection }
                        }
                        settingsCard { nativeGamesSection }
                        settingsCard { metadataSection }
                        settingsCard {
                            Button("恢复已隐藏游戏的自动识别") {
                                UserDefaults(suiteName: suiteName)?.removeObject(forKey: "hiddenInstalledGames.v1")
                                Task { await load() }
                            }
                            Text("不移动或删除文件，下次扫描将重新发现仍存在的游戏。").font(.footnote)
                        }
                    case "更新":
                        updateCard
                    case "关于":
                        aboutCard
                    default:
                        modeSelectionCard
                        appearanceCard
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 680, height: 500)
        .padding(.top, 18)
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

            if isOnlineMode {
                HStack(spacing: 12) {
                    Label("剑三首页", systemImage: "rectangle.grid.1x2")
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer(minLength: 8)
                    Picker("剑三首页", selection: $compactJX3Home) {
                        Text("简洁").tag(true)
                        Text("完整").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .help("简洁视图隐藏海报和资讯图片，仅保留启动与设置。")
                Divider()
            }
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
                    Button(updateService.isDownloadingApplication ? "更新中…" : "更新并重启") {
                        showApplicationUpdateConfirmation = true
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
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var standardRuntimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("运行时")
                .font(.headline)
            Text("Arclume Wine").font(.title3)
            Text("统一使用内置 Wine。旧 CrossOver 容器保留，不会自动迁移或删除。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .help(
            standardGameRuntime == .bundledWine
                ? "普通 Windows 游戏使用 Arclume Wine 与独立 Steam 容器，不需要 CrossOver。"
                : "普通 Windows 游戏使用你选择的 CrossOver Bottle。"
        )
    }

    private var bundledSteamPrefixSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Steam 容器").font(.headline)
                Spacer()
                Text("64 位").font(.caption).foregroundStyle(.secondary)
            }
            if preparingBundledSteamPrefix {
                ProgressView(value: bundledSteamProgress) {
                    Text(bundledSteamProgressLabel ?? "正在准备容器…").font(.footnote)
                }
            } else if BundledWineRuntime.isValidPrefix(at: BundledWineRuntime.standardSteamPrefixURL) {
                steamInstallationSection
            } else {
                HStack {
                    Text("尚未创建").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("创建并安装 Steam") { prepareBundledSteamPrefix() }
                        .buttonStyle(.borderedProminent)
                        .disabled(containerSteamStore.steamSetupBusy)
                }
                if let error = containerSteamStore.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
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
            .disabled(creatingBottle || containerSteamStore.steamSetupBusy)
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
        }
    }

    private var steamBottleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steam 容器")
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
                .disabled(creatingBottle || containerSteamStore.steamSetupBusy)
                .onChange(of: appGlobals.selectedBottle) { _, value in
                    selectStandardBottle(value)
                }
            }

            HStack {
                TextField("新 Bottle 名称", text: $newBottleName)
                Button("新建") { createSelectedBottle() }
                    .disabled(
                        creatingBottle
                            || containerSteamStore.steamSetupBusy
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

            .help(L10n.string(
                "Native apps use their bundle identifier to look up App Store descriptions, developers, and genres in the selected language."
            ))

            if steamMetadataSource == SteamMetadataSource.localProxy.rawValue {
                Text(L10n.string("Start local_steam_proxy.py from the project folder before reloading the library."))
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

    private func restoreBundledSteamPrefixIfAvailable() {
        let prefixURL = BundledWineRuntime.standardSteamPrefixURL
        guard BundledWineRuntime.isValidPrefix(at: prefixURL) else {
            containerSteamStore.refresh(bottleURL: nil)
            appGlobals.windowsSteamFolder = nil
            return
        }
        StandardGameRuntimeKind.activate(
            .bundledWine,
            with: prefixURL,
            appGlobals: appGlobals
        )
        syncStandardSteamState(for: prefixURL, loadAfterSync: false)
    }

    private func switchStandardRuntime(to runtime: StandardGameRuntimeKind) {
        StandardGameRuntimeKind.select(runtime)
        switch runtime {
        case .crossOver:
            guard let bottleURL = StandardGameRuntimeKind.configuredBottleURL(for: .crossOver),
                  FileManager.default.fileExists(atPath: bottleURL.path)
            else {
                appGlobals.selectedBottle = ""
                persistUsrDefOptionString(key: "selectedBottle", value: "")
                syncStandardSteamState(loadAfterSync: true)
                return
            }
            StandardGameRuntimeKind.activate(
                .crossOver,
                with: bottleURL,
                appGlobals: appGlobals
            )
            syncStandardSteamState(for: bottleURL, loadAfterSync: true)
        case .bundledWine:
            restoreBundledSteamPrefixIfAvailable()
            if !BundledWineRuntime.isValidPrefix(
                at: BundledWineRuntime.standardSteamPrefixURL
            ) {
                appGlobals.selectedBottle = ""
                persistUsrDefOptionString(key: "selectedBottle", value: "")
                syncStandardSteamState(loadAfterSync: true)
            }
        }
    }

    private func prepareBundledSteamPrefix() {
        guard !preparingBundledSteamPrefix, !containerSteamStore.steamSetupBusy else { return }
        preparingBundledSteamPrefix = true
        bundledSteamProgress = 0.01
        bundledSteamProgressLabel = "正在检查内置 Wine…"
        containerSteamStore.errorMessage = nil
        let reportProgress: BundledWineRuntime.ProgressHandler = { value, label in
            Task { @MainActor in
                bundledSteamProgress = min(max(value, 0), 1)
                bundledSteamProgressLabel = label
            }
        }
        Task {
            do {
                let prefixURL = try await Task.detached(priority: .userInitiated) {
                    try BundledWineRuntime.prepareStandardSteamPrefix(
                        progress: reportProgress
                    )
                }.value
                guard !OnlineGameMode.isEnabled, standardGameRuntime == .bundledWine else {
                    preparingBundledSteamPrefix = false
                    return
                }
                StandardGameRuntimeKind.activate(
                    .bundledWine,
                    with: prefixURL,
                    appGlobals: appGlobals
                )
                syncStandardSteamState(for: prefixURL, loadAfterSync: true)
                bundledSteamProgress = nil
                beginSteamInstallation(in: prefixURL, using: .bundledWine)
            } catch {
                containerSteamStore.errorMessage = error.localizedDescription
            }
            preparingBundledSteamPrefix = false
        }
    }

    private var steamInstallationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if containerSteamStore.steamSetupBusy {
                ProgressView(value: containerSteamStore.steamSetupProgress) {
                    Text(containerSteamStore.steamSetupMessage ?? "正在安装 Steam…")
                        .font(.footnote)
                }
                if containerSteamStore.steamSetupDownloading {
                    Button("取消下载", role: .cancel) { containerSteamStore.cancelSteamDownload() }
                }
            } else {
                HStack {
                    Label(
                        containerSteamStore.isReady ? "Steam 已安装" : "待安装 Steam",
                        systemImage: containerSteamStore.isReady ? "checkmark.circle.fill" : "arrow.down.circle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(containerSteamStore.isReady ? Color.green : Color.secondary)
                    Spacer()
                    if containerSteamStore.isReady {
                        Button(containerSteamStore.steamOpening ? "准备 Steam…" : "打开 Steam") {
                            if standardGameRuntime == .bundledWine {
                                containerSteamStore.openSteam(using: .bundledWine)
                            } else if let path = appGlobals.cxAppPath {
                                containerSteamStore.openSteam(using: .crossOver(URL(fileURLWithPath: path)))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("安装 Steam") { installSteamClient(manually: false) }
                            .buttonStyle(.borderedProminent)
                        Menu {
                            Button("选择本地安装包…") { installSteamClient(manually: true) }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .fixedSize()
                        .accessibilityLabel("其他安装方式")
                        .help("选择本地 SteamSetup.exe")
                    }
                }
                .disabled(libraryPageGlobals.isStoppingWine || appGlobals.selectedBottle.isEmpty || creatingBottle || preparingBundledSteamPrefix || containerSteamStore.steamOpening)
            }
            SteamUpdateRecoveryControl()
            if let error = containerSteamStore.steamSetupError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if let error = containerSteamStore.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func installSteamClient(manually: Bool) {
        guard !containerSteamStore.steamSetupBusy,
              let bottle = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle) else { return }
        let runtime: ContainerSteamRuntime
        if standardGameRuntime == .bundledWine {
            runtime = .bundledWine
        } else if let path = appGlobals.cxAppPath {
            runtime = .crossOver(URL(fileURLWithPath: path))
        } else { return }
        var installer: URL?
        if manually {
            let panel = NSOpenPanel()
            panel.title = "选择 SteamSetup.exe"
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            installer = url
        }
        beginSteamInstallation(in: bottle, using: runtime, installer: installer)
    }

    private func beginSteamInstallation(in bottle: URL, using runtime: ContainerSteamRuntime, installer: URL? = nil) {
        containerSteamStore.installSteamClient(in: bottle, using: runtime, installerURL: installer) { completedBottle in
            // The installer owns a captured container, even if settings close
            // or the user switches launcher mode while it is running.
            guard !OnlineGameMode.isEnabled,
                  OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle)?.standardizedFileURL
                    == completedBottle.standardizedFileURL else { return }
            syncStandardSteamState(for: completedBottle, loadAfterSync: true)
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
        if standardGameRuntime == .crossOver {
            StandardGameRuntimeKind.recordBottle(bottleURL, for: .crossOver)
        }
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
        guard !isOnlineMode, !creatingBottle, !containerSteamStore.steamSetupBusy,
              let crossOverPath = appGlobals.cxAppPath else { return }
        let name = newBottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !bottles.contains(where: { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame })
        else {
            containerSteamStore.errorMessage = "请使用未被占用的有效容器名称。"
            return
        }
        creatingBottle = true
        do {
            let process = try createBottle(cxAppPath: crossOverPath, bottleName: name)
            createBottleProcess = process
            Task {
                // createBottle starts the process before returning it. Polling
                // also covers fast exits that could precede a handler being set.
                while process.isRunning {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                creatingBottle = false
                guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                    containerSteamStore.errorMessage = "创建 Steam 容器失败（\(process.terminationStatus)）。"
                    return
                }
                guard !OnlineGameMode.isEnabled,
                      standardGameRuntime == .crossOver,
                      appGlobals.cxAppPath == crossOverPath else { return }
                let appURL = URL(fileURLWithPath: crossOverPath)
                refreshBottles(at: appURL)
                guard let created = bottles.first(where: {
                    $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
                }) else {
                    containerSteamStore.errorMessage = "创建后未找到 Steam 容器，请刷新重试。"
                    return
                }
                StandardGameRuntimeKind.activate(.crossOver, with: created, appGlobals: appGlobals)
                syncStandardSteamState(for: created, loadAfterSync: true)
                beginSteamInstallation(in: created, using: .crossOver(appURL))
            }
        } catch {
            creatingBottle = false
            containerSteamStore.errorMessage = error.localizedDescription
        }
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
