//
//  ContainerSteamStore.swift
//  Procyon
//

import Foundation
import Combine

@MainActor
final class ContainerSteamStore: ObservableObject {
    @Published private(set) var detection: ContainerSteamDetection?
    @Published private(set) var snapshots: [Int: SteamInstallSnapshot] = [:]
    @Published var errorMessage: String?
    @Published private(set) var steamSetupBusy = false
    @Published private(set) var steamSetupDownloading = false
    @Published private(set) var steamSetupProgress: Double?
    @Published private(set) var steamSetupMessage: String?
    @Published private(set) var steamSetupError: String?
    @Published private(set) var steamOpening = false
    private var steamSetupTask: Task<Void, Never>?
    private var steamInstallerProcess: Process?
    private var steamOpenTask: Task<Void, Never>?
    private var openingRuntime: ContainerSteamRuntime?
    private var setupRuntime: ContainerSteamRuntime?
    @Published private(set) var steamNeedsRecovery = false
    private var recoveryMonitor: Task<Void, Never>?
    private var recoveryBottle: URL?
    private var recoveryLogBaseline: UInt64 = 0

    func cancelPendingBundledWineLaunches() {
        recoveryMonitor?.cancel()
        steamNeedsRecovery = false
        if case .bundledWine = openingRuntime { steamOpenTask?.cancel() }
        if case .bundledWine = setupRuntime { steamSetupTask?.cancel() }
    }

    var onInstallationFinished: ((Int) -> Void)?

    private struct InstallTrackingState {
        var hasSeenManifest = false
        var lastValidSnapshot: SteamInstallSnapshot?
    }

    private let service: ContainerSteamService
    private let monitor: SteamInstallMonitor
    private var observations: [Int: SteamInstallObservation] = [:]
    private var observationTasks: [Int: Task<Void, Never>] = [:]
    private var observationTimeoutTasks: [Int: Task<Void, Never>] = [:]
    private var transientMissingTasks: [Int: Task<Void, Never>] = [:]
    private var trackingStates: [Int: InstallTrackingState] = [:]
    private var steamOverrides: [String: URL]
    private let missingManifestTimeout: Duration
    private let transientManifestTimeout: Duration
    private let pollInterval: Duration

    init(
        service: ContainerSteamService = ContainerSteamService(),
        monitor: SteamInstallMonitor = SteamInstallMonitor(),
        missingManifestTimeout: Duration = .seconds(45),
        transientManifestTimeout: Duration = .seconds(10),
        pollInterval: Duration = .seconds(1)
    ) {
        self.service = service
        self.monitor = monitor
        self.missingManifestTimeout = missingManifestTimeout
        self.transientManifestTimeout = transientManifestTimeout
        self.pollInterval = pollInterval
        self.steamOverrides = Self.loadOverrides()
    }

    var installation: ContainerSteamInstallation? {
        detection?.installation
    }

    var isReady: Bool {
        installation != nil
    }

    func cancelSteamDownload() {
        guard steamSetupDownloading else { return }
        steamSetupTask?.cancel()
    }

