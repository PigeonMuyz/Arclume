//
//  NativeSteamStore.swift
//  Procyon
//

import Combine
import Foundation

/// Continuously reflects appmanifest changes made by the native macOS Steam
/// client. ContainerSteamStore owns the equivalent lifecycle for CrossOver.
@MainActor
final class NativeSteamStore: ObservableObject {
    @Published private(set) var snapshots: [Int: SteamInstallSnapshot] = [:]
    @Published private(set) var libraryURLs: [URL] = []
    @Published var errorMessage: String?

    var onInstallationFinished: ((Int) -> Void)?

    private let monitor: SteamInstallMonitor
    private let launcher: any NativeSteamLaunching
    private let missingManifestTimeout: Duration
    private let pollInterval: Duration
    private var pollingTask: Task<Void, Never>?
    private var initialManifestTimeoutTasks: [Int: Task<Void, Never>] = [:]
    private var pendingManifestAppIDs = Set<Int>()
    private var missingPollCounts: [Int: Int] = [:]

    init(
        monitor: SteamInstallMonitor = SteamInstallMonitor(),
        launcher: (any NativeSteamLaunching)? = nil,
        missingManifestTimeout: Duration = .seconds(45),
        pollInterval: Duration = .seconds(1)
    ) {
        self.monitor = monitor
        self.launcher = launcher ?? WorkspaceNativeSteamLauncher()
        self.missingManifestTimeout = missingManifestTimeout > .zero
            ? missingManifestTimeout
            : .milliseconds(100)
        self.pollInterval = pollInterval > .zero ? pollInterval : .milliseconds(100)
    }

    var isReady: Bool {
        launcher.applicationURL != nil
    }

    func refresh(installation: NativeSteamInstallation?) {
        let directories = uniqueDirectories(installation?.libraryURLs ?? [])
        guard directories != libraryURLs || pollingTask == nil else { return }

        pollingTask?.cancel()
        pollingTask = nil
        cancelInitialManifestTimeouts()
        libraryURLs = directories
        snapshots = [:]
        pendingManifestAppIDs = []
        missingPollCounts = [:]

        guard !directories.isEmpty else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.poll(notifyCompletions: false)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.pollInterval)
                } catch {
                    return
                }
                await self.poll(notifyCompletions: true)
            }
        }
    }

    func snapshot(for appID: Int) -> SteamInstallSnapshot? {
        snapshots[appID]
    }

    func install(appID: Int) {
        errorMessage = nil
        do {
            try launcher.install(appID: appID)
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
            pendingManifestAppIDs.insert(appID)
            missingPollCounts[appID] = 0
            scheduleInitialManifestTimeout(appID: appID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        cancelInitialManifestTimeouts()
        libraryURLs = []
        snapshots = [:]
        pendingManifestAppIDs = []
        missingPollCounts = [:]
    }

    deinit {
        pollingTask?.cancel()
        initialManifestTimeoutTasks.values.forEach { $0.cancel() }
    }

    private func poll(notifyCompletions: Bool) async {
        let monitor = monitor
        let directories = libraryURLs
        let scanned = await Task.detached(priority: .utility) {
            monitor.scan(in: directories)
        }.value
        guard !Task.isCancelled else { return }

        var nextSnapshots: [Int: SteamInstallSnapshot] = [:]
        for snapshot in scanned {
            if pendingManifestAppIDs.remove(snapshot.appID) != nil {
                initialManifestTimeoutTasks.removeValue(forKey: snapshot.appID)?.cancel()
            }
            let candidate: SteamInstallSnapshot
            if snapshot.state == .unknown,
               let previous = snapshots[snapshot.appID],
               previous.state != .unknown {
                // Steam sometimes exposes a partially rewritten manifest. Keep
                // the last trustworthy value rather than flashing back to 0%.
                candidate = previous
            } else {
                candidate = snapshot
            }

            if let existing = nextSnapshots[snapshot.appID] {
                nextSnapshots[snapshot.appID] = preferred(existing, candidate)
            } else {
                nextSnapshots[snapshot.appID] = candidate
            }
            missingPollCounts.removeValue(forKey: snapshot.appID)
        }

        // Atomic replacements can make a manifest disappear for a fraction of
        // a second. Require three consecutive missing polls before dropping the
        // last snapshot so the progress bar remains monotonic and stable.
        for (appID, previous) in snapshots where nextSnapshots[appID] == nil {
            if pendingManifestAppIDs.contains(appID) {
                // Steam may need time to launch and show its install confirmation
                // before it creates appmanifest_<id>.acf. The dedicated initial
                // timeout owns this state; transient-missing debounce only starts
                // after a manifest has been observed at least once.
                nextSnapshots[appID] = previous
                continue
            }
            let missingCount = (missingPollCounts[appID] ?? 0) + 1
            missingPollCounts[appID] = missingCount
            if missingCount < 3 {
                nextSnapshots[appID] = previous
            } else {
                missingPollCounts.removeValue(forKey: appID)
            }
        }

        let previousSnapshots = snapshots
        if nextSnapshots != snapshots {
            snapshots = nextSnapshots
        }

        guard notifyCompletions else { return }
        for (appID, snapshot) in nextSnapshots where snapshot.state == .installed {
            if previousSnapshots[appID]?.state != .installed {
                onInstallationFinished?(appID)
            }
        }
    }

    private func scheduleInitialManifestTimeout(appID: Int) {
        initialManifestTimeoutTasks.removeValue(forKey: appID)?.cancel()
        let timeout = missingManifestTimeout
        initialManifestTimeoutTasks[appID] = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self,
                  self.pendingManifestAppIDs.remove(appID) != nil
            else {
                return
            }
            self.initialManifestTimeoutTasks.removeValue(forKey: appID)
            self.missingPollCounts.removeValue(forKey: appID)
            if self.snapshots[appID]?.manifestURL == nil {
                self.snapshots.removeValue(forKey: appID)
            }
        }
    }

    private func cancelInitialManifestTimeouts() {
        initialManifestTimeoutTasks.values.forEach { $0.cancel() }
        initialManifestTimeoutTasks = [:]
    }

    private func preferred(
        _ lhs: SteamInstallSnapshot,
        _ rhs: SteamInstallSnapshot
    ) -> SteamInstallSnapshot {
        let priority: (SteamInstallState) -> Int = { state in
            switch state {
            case .downloading: return 6
            case .waiting: return 5
            case .failed: return 4
            case .installed: return 3
            case .unknown: return 2
            case .notInstalled: return 1
            }
        }
        return priority(rhs.state) > priority(lhs.state) ? rhs : lhs
    }

    private func uniqueDirectories(_ directories: [URL]) -> [URL] {
        var seen = Set<String>()
        return directories.compactMap { directory in
            let standardized = directory.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return nil }
            return standardized
        }
    }
}
