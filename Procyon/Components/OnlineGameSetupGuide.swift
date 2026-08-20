//
//  OnlineGameSetupGuide.swift
//  Procyon
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum OnlineGameSetupStatus {
    static func isComplete(appGlobals: AppGlobals) -> Bool {
        OnlineGameRuntimeKind.migrateLegacyCrossOverConfigurationIfNeeded(
            appGlobals: appGlobals
        )
        guard
            let bottleURL = OnlineGameDiscovery.selectedBottleURL(
                from: appGlobals.selectedBottle
            ),
            FileManager.default.fileExists(atPath: bottleURL.path)
        else {
            return false
        }
        switch OnlineGameRuntimeKind.selected() {
        case .crossOver:
            guard let crossOverPath = appGlobals.cxAppPath,
                  OnlineGameRuntimeKind.isValidCrossOverApplication(
                    at: URL(fileURLWithPath: crossOverPath)
                  )
            else {
                return false
            }
        case .bundledWine:
            guard BundledWineRuntime.ownsPrefix(bottleURL),
                  BundledWineRuntime.isValidPrefix(at: bottleURL),
                  BundledWineRuntime.isCurrentRuntime()
            else {
                return false
            }
        }
        return bottleURL.lastPathComponent.caseInsensitiveCompare(
            OnlineGameMode.defaultBottleName
        ) == .orderedSame
            && OnlineGameDiscovery.jx3Installation(in: bottleURL).isDetected
    }

    /// An existing embedded-Wine container only needs its immutable runtime
    /// refreshed when the app ships a newer version. Keep it out of first-run
    /// setup so the user sees an updater rather than the onboarding guide.
    static func requiresBundledWineRuntimeUpdate(appGlobals: AppGlobals) -> Bool {
        OnlineGameRuntimeKind.migrateLegacyCrossOverConfigurationIfNeeded(
            appGlobals: appGlobals
        )
        guard OnlineGameRuntimeKind.selected() == .bundledWine,
              let bottleURL = OnlineGameDiscovery.selectedBottleURL(
                from: appGlobals.selectedBottle
              ),
              BundledWineRuntime.ownsPrefix(bottleURL),
              bottleURL.lastPathComponent.caseInsensitiveCompare(
                OnlineGameMode.defaultBottleName
              ) == .orderedSame
        else {
            return false
        }
        return BundledWineRuntime.hasMigratableLegacyInstallation()
            || BundledWineRuntime.requiresRuntimeUpdate(
                runtimeURL: BundledWineRuntime.installationURL,
                prefixURL: bottleURL
            )
    }
}