    func installSteamClient(
        in bottle: URL,
        using runtime: ContainerSteamRuntime,
        installerURL: URL? = nil,
        onInstalled: @escaping @MainActor (URL) -> Void
    ) {
        guard !steamSetupBusy, !steamOpening else { return }
        guard steamInstallerProcess?.isRunning != true else {
            steamSetupError = "上一个 Steam 安装程序仍在运行，请先完成或关闭它。"
            return
        }
        if service.detect(in: bottle).installation != nil {
            onInstalled(bottle)
            return
        }
        steamSetupBusy = true
        setupRuntime = runtime
        steamSetupDownloading = installerURL == nil
        steamSetupProgress = nil
        steamSetupError = nil
        steamSetupMessage = installerURL == nil ? "正在下载 Steam 安装程序…" : "正在打开 Steam 安装程序…"
        steamSetupTask = Task { [weak self] in
            guard let self else { return }
            var downloadedInstaller: URL?
            var installerProcess: Process?
            defer {
                // Do not remove files while an installer may still need them.
                if let downloadedInstaller {
                    let directory = downloadedInstaller.deletingLastPathComponent()
                    if let installerProcess, installerProcess.isRunning {
                        installerProcess.terminationHandler = { _ in
                            try? FileManager.default.removeItem(at: directory)
                        }
                    }
                    if installerProcess?.isRunning != true {
                        try? FileManager.default.removeItem(at: directory)
                    }
                }
                steamSetupBusy = false
                steamSetupDownloading = false
                steamSetupTask = nil
                setupRuntime = nil
            }
            do {
                let installer: URL
                if let installerURL {
                    installer = installerURL
                } else {
                    installer = try await SteamInstallerDownload.download(status: { [self] message in
                        Task { @MainActor in
                            guard self.steamSetupDownloading else { return }
                            self.steamSetupMessage = message
                        }
                    }) { [self] value in
                        Task { @MainActor in
                            guard self.steamSetupDownloading else { return }
                            self.steamSetupProgress = value
                        }
                    }
                    downloadedInstaller = installer
                }
                try Task.checkCancellation()
                steamSetupDownloading = false
                steamSetupProgress = nil
                steamSetupMessage = "正在准备 Steam 中文字体…"
                try await service.prepareChineseFonts(in: bottle, using: runtime)
                try Task.checkCancellation()
                installerProcess = try service.launchInstaller(at: installer, in: bottle, using: runtime)
                steamInstallerProcess = installerProcess
                steamSetupMessage = "请在 Steam 安装窗口中完成安装，完成后将自动刷新。"
                var exitedWithoutInstallation = 0
                for _ in 0..<450 {
                    try await Task.sleep(for: .seconds(2))
                    if service.detect(in: bottle).installation != nil,
                       installerProcess?.isRunning != true {
                        steamSetupMessage = "Steam 已安装"
                        steamSetupProgress = 1
                        onInstalled(bottle)
                        return
                    }
                    if let installerProcess, !installerProcess.isRunning,
                       installerProcess.terminationStatus != 0 {
                        throw NSError(domain: "SteamSetup", code: Int(installerProcess.terminationStatus),
                                      userInfo: [NSLocalizedDescriptionKey: "Steam 安装程序已退出（\(installerProcess.terminationStatus)）。可以重试或选择本地安装包。"])
                    }
                    if installerProcess?.isRunning != true {
                        exitedWithoutInstallation += 1
                        if exitedWithoutInstallation >= 15 { break }
                    }
                }
                steamSetupMessage = nil
                steamSetupError = "尚未检测到 Steam 安装完成。请完成安装后刷新；若选择了自定义目录，请在游戏库设置中选择 Steam 路径。"
            } catch {
                steamSetupMessage = nil
                if Task.isCancelled {
                    steamSetupError = "已取消 Steam 准备或安装。可以重试，或选择本地 SteamSetup.exe。"
                } else {
                    steamSetupError = "Steam 安装未完成：\(error.localizedDescription)"
                }
            }
        }
    }

    /// Refresh the client without discarding active game-download observers
    /// when the library reloads in the same container.
    func refreshClientDetection(bottleURL: URL?, legacyOverride: URL? = nil) {
        guard let bottleURL,
              detection?.bottleURL.standardizedFileURL == bottleURL.standardizedFileURL else {
            refresh(bottleURL: bottleURL, legacyOverride: legacyOverride)
            return
        }
        let override = steamOverrides[Self.bottleKey(bottleURL)] ?? legacyOverride
        detection = service.detect(in: bottleURL, steamOverride: override)
    }

    func refresh(bottleURL: URL?, legacyOverride: URL? = nil) {
        if recoveryBottle?.standardizedFileURL != bottleURL?.standardizedFileURL {
            recoveryMonitor?.cancel()
            recoveryBottle = nil
            steamNeedsRecovery = false
        }
        stopObservingAll()
        snapshots.removeAll()
        errorMessage = nil

        guard let bottleURL else {
            detection = nil
            return
        }

        let key = Self.bottleKey(bottleURL)
        let override = steamOverrides[key] ?? legacyOverride
        detection = service.detect(in: bottleURL, steamOverride: override)

        if let installation {
            for library in installation.libraries {
                for appID in library.installedAppIDs {
                    snapshots[appID] = monitor.status(
                        for: appID,
                        in: installation.libraries.compactMap(\.steamAppsURL)
                    )
                }
            }
        }
    }

