//
//  SteamInstallMonitor.swift
//  Procyon
//

import Foundation

nonisolated enum SteamInstallState: String, Codable, Sendable {
    case notInstalled
    case waiting
    case downloading
    case installed
    case failed
    case unknown
}

nonisolated enum SteamInstallPhase: String, Codable, Sendable {
    case notInstalled
    case queued
    case preparing
    case downloading
    case validating
    case staging
    case committing
    case stopping
    case installed
    case failed
    case unknown

    var localizedTitle: String {
        switch self {
        case .notInstalled: return L10n.string("Not installed")
        case .queued: return L10n.string("Queued")
        case .preparing: return L10n.string("Preparing")
        case .downloading: return L10n.string("Downloading")
        case .validating: return L10n.string("Validating")
        case .staging: return L10n.string("Staging")
        case .committing: return L10n.string("Committing")
        case .stopping: return L10n.string("Finishing")
        case .installed: return L10n.string("Installed")
        case .failed: return L10n.string("Failed")
        case .unknown: return L10n.string("Processing")
        }
    }
}

nonisolated struct SteamInstallSnapshot: Equatable, Sendable {
    let appID: Int
    let state: SteamInstallState
    let phase: SteamInstallPhase
    /// Normalized to the range 0...1.
    let progress: Double
    let bytesDownloaded: UInt64?
    let bytesToDownload: UInt64?
    let bytesStaged: UInt64?
    let bytesToStage: UInt64?
    let rawStateFlags: UInt64?
    let updateResult: Int?
    let installDirectory: String?
    let steamAppsDirectory: URL?
    let manifestURL: URL?

    var progressPercent: Double {
        progress * 100
    }

    static func notInstalled(appID: Int) -> SteamInstallSnapshot {
        SteamInstallSnapshot(
            appID: appID,
            state: .notInstalled,
            phase: .notInstalled,
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
    }
}

nonisolated final class SteamInstallObservation: @unchecked Sendable {
    let updates: AsyncStream<SteamInstallSnapshot>

    private let pollingTask: Task<Void, Never>

    fileprivate init(
        pollInterval: Duration,
        snapshot: @escaping @Sendable () -> SteamInstallSnapshot
    ) {
        let (stream, continuation) = AsyncStream<SteamInstallSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let interval = pollInterval > .zero ? pollInterval : .milliseconds(100)
        let task = Task.detached(priority: .utility) {
            var lastSnapshot: SteamInstallSnapshot?
            while !Task.isCancelled {
                let currentSnapshot = snapshot()
                if currentSnapshot != lastSnapshot {
                    continuation.yield(currentSnapshot)
                    lastSnapshot = currentSnapshot
                }

                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
            }

            continuation.finish()
        }

        updates = stream
        pollingTask = task
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }

    func cancel() {
        pollingTask.cancel()
    }

    deinit {
        pollingTask.cancel()
    }
}

nonisolated struct SteamInstallMonitor: Sendable {
    func scan(in steamAppsDirectories: [URL]) -> [SteamInstallSnapshot] {
        var snapshots: [SteamInstallSnapshot] = []

        for steamAppsDirectory in uniqueDirectories(from: steamAppsDirectories) {
            guard let manifestURLs = try? FileManager.default.contentsOfDirectory(
                at: steamAppsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                continue
            }

            let directorySnapshots = manifestURLs
                .compactMap { manifestURL -> (Int, URL)? in
                    guard let appID = Self.appID(fromManifestURL: manifestURL) else {
                        return nil
                    }
                    return (appID, manifestURL)
                }
                .sorted { lhs, rhs in
                    if lhs.0 == rhs.0 {
                        return lhs.1.path < rhs.1.path
                    }
                    return lhs.0 < rhs.0
                }
                .map { appID, manifestURL in
                    snapshot(
                        appID: appID,
                        manifestURL: manifestURL,
                        steamAppsDirectory: steamAppsDirectory
                    )
                }

            snapshots.append(contentsOf: directorySnapshots)
        }

        return snapshots
    }

    func snapshots(for appID: Int, in steamAppsDirectories: [URL]) -> [SteamInstallSnapshot] {
        uniqueDirectories(from: steamAppsDirectories).compactMap { steamAppsDirectory in
            let manifestURL = steamAppsDirectory
                .appendingPathComponent("appmanifest_\(appID).acf", isDirectory: false)

            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                return nil
            }

            return snapshot(
                appID: appID,
                manifestURL: manifestURL,
                steamAppsDirectory: steamAppsDirectory
            )
        }
    }

    func status(for appID: Int, in steamAppsDirectories: [URL]) -> SteamInstallSnapshot {
        snapshots(for: appID, in: steamAppsDirectories).first
            ?? .notInstalled(appID: appID)
    }

    func observe(
        appID: Int,
        in steamAppsDirectories: [URL],
        pollInterval: Duration = .seconds(1)
    ) -> SteamInstallObservation {
        let directories = uniqueDirectories(from: steamAppsDirectories)
        return SteamInstallObservation(pollInterval: pollInterval) {
            status(for: appID, in: directories)
        }
    }

    private func snapshot(
        appID: Int,
        manifestURL: URL,
        steamAppsDirectory: URL
    ) -> SteamInstallSnapshot {
        guard
            let contents = try? String(contentsOf: manifestURL, encoding: .utf8),
            Self.isStructurallyValidVDF(contents),
            let appState = parseVDFToDict(from: contents)["AppState"] as? [String: Any],
            let manifestAppID = Self.parseInt(appState["appid"]),
            manifestAppID == appID,
            let stateFlags = Self.parseUInt64(appState["StateFlags"])
        else {
            return unknownSnapshot(
                appID: appID,
                manifestURL: manifestURL,
                steamAppsDirectory: steamAppsDirectory
            )
        }

        let bytesDownloaded = Self.parseOptionalUInt64(appState["BytesDownloaded"])
        let bytesToDownload = Self.parseOptionalUInt64(appState["BytesToDownload"])
        let bytesStaged = Self.parseOptionalUInt64(appState["BytesStaged"])
        let bytesToStage = Self.parseOptionalUInt64(appState["BytesToStage"])
        let updateResult = Self.parseOptionalInt(appState["UpdateResult"])

        guard bytesDownloaded.isValid,
              bytesToDownload.isValid,
              bytesStaged.isValid,
              bytesToStage.isValid,
              updateResult.isValid else {
            return unknownSnapshot(
                appID: appID,
                manifestURL: manifestURL,
                steamAppsDirectory: steamAppsDirectory
            )
        }

        let state = Self.installState(
            stateFlags: stateFlags,
            bytesDownloaded: bytesDownloaded.value,
            bytesToDownload: bytesToDownload.value,
            updateResult: updateResult.value
        )
        let phase = Self.installPhase(state: state, stateFlags: stateFlags)
        let progress = Self.progress(
            for: state,
            phase: phase,
            bytesDownloaded: bytesDownloaded.value,
            bytesToDownload: bytesToDownload.value,
            bytesStaged: bytesStaged.value,
            bytesToStage: bytesToStage.value
        )

        return SteamInstallSnapshot(
            appID: appID,
            state: state,
            phase: phase,
            progress: progress,
            bytesDownloaded: bytesDownloaded.value,
            bytesToDownload: bytesToDownload.value,
            bytesStaged: bytesStaged.value,
            bytesToStage: bytesToStage.value,
            rawStateFlags: stateFlags,
            updateResult: updateResult.value,
            installDirectory: appState["installdir"] as? String,
            steamAppsDirectory: steamAppsDirectory,
            manifestURL: manifestURL
        )
    }

    private func unknownSnapshot(
        appID: Int,
        manifestURL: URL,
        steamAppsDirectory: URL
    ) -> SteamInstallSnapshot {
        SteamInstallSnapshot(
            appID: appID,
            state: .unknown,
            phase: .unknown,
            progress: 0,
            bytesDownloaded: nil,
            bytesToDownload: nil,
            bytesStaged: nil,
            bytesToStage: nil,
            rawStateFlags: nil,
            updateResult: nil,
            installDirectory: nil,
            steamAppsDirectory: steamAppsDirectory,
            manifestURL: manifestURL
        )
    }

    private func uniqueDirectories(from directories: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return directories.compactMap { directory in
            let standardizedDirectory = directory.standardizedFileURL
            guard seenPaths.insert(standardizedDirectory.path).inserted else {
                return nil
            }
            return standardizedDirectory
        }
    }

    private static func appID(fromManifestURL manifestURL: URL) -> Int? {
        let filename = manifestURL.lastPathComponent
        let prefix = "appmanifest_"
        let suffix = ".acf"

        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else {
            return nil
        }

        let start = filename.index(filename.startIndex, offsetBy: prefix.count)
        let end = filename.index(filename.endIndex, offsetBy: -suffix.count)
        return Int(filename[start..<end])
    }

    private static func installState(
        stateFlags: UInt64,
        bytesDownloaded: UInt64?,
        bytesToDownload: UInt64?,
        updateResult: Int?
    ) -> SteamInstallState {
        if let updateResult, updateResult != 0 {
            return .failed
        }

        if stateFlags & AppStateFlag.filesCorrupt != 0 {
            return .failed
        }

        if stateFlags & AppStateFlag.uninstalled != 0 {
            return .notInstalled
        }

        if stateFlags & AppStateFlag.updatePaused != 0 {
            return .waiting
        }

        if stateFlags & AppStateFlag.activeInstallation != 0 {
            return .downloading
        }

        if let bytesDownloaded, let bytesToDownload,
           bytesToDownload > 0, bytesDownloaded > 0, bytesDownloaded < bytesToDownload {
            return .downloading
        }

        if stateFlags & AppStateFlag.updateRequired != 0 {
            return .waiting
        }

        if let bytesDownloaded, let bytesToDownload,
           bytesToDownload > 0, bytesDownloaded < bytesToDownload {
            return .waiting
        }

        if stateFlags & AppStateFlag.fullyInstalled != 0 {
            return .installed
        }

        return .unknown
    }

    private static func progress(
        for state: SteamInstallState,
        phase: SteamInstallPhase,
        bytesDownloaded: UInt64?,
        bytesToDownload: UInt64?,
        bytesStaged: UInt64?,
        bytesToStage: UInt64?
    ) -> Double {
        if state == .installed {
            return 1
        }

        if phase == .staging || phase == .committing,
           let bytesStaged,
           let bytesToStage,
           bytesToStage > 0 {
            return min(max(Double(bytesStaged) / Double(bytesToStage), 0), 1)
        }

        guard let bytesDownloaded, let bytesToDownload, bytesToDownload > 0 else {
            return 0
        }

        return min(max(Double(bytesDownloaded) / Double(bytesToDownload), 0), 1)
    }

    private static func installPhase(
        state: SteamInstallState,
        stateFlags: UInt64
    ) -> SteamInstallPhase {
        switch state {
        case .notInstalled:
            return .notInstalled
        case .installed:
            return .installed
        case .failed:
            return .failed
        case .unknown:
            return .unknown
        case .waiting:
            return .queued
        case .downloading:
            break
        }

        if stateFlags & AppStateFlag.committing != 0 { return .committing }
        if stateFlags & AppStateFlag.staging != 0 { return .staging }
        if stateFlags & AppStateFlag.validating != 0 { return .validating }
        if stateFlags & AppStateFlag.downloading != 0 { return .downloading }
        if stateFlags & AppStateFlag.updateStopping != 0 { return .stopping }
        return .preparing
    }

    private static func parseInt(_ value: Any?) -> Int? {
        guard let value = value as? String else {
            return nil
        }
        return Int(value)
    }

    private static func parseUInt64(_ value: Any?) -> UInt64? {
        guard let value = value as? String else {
            return nil
        }
        return UInt64(value)
    }

    private static func parseOptionalInt(_ value: Any?) -> (value: Int?, isValid: Bool) {
        guard let value else {
            return (nil, true)
        }
        guard let stringValue = value as? String, let parsedValue = Int(stringValue) else {
            return (nil, false)
        }
        return (parsedValue, true)
    }

    private static func parseOptionalUInt64(_ value: Any?) -> (value: UInt64?, isValid: Bool) {
        guard let value else {
            return (nil, true)
        }
        guard let stringValue = value as? String, let parsedValue = UInt64(stringValue) else {
            return (nil, false)
        }
        return (parsedValue, true)
    }

    private static func isStructurallyValidVDF(_ contents: String) -> Bool {
        let scalars = Array(contents.unicodeScalars)
        var braceDepth = 0
        var hasBraces = false
        var isInString = false
        var isEscaped = false
        var isInLineComment = false
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if isInLineComment {
                if scalar == "\n" || scalar == "\r" {
                    isInLineComment = false
                }
                index += 1
                continue
            }

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if scalar == "\\" {
                    isEscaped = true
                } else if scalar == "\"" {
                    isInString = false
                }
                index += 1
                continue
            }

            if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "/" {
                isInLineComment = true
                index += 2
                continue
            }

            switch scalar {
            case "\"":
                isInString = true
            case "{":
                braceDepth += 1
                hasBraces = true
            case "}":
                braceDepth -= 1
                if braceDepth < 0 {
                    return false
                }
            default:
                break
            }

            index += 1
        }

        return hasBraces && braceDepth == 0 && !isInString
    }
}

nonisolated private enum AppStateFlag {
    static let uninstalled: UInt64 = 1
    static let updateRequired: UInt64 = 1 << 1
    static let fullyInstalled: UInt64 = 1 << 2
    static let filesCorrupt: UInt64 = 1 << 7
    static let updatePaused: UInt64 = 1 << 9

    static let validating: UInt64 = 1 << 17
    static let downloading: UInt64 = 1 << 20
    static let staging: UInt64 = 1 << 21
    static let committing: UInt64 = 1 << 22
    static let updateStopping: UInt64 = 1 << 23

    static let activeInstallation: UInt64 =
        (1 << 8) |   // UpdateRunning
        (1 << 10) |  // UpdateStarted
        (1 << 16) |  // Reconfiguring
        (1 << 17) |  // Validating
        (1 << 18) |  // AddingFiles
        (1 << 19) |  // Preallocating
        (1 << 20) |  // Downloading
        (1 << 21) |  // Staging
        (1 << 22) |  // Committing
        (1 << 23)    // UpdateStopping
}