/// Shown only to users with an already-working embedded-Wine Games container
/// when an app update includes a newer runtime. The existing container is
/// preserved; `preparePrefix` detects it and performs only the runtime swap.
struct OnlineGameRuntimeUpdateView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appGlobals: AppGlobals
    @MainActor var load: @Sendable () async -> Void

    @State private var progress: Double = 0
    @State private var progressLabel = "正在检查内置 Wine 更新…"
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        Modal(
            "更新内置 Wine",
            showModal: $isPresented,
            scrollable: false,
            allowsClose: false
        ) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("正在更新内置 Wine", systemImage: "arrow.triangle.2.circlepath")
                        .font(.title2.weight(.semibold))
                    Text("将保留现有 Games 容器和剑网3文件，无需重新导入。")
                        .foregroundStyle(.secondary)
                    Text("\(installedVersion) → \(BundledWineRuntime.runtimeVersion)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(progressLabel)
                        .fontWeight(.medium)
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("退出 App", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if errorMessage != nil {
                        Button("重新尝试") {
                            beginUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                    } else if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .frame(width: 520, alignment: .leading)
            .padding(.vertical, 24)
        }
        .interactiveDismissDisabled()
        .task {
            beginUpdate()
        }
    }

    private var installedVersion: String {
        BundledWineRuntime.installedRuntimeVersion(
            at: BundledWineRuntime.installationURL
        ) ?? BundledWineRuntime.pendingLegacyRuntimeVersion()
            ?? "已安装版本"
    }

    private func beginUpdate() {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        progress = 0
        progressLabel = "正在检查内置 Wine 更新…"

        let reportProgress: BundledWineRuntime.ProgressHandler = { value, label in
            Task { @MainActor in
                progress = min(max(value, 0), 1)
                progressLabel = label
            }
        }

        Task { @MainActor in
            do {
                let bottleURL = try await Task.detached(priority: .userInitiated) {
                    let bottleURL = try BundledWineRuntime.preparePrefix(
                        progress: reportProgress
                    )
                    reportProgress(0.97, "正在核对 Games 容器配置…")
                    try OnlineGameBottleConfiguration.apply(to: bottleURL)
                    reportProgress(1, "内置 Wine 更新完成")
                    return bottleURL
                }.value
                OnlineGameRuntimeKind.activate(
                    .bundledWine,
                    with: bottleURL,
                    appGlobals: appGlobals
                )
                progress = 1
                progressLabel = "内置 Wine 更新完成"
                isUpdating = false
                await load()
                isPresented = false
            } catch {
                isUpdating = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct OnlineGameSetupLandingView: View {
    let startAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("完成首次设置", systemImage: "sparkles.rectangle.stack")
        } description: {
            VStack(spacing: 10) {
                Text("先选择 CrossOver 或 Arclume 内置 Wine，再创建独立的 Games 容器。最后导入启动器即可进入剑网3启动器首页。剑网3模式首次设置完成前不能退出。")
                    .multilineTextAlignment(.center)
                Button("开始设置", action: startAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .foregroundStyle(.white)
    }
}

struct OnlineGameSetupGuide: View {
    private enum Stage: Int, CaseIterable {
        case runtime
        case crossOver
        case bottle
        case launcher
        case complete

        var title: String {
            switch self {
            case .runtime: "选择运行时"
            case .crossOver: "准备所选运行时"
            case .bottle: "准备 Games 容器"
            case .launcher: "导入剑网 3 启动器"
            case .complete: "设置完成"
            }
        }
    }

    @Binding var isPresented: Bool
    @EnvironmentObject private var appGlobals: AppGlobals
    @MainActor var load: @Sendable () async -> Void
    private let targetRuntime: OnlineGameRuntimeKind?

    @State private var stage: Stage = .runtime
    @State private var chosenRuntime: OnlineGameRuntimeKind?
    @State private var progress: Double = 0
    @State private var progressLabel = "等待选择运行时"
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var pendingCrossOverURL: URL?
    @State private var lastCrossOverURL: URL?
    @State private var launcherImportMessage: String?
    @State private var isWatchingManualImport = false
    @State private var isScanningDownloads = false
    @State private var downloadScanMessage: String?
    @State private var migrationSourceBottleURL: URL?
    @State private var isMigratingGame = false

    init(
        isPresented: Binding<Bool>,
        load: @escaping @MainActor @Sendable () async -> Void,
        targetRuntime: OnlineGameRuntimeKind? = nil
    ) {
        _isPresented = isPresented
        self.load = load
        self.targetRuntime = targetRuntime
    }

    var body: some View {
        Modal(
            targetRuntime == nil ? "首次设置" : "配置 \(targetRuntime!.title)",
            showModal: $isPresented,
            scrollable: false,
            allowsClose: targetRuntime != nil
        ) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 26) {
                    steps
                        .frame(width: 220, alignment: .leading)

                    Divider()

                    stageContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出 App", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("退出 App")
                .padding(.top, -6)
            }
            .frame(width: 710, height: 420)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
        .interactiveDismissDisabled(targetRuntime == nil)
        .onAppear {
            captureMigrationSource()
            synchronizeStage()
            if targetRuntime == .crossOver,
               let crossOverPath = appGlobals.cxAppPath,
               !OnlineGameRuntimeKind.isValidCrossOverApplication(
                   at: URL(fileURLWithPath: crossOverPath)
               ) {
                DispatchQueue.main.async {
                    chooseCrossOver()
                }
            }
        }
        .task(id: isWatchingManualImport) {
            guard
                isWatchingManualImport,
                let bottleURL = selectedBottleURL
            else {
                return
            }
            await monitorManualImport(in: bottleURL)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置剑网 3 启动器")
                .font(.title2.weight(.semibold))
            Text("只需完成一次，以后打开应用会直接显示剑网3启动器首页。")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(Stage.allCases, id: \.rawValue) { item in
                HStack(spacing: 10) {
                    Image(systemName: stepIcon(for: item))
                        .frame(width: 22)
                        .foregroundStyle(stepColor(for: item))
                    Text(item.title)
                        .fontWeight(item == stage ? .semibold : .regular)
                        .foregroundStyle(item.rawValue > stage.rawValue ? .secondary : .primary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch stage {
            case .runtime:
                stageHeader(
                    "选择剑网3运行时",
                    detail: "两种运行时会使用独立的 Games 容器。后续会继续使用本次选择，不会改写你已有的 CrossOver。"
                )
                Button {
                    chooseRuntime(.crossOver)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("使用 CrossOver")
                            .fontWeight(.semibold)
                        Text(OnlineGameRuntimeKind.crossOver.detail)
                            .font(.footnote)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    chooseRuntime(.bundledWine)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("使用 Arclume 内置 Wine")
                            .fontWeight(.semibold)
                        Text(OnlineGameRuntimeKind.bundledWine.detail)
                            .font(.footnote)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

            case .crossOver:
                if isBusy {
                    stageHeader(
                        "正在准备 CrossOver",
                        detail: "正在从 App 内置资源安装 GStreamer、DXMT 和 GPTK 4.0 Beta 2。"
                    )
                    ProgressView(value: progress, total: 100) {
                        Text(progressLabel)
                    }
                    .frame(maxWidth: 360)
                } else {
                    stageHeader(
                        "选择 CrossOver",
                        detail: "请选择已经安装的 CrossOver.app。运行依赖已经随 App 附带，不需要联网或手动导入。"
                    )
                    Button("选择 CrossOver.app…") {
                        chooseCrossOver()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

            case .bottle:
                stageHeader(
                    isMigratingGame
                        ? "正在迁移剑网3"
                        : runtimeForSetup == .bundledWine
                        ? "正在准备内置 Wine"
                        : "正在创建 Games 容器",
                    detail: isMigratingGame
                        ? "正在移动剑网3启动器与游戏文件到新的 Games 容器；旧容器会保留。"
                        : runtimeForSetup == .bundledWine
                        ? "正在解压自编译 Wine，并创建独立的 64 位 Games 容器。"
                        : "剑网3模式正在自动创建独立的 64 位 Windows 10 Games 容器。"
                )
                if isMigratingGame || runtimeForSetup == .bundledWine {
                    ProgressView(value: progress, total: 1) {
                        Text(progressLabel)
                    } currentValueLabel: {
                        Text("\(Int(progress * 100))%")
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 360)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
                if !isMigratingGame {
                    Text(runtimeForSetup == .bundledWine
                    ? "容器名称：Games"
                    : "容器名称：Games")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !isMigratingGame, runtimeForSetup != .bundledWine {
                    Text(progressLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

            case .launcher:
                stageHeader(
                    "导入剑网 3 启动器",
                    detail: "选择 SeasunGame.exe、完整启动器文件夹或 ZIP。选择文件夹会直接移动到 Games 容器，不会复制完整游戏；导入不会立即运行。"
                )
                HStack(spacing: 10) {
                    Button("导入启动器…") {
                        importLauncher()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isBusy || isWatchingManualImport)

                    Button(isWatchingManualImport ? "停止监听" : "手动导入") {
                        if isWatchingManualImport {
                            stopManualImport()
                        } else {
                            startManualImport()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isBusy)
                }

                Button("从下载文件夹扫描") {
                    scanDownloadsAndImport()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isBusy || isScanningDownloads || isWatchingManualImport)

                if isWatchingManualImport {
                    Label(
                        "正在监听 drive_c，发现 SeasunGame.exe 后会自动完成设置。",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .foregroundStyle(.procyonSecondary)
                }
                if isScanningDownloads {
                    ProgressView("正在扫描并导入下载文件夹内容…")
                        .controlSize(.small)
                }
                if let downloadScanMessage {
                    Text(downloadScanMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let launcherImportMessage {
                    Label(launcherImportMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text("也可以把 SeasunGame 文件夹复制到打开的 drive_c 中，应用会自动监听并识别。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            case .complete:
                stageHeader(
                    "剑网 3 启动器已添加",
                    detail: "主界面现在会直接显示启动器首页。只有点击首页上的“打开启动器”时才会真正运行。"
                )
                Label("\(runtimeForSetup?.title ?? OnlineGameRuntimeKind.selected().title)、Games 容器和启动器均已就绪", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Button("进入主界面") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    if stage == .crossOver, lastCrossOverURL != nil {
                        Button("重试内置依赖准备") {
                            pendingCrossOverURL = lastCrossOverURL
                            beginCrossOverPreparation()
                        }
                    }
                    if stage == .bottle,
                       runtimeForSetup == .bundledWine {
                        Button("重新初始化内置 Wine") {
                            beginBundledWinePreparation()
                        }
                        if FileManager.default.fileExists(
                            atPath: BundledWineRuntime.prefixInitializationLogURL.path
                        ) {
                            Button("打开初始化诊断目录") {
                                NSWorkspace.shared.open(
                                    BundledWineRuntime.prefixInitializationDiagnosticsDirectoryURL
                                )
                            }
                        }
                    }
                }
                .font(.callout)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var selectedBottleURL: URL? {
        OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle)
    }

    private var runtimeForSetup: OnlineGameRuntimeKind? {
        targetRuntime
            ?? chosenRuntime
            ?? (OnlineGameRuntimeKind.hasExplicitSelection()
                ? OnlineGameRuntimeKind.selected()
                : nil)
    }

    private func captureMigrationSource() {
        guard let targetRuntime,
              OnlineGameRuntimeKind.selected() != targetRuntime,
              let selectedBottleURL,
              OnlineGameDiscovery.jx3Installation(in: selectedBottleURL).isDetected
        else {
            return
        }
        migrationSourceBottleURL = selectedBottleURL
    }

    private func stageHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title.weight(.semibold))
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepIcon(for item: Stage) -> String {
        if item.rawValue < stage.rawValue || stage == .complete {
            return "checkmark.circle.fill"
        }
        if item == stage {
            return isBusy ? "hourglass.circle.fill" : "circle.inset.filled"
        }
        return "circle"
    }

    private func stepColor(for item: Stage) -> Color {
        if item.rawValue < stage.rawValue || stage == .complete {
            return .green
        }
        return item == stage ? .accentColor : .secondary
    }

    private func synchronizeStage() {
        OnlineGameRuntimeKind.migrateLegacyCrossOverConfigurationIfNeeded(
            appGlobals: appGlobals
        )
        if targetRuntime == nil,
           chosenRuntime == nil,
           OnlineGameSetupStatus.isComplete(appGlobals: appGlobals) {
            stage = .complete
            return
        }

        guard let runtime = runtimeForSetup else {
            stage = .runtime
            return
        }

        switch runtime {
        case .crossOver:
            guard let crossOverPath = appGlobals.cxAppPath,
                  OnlineGameRuntimeKind.isValidCrossOverApplication(
                    at: URL(fileURLWithPath: crossOverPath)
                  )
            else {
                stage = .crossOver
                return
            }
            stage = .bottle
            Task { await ensureBottleAndContinue(crossOverPath: crossOverPath) }
        case .bundledWine:
            if let bottleURL = selectedBottleURL,
               BundledWineRuntime.ownsPrefix(bottleURL),
               BundledWineRuntime.isValidPrefix(at: bottleURL),
               BundledWineRuntime.isCurrentRuntime() {
                stage = .launcher
            } else {
                stage = .bottle
                beginBundledWinePreparation()
            }
        }
    }

    private func chooseRuntime(_ runtime: OnlineGameRuntimeKind) {
        chosenRuntime = runtime
        errorMessage = nil
        launcherImportMessage = nil
        progress = 0
        switch runtime {
        case .crossOver:
            stage = .crossOver
            chooseCrossOver()
        case .bundledWine:
            stage = .bottle
            beginBundledWinePreparation()
        }
    }

    private func chooseCrossOver() {
        guard let sourceURL = openFolderSelectorPanel(
            type: .application,
            title: "选择 CrossOver.app"
        ) else {
            return
        }
        guard OnlineGameRuntimeKind.isValidCrossOverApplication(at: sourceURL) else {
            errorMessage = "请选择可用的 CrossOver.app。"
            stage = .crossOver
            return
        }
        pendingCrossOverURL = sourceURL
        lastCrossOverURL = sourceURL
        beginCrossOverPreparation()
    }

    private func beginCrossOverPreparation() {
        guard let sourceURL = pendingCrossOverURL else { return }
        pendingCrossOverURL = nil
        lastCrossOverURL = sourceURL
        isBusy = true
        errorMessage = nil
        progress = 0
        progressLabel = "准备 App 内置依赖…"

        Task { @MainActor in
            do {
                let patchedAppURL = try await makeCrossoverPatchedCopy(
                    sourceCXPath: sourceURL,
                    dependencyMode: .automatic,
                    useBundledDependencies: true,
                    setProgress: { value, label in
                        progress = value
                        progressLabel = label
                    },
                    setLoading: { _ in }
                )
                appGlobals.cxAppPath = patchedAppURL.path
                persistUsrDefOptionString(key: "cxAppPath", value: patchedAppURL.path)
                persistUsrDefOptionString(
                    key: "cxCompleteAppPath",
                    value: patchedAppURL.path
                )
                if DEBUG_ENABLED {
                    console.saveLogs()
                }
                stage = .bottle
                await ensureBottleAndContinue(crossOverPath: patchedAppURL.path)
            } catch {
                isBusy = false
                stage = .crossOver
                errorMessage = error.localizedDescription
            }
        }
    }

    private func beginBundledWinePreparation() {
        guard !isBusy else { return }
        isBusy = true
        stage = .bottle
        errorMessage = nil
        progress = 0
        progressLabel = "正在准备内置 Wine…"

        let reportProgress: BundledWineRuntime.ProgressHandler = { value, label in
            Task { @MainActor in
                progress = min(max(value, 0), 1)
                progressLabel = label
            }
        }

        Task { @MainActor in
            do {
                let bottleURL = try await Task.detached(priority: .userInitiated) {
                    let bottleURL = try BundledWineRuntime.preparePrefix(
                        progress: reportProgress
                    )
                    reportProgress(0.97, "正在写入中文环境和字体回退…")
                    try OnlineGameBottleConfiguration.apply(to: bottleURL)
                    reportProgress(1, "内置 Wine 与 Games 容器已准备完成")
                    return bottleURL
                }.value
                try await migrateJX3IfNeeded(to: bottleURL)
                OnlineGameRuntimeKind.activate(
                    .bundledWine,
                    with: bottleURL,
                    appGlobals: appGlobals
                )
                isBusy = false
                progress = 1
                progressLabel = "内置 Wine 与 Games 容器已准备完成"
                stage = OnlineGameDiscovery.jx3Installation(in: bottleURL).isDetected
                    ? .complete
                    : .launcher
                await load()
            } catch {
                isBusy = false
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func ensureBottleAndContinue(crossOverPath: String) async {
        isBusy = true
        stage = .bottle
        errorMessage = nil
        do {
            let bottleURL = try await ensureDefaultBottle(
                crossOverURL: URL(fileURLWithPath: crossOverPath)
            )
            try OnlineGameBottleConfiguration.apply(to: bottleURL)
            try await migrateJX3IfNeeded(to: bottleURL)
            OnlineGameRuntimeKind.activate(
                .crossOver,
                with: bottleURL,
                appGlobals: appGlobals
            )
            isBusy = false
            stage = OnlineGameDiscovery.jx3Installation(in: bottleURL).isDetected
                ? .complete
                : .launcher
            await load()
        } catch {
            isBusy = false
            errorMessage = error.localizedDescription
        }
    }

    private func ensureDefaultBottle(crossOverURL: URL) async throws -> URL {
        if let existing = try getAllBottles(appDir: crossOverURL).first(where: {
            $0.lastPathComponent.caseInsensitiveCompare(
                OnlineGameMode.defaultBottleName
            ) == .orderedSame
        }) {
            return existing
        }

        let process = try createBottle(
            cxAppPath: crossOverURL.path,
            bottleName: OnlineGameMode.defaultBottleName
        )
        try await waitForTermination(of: process)

        if let created = try getAllBottles(appDir: crossOverURL).first(where: {
            $0.lastPathComponent.caseInsensitiveCompare(
                OnlineGameMode.defaultBottleName
            ) == .orderedSame
        }) {
            return created
        }
        throw CocoaError(.fileNoSuchFile)
    }

    @MainActor
    private func migrateJX3IfNeeded(to destinationBottleURL: URL) async throws {
        guard let sourceBottleURL = migrationSourceBottleURL,
              sourceBottleURL.standardizedFileURL != destinationBottleURL.standardizedFileURL,
              OnlineGameDiscovery.jx3Installation(in: sourceBottleURL).isDetected
        else {
            return
        }

        isMigratingGame = true
        progress = 0
        progressLabel = "正在扫描剑网3文件…"
        let reportProgress: OnlineGameContainerMigration.ProgressHandler = { value, label in
            Task { @MainActor in
                progress = min(max(value, 0), 1)
                progressLabel = label
            }
        }

        defer { isMigratingGame = false }
        _ = try await Task.detached(priority: .userInitiated) {
            try OnlineGameContainerMigration.migrateJX3(
                from: sourceBottleURL,
                to: destinationBottleURL,
                progress: reportProgress
            )
        }.value
    }

    private func waitForTermination(of process: Process) async throws {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { completedProcess in
                if completedProcess.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: OnlineArchiveImportError.launcherInstallFailed(
                            "创建 Games 容器失败，退出状态为 \(completedProcess.terminationStatus)。"
                        )
                    )
                }
            }
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
        guard
            let sourceURL = panel.runModal() == .OK ? panel.url : nil,
            let bottleURL = OnlineGameDiscovery.selectedBottleURL(
                from: appGlobals.selectedBottle
            )
        else {
            return
        }

        isWatchingManualImport = false
        isScanningDownloads = false
        downloadScanMessage = nil
        isBusy = true
        errorMessage = nil
        do {
            try OnlineGameBottleConfiguration.apply(to: bottleURL)
            let launcherURL = try OnlineLauncherImporter.installLauncher(
                from: sourceURL,
                into: bottleURL
            )
            OnlineGameInitialConfiguration.startPolling(for: bottleURL)
            completeLauncherSetup(message: "已安装 \(launcherURL.lastPathComponent)")
        } catch {
            isBusy = false
            errorMessage = error.localizedDescription
        }
    }

    private func startManualImport() {
        guard let bottleURL = selectedBottleURL else {
            errorMessage = "Games 容器尚未准备好，请先完成前面的步骤。"
            return
        }

        let driveCURL = bottleURL.appendingPathComponent("drive_c", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: driveCURL,
                withIntermediateDirectories: true
            )
        } catch {
            errorMessage = "无法打开 Games 容器的 drive_c：\(error.localizedDescription)"
            return
        }

        errorMessage = nil
        launcherImportMessage = nil
        downloadScanMessage = nil
        isWatchingManualImport = true
        NSWorkspace.shared.open(driveCURL)
    }

    private func stopManualImport() {
        isWatchingManualImport = false
        launcherImportMessage = "已停止监听 drive_c。"
    }

    private func monitorManualImport(in bottleURL: URL) async {
        for _ in 0..<1_800 {
            guard !Task.isCancelled, isWatchingManualImport else {
                return
            }

            if OnlineGameDiscovery.jx3Installation(in: bottleURL).isDetected {
                isWatchingManualImport = false
                do {
                    try OnlineGameBottleConfiguration.apply(to: bottleURL)
                    OnlineGameInitialConfiguration.startPolling(for: bottleURL)
                    completeLauncherSetup(message: "已在 drive_c 中发现并识别 SeasunGame.exe")
                } catch {
                    errorMessage = error.localizedDescription
                }
                return
            }

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }

        if isWatchingManualImport {
            isWatchingManualImport = false
            errorMessage = "监听已超时。请重新点击“手动导入”，或使用其他导入方式。"
        }
    }

    private func scanDownloadsAndImport() {
        guard !isBusy else { return }
        isWatchingManualImport = false
        isScanningDownloads = true
        downloadScanMessage = "正在扫描下载文件夹…"
        launcherImportMessage = nil
        errorMessage = nil

        let candidates = OnlineLauncherDownloadScanner.candidates()
        guard let sourceURL = candidates.first else {
            isScanningDownloads = false
            downloadScanMessage = "下载文件夹中未找到 SeasunGame 文件夹或 SeasunGame.zip。"
            return
        }

        downloadScanMessage = "发现 \(sourceURL.lastPathComponent)，正在导入…"
        importLauncher(from: sourceURL)
    }

    private func importLauncher(from sourceURL: URL) {
        guard let bottleURL = selectedBottleURL else {
            isScanningDownloads = false
            errorMessage = "Games 容器尚未准备好，请先完成前面的步骤。"
            return
        }

        isBusy = true
        errorMessage = nil
        do {
            try OnlineGameBottleConfiguration.apply(to: bottleURL)
            let launcherURL = try OnlineLauncherImporter.installLauncher(
                from: sourceURL,
                into: bottleURL
            )
            OnlineGameInitialConfiguration.startPolling(for: bottleURL)
            completeLauncherSetup(
                message: "已从下载文件夹导入 \(launcherURL.lastPathComponent)"
            )
        } catch {
            isBusy = false
            isScanningDownloads = false
            errorMessage = error.localizedDescription
        }
    }

    private func completeLauncherSetup(message: String) {
        launcherImportMessage = message
        errorMessage = nil
        isScanningDownloads = false
        isBusy = true
        Task { @MainActor in
            await load()
            isBusy = false
            stage = .complete
        }
    }

}