    func setSteamOverride(_ url: URL, for bottleURL: URL) {
        steamOverrides[Self.bottleKey(bottleURL)] = url.standardizedFileURL
        Self.saveOverrides(steamOverrides)
        refresh(bottleURL: bottleURL)
    }

    func snapshot(for appID: Int) -> SteamInstallSnapshot? {
        snapshots[appID]
    }

    func openSteam(crossOverAppURL: URL) {
        openSteam(using: .crossOver(crossOverAppURL))
    }

    func openSteam(using runtime: ContainerSteamRuntime, onFailure: ((String) -> Void)? = nil) {
        guard !steamOpening, !steamSetupBusy else { return }
        errorMessage = nil
        guard let installation else {
            errorMessage = String(
                localized: "Steam was not found in the selected Windows games container."
            )
            onFailure?(errorMessage!)
            return
        }

        steamOpening = true
        recoveryMonitor?.cancel()
        steamNeedsRecovery = false
        openingRuntime = runtime
        steamOpenTask = Task {
            defer { steamOpening = false; steamOpenTask = nil; openingRuntime = nil }
            do {
                try await service.prepareChineseFonts(in: installation.bottleURL, using: runtime)
                try Task.checkCancellation()
                let log = SteamBootstrapRecovery.logURL(in: installation.steamRootURL)
                let baseline = SteamBootstrapRecovery.size(of: log)
                try service.openSteam(in: installation, using: runtime)
                if case .bundledWine = runtime { watchBootstrap(installation: installation, initialSize: baseline) }
            } catch is CancellationError {
                // A deliberate Stop Wine action is not a Steam launch failure.
            } catch {
                errorMessage = error.localizedDescription
                onFailure?(error.localizedDescription)
            }
        }
    }

    private func watchBootstrap(installation: ContainerSteamInstallation, initialSize: UInt64) {
        recoveryMonitor?.cancel()
        recoveryBottle = installation.bottleURL
        recoveryLogBaseline = initialSize
        let log = SteamBootstrapRecovery.logURL(in: installation.steamRootURL)
        let root = BundledWineRuntime.installationURL.deletingLastPathComponent().path
        recoveryMonitor = Task { [weak self] in
            // Only observe this launch's new log bytes. Never act on an old Shutdown.
            var stalledSince: ContinuousClock.Instant?
            do {
                for _ in 0..<300 {
                    try await Task.sleep(for: .seconds(3))
                    guard let self, self.installation?.bottleURL == installation.bottleURL else { return }
                    let stalled = try await Task.detached(priority: .utility) {
                        guard let tail = try? SteamBootstrapRecovery.newTail(at: log, initialSize: initialSize),
                              SteamBootstrapRecovery.completedButShuttingDown(tail) else { return false }
                        let processes = try ArclumeWineStopService.snapshot(root: root, prefix: installation.bottleURL)
                        return SteamBootstrapRecovery.hasStalledBootstrapper(processes)
                    }.value
                    try Task.checkCancellation()
                    if stalled {
                        if stalledSince == nil { stalledSince = .now }
                        if ContinuousClock.now - stalledSince! >= .seconds(30) {
                            self.steamNeedsRecovery = true
                        }
                    } else {
                        stalledSince = nil
                        self.steamNeedsRecovery = false
                    }
                }
            } catch { /* Monitoring must not interrupt a healthy Steam session. */ }
        }
    }

