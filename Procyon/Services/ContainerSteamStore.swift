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

    func refresh(bottleURL: URL?, legacyOverride: URL? = nil) {
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
        guard let installation else {
            errorMessage = String(
                localized: "Steam was not found in the selected CrossOver bottle."
            )
            return
        }

        do {
            try service.openSteam(in: installation, using: crossOverAppURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func install(appID: Int, crossOverAppURL: URL) {
        guard let installation else {
            errorMessage = String(
                localized: "Steam was not found in the selected CrossOver bottle."
            )
            return
        }

        do {
            try service.install(appID: appID, in: installation, using: crossOverAppURL)
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