    func recoverSteamAfterUpdate(onFailure: ((String) -> Void)? = nil) {
        guard steamNeedsRecovery, !steamOpening, !steamSetupBusy,
              let installation, installation.bottleURL == recoveryBottle,
              BundledWineRuntime.ownsStandardSteamPrefix(installation.bottleURL) else { return }
        steamNeedsRecovery = false
        recoveryMonitor?.cancel()
        steamOpening = true
        openingRuntime = .bundledWine
        errorMessage = nil
        let baseline = recoveryLogBaseline
        steamOpenTask = Task {
            defer { steamOpening = false; steamOpenTask = nil; openingRuntime = nil }
            do {
                let root = BundledWineRuntime.installationURL.deletingLastPathComponent()
                // The confirmation may have stayed open while Steam recovered.
                let stillStalled = try await Task.detached(priority: .utility) {
                    let log = SteamBootstrapRecovery.logURL(in: installation.steamRootURL)
                    let tail = try SteamBootstrapRecovery.newTail(at: log, initialSize: baseline)
                    guard SteamBootstrapRecovery.completedButShuttingDown(tail) else { return false }
                    return SteamBootstrapRecovery.hasStalledBootstrapper(
                        try ArclumeWineStopService.snapshot(root: root.path, prefix: installation.bottleURL)
                    )
                }.value
                try Task.checkCancellation()
                guard stillStalled else { return }
                try await Task.detached(priority: .userInitiated) {
                    try await ArclumeWineStopService.stop(runtimeRoot: root, prefix: installation.bottleURL)
                }.value
                try Task.checkCancellation()
                try await service.prepareChineseFonts(in: installation.bottleURL, using: .bundledWine)
                try Task.checkCancellation()
                let baseline = SteamBootstrapRecovery.size(of: SteamBootstrapRecovery.logURL(in: installation.steamRootURL))
                try service.openSteam(in: installation, using: .bundledWine)
                watchBootstrap(installation: installation, initialSize: baseline)
            } catch is CancellationError {
            } catch {
                errorMessage = "重新启动 Steam 失败：\(error.localizedDescription)"
                onFailure?(errorMessage!)
            }
        }
    }

    func install(appID: Int, crossOverAppURL: URL) {
        install(appID: appID, using: .crossOver(crossOverAppURL))
    }

    func install(appID: Int, using runtime: ContainerSteamRuntime) {
        guard let installation else {
            errorMessage = String(
                localized: "Steam was not found in the selected Windows games container."
            )
            return
        }

        do {
            try service.install(appID: appID, in: installation, using: runtime)
            snapshots[appID] = SteamInstallSnapshot(
                appID: appID,
                state: .waiting,
                phase: .queued,
                progress: 0,
                bytesDownloaded: nil,
                bytesToDownload: nil,
                bytesStaged: nil,
                bytesToStage: nil,
                rawStateFlags: nil,
                updateResult: nil,
                installDirectory: nil,
                steamAppsDirectory: nil,
                manifestURL: nil
            )
            trackingStates[appID] = InstallTrackingState()
            startObserving(appID: appID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startObserving(appID: Int) {
        guard let installation else { return }
        let directories = installation.libraries.compactMap(\.steamAppsURL)
        guard !directories.isEmpty else { return }

        observations[appID]?.cancel()
        observationTasks[appID]?.cancel()
        observationTimeoutTasks[appID]?.cancel()
        transientMissingTasks[appID]?.cancel()

        if trackingStates[appID] == nil {
            let existingSnapshot = snapshots[appID]
            trackingStates[appID] = InstallTrackingState(
                hasSeenManifest: existingSnapshot?.manifestURL != nil,
                lastValidSnapshot: existingSnapshot.flatMap(Self.validSnapshot)
            )
        }

        let observation = monitor.observe(
            appID: appID,
            in: directories,
            pollInterval: pollInterval
        )
        observations[appID] = observation
        observationTasks[appID] = Task { [weak self, weak observation] in
            guard let observation else { return }
            for await snapshot in observation.updates {
                guard let self else { return }

                self.handleObserved(snapshot, for: appID, directories: directories)
            }
        }

        let timeout = missingManifestTimeout
        observationTimeoutTasks[appID] = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }

            guard let self,
                  let pending = self.snapshots[appID],
                  pending.state == .waiting,
                  pending.manifestURL == nil else {
                return
            }

            let current = self.monitor.status(for: appID, in: directories)
            if current.state == .notInstalled {
                self.apply(current, for: appID)
            } else {
                self.handleObserved(current, for: appID, directories: directories)
            }
        }
    }

    func stopObserving(appID: Int) {
        observations.removeValue(forKey: appID)?.cancel()
        observationTasks.removeValue(forKey: appID)?.cancel()
        observationTimeoutTasks.removeValue(forKey: appID)?.cancel()
        transientMissingTasks.removeValue(forKey: appID)?.cancel()
        trackingStates.removeValue(forKey: appID)
    }

    func stopObservingAll() {
        observations.values.forEach { $0.cancel() }
        observationTasks.values.forEach { $0.cancel() }
        observationTimeoutTasks.values.forEach { $0.cancel() }
        transientMissingTasks.values.forEach { $0.cancel() }
        observations.removeAll()
        observationTasks.removeAll()
        observationTimeoutTasks.removeAll()
        transientMissingTasks.removeAll()
        trackingStates.removeAll()
    }

    deinit {
        observations.values.forEach { $0.cancel() }
        observationTasks.values.forEach { $0.cancel() }
        observationTimeoutTasks.values.forEach { $0.cancel() }
        transientMissingTasks.values.forEach { $0.cancel() }
    }

    private func handleObserved(
        _ snapshot: SteamInstallSnapshot,
        for appID: Int,
        directories: [URL]
    ) {
        var trackingState = trackingStates[appID] ?? InstallTrackingState()

        if snapshot.manifestURL != nil {
            trackingState.hasSeenManifest = true
            observationTimeoutTasks.removeValue(forKey: appID)?.cancel()
        }

        switch snapshot.state {
        case .installed, .failed:
            trackingState.lastValidSnapshot = snapshot
            transientMissingTasks.removeValue(forKey: appID)?.cancel()
            trackingStates[appID] = trackingState
            apply(snapshot, for: appID)

        case .waiting, .downloading:
            trackingState.lastValidSnapshot = snapshot
            transientMissingTasks.removeValue(forKey: appID)?.cancel()
            trackingStates[appID] = trackingState
            apply(snapshot, for: appID)

        case .unknown:
            // Steam rewrites appmanifest files in place. A partial read must not
            // erase the last trustworthy phase or make the progress jump back.
            trackingStates[appID] = trackingState
            if trackingState.lastValidSnapshot == nil,
               snapshots[appID]?.state != .waiting {
                snapshots[appID] = snapshot
            }

        case .notInstalled:
            trackingStates[appID] = trackingState
            guard trackingState.hasSeenManifest else {
                // Steam can take several seconds to create the first manifest.
                // The dedicated initial timeout owns this state transition.
                return
            }
            scheduleStableMissingCheck(appID: appID, directories: directories)
        }
    }

    private func scheduleStableMissingCheck(appID: Int, directories: [URL]) {
        guard transientMissingTasks[appID] == nil else { return }
        let timeout = transientManifestTimeout
        transientMissingTasks[appID] = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self else { return }
            self.transientMissingTasks.removeValue(forKey: appID)
            let current = self.monitor.status(for: appID, in: directories)
            if current.state == .notInstalled {
                self.apply(current, for: appID)
            } else {
                self.handleObserved(current, for: appID, directories: directories)
            }
        }
    }

    private static func validSnapshot(
        _ snapshot: SteamInstallSnapshot
    ) -> SteamInstallSnapshot? {
        switch snapshot.state {
        case .waiting, .downloading, .installed, .failed:
            return snapshot
        case .notInstalled, .unknown:
            return nil
        }
    }

    private func apply(_ snapshot: SteamInstallSnapshot, for appID: Int) {
        let wasInstalled = snapshots[appID]?.state == .installed
        snapshots[appID] = snapshot

        if snapshot.state == .installed {
            if !wasInstalled {
                onInstallationFinished?(appID)
            }
            stopObserving(appID: appID)
        } else if snapshot.state == .notInstalled || snapshot.state == .failed {
            stopObserving(appID: appID)
        } else if snapshot.manifestURL != nil {
            observationTimeoutTasks.removeValue(forKey: appID)?.cancel()
        }
    }

    private static func bottleKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func loadOverrides() -> [String: URL] {
        guard let values = UserDefaults(suiteName: suiteName)?.dictionary(forKey: "steamExecutableOverrides") as? [String: String] else {
            return [:]
        }
        return values.reduce(into: [:]) { result, item in
            result[item.key] = URL(fileURLWithPath: item.value)
        }
    }

    private static func saveOverrides(_ values: [String: URL]) {
        let serialized = values.mapValues(\.path)
        UserDefaults(suiteName: suiteName)?.set(serialized, forKey: "steamExecutableOverrides")
    }
}
