//
//  OnlineGame.swift
//  Procyon
//

import Foundation

enum OnlineGameMode {
    static let jx3GameID = "online.jx3.flagship"
    static let jx3ClientName = "JX3ClientX64.exe"
    static let jx3LauncherName = "SeasunGame.exe"
    static let defaultBottleName = "Games"
    static let jx3GameDirectoryComponents = [
        "drive_c", "SeasunGame", "Game", "JX3", "bin", "zhcn_hd"
    ]
    static let onlineGraphicsBackends: DropdownOptions = [
        (id: "d3dmetal3", label: "D3DMetal 3"),
        (id: "d3dmetal4", label: "D3DMetal 4 Beta 2")
    ]
    static let defaultGraphicsBackend = "d3dmetal4"

    static var isEnabled: Bool {
        ProcyonMode.persisted?.isOnlineGameMode == true
    }

    static func isJX3(_ game: Game) -> Bool {
        isEnabled && game.id == jx3GameID
    }

    static func applyDefaultRuntimePreferences(to options: GameOptions) {
        guard isEnabled else { return }
        if !onlineGraphicsBackends.contains(where: { $0.id == options.cxGraphicsBackend }) {
            options.cxGraphicsBackend = defaultGraphicsBackend
        }
        // The same persisted choice is consumed by CrossOver and standalone
        // Wine 11. Wine 11 resolves the selected D3DMetal version inside its
        // own runtime instead of injecting CrossOver files into the bottle.
        options.d3dMtl4Enabled = options.cxGraphicsBackend == "d3dmetal4"
    }

    /// Preserve the same per-client options that users already configured
    /// before the game was discovered by Procyon 剑网3模式.
    static func gameOptionsIdentifier(for game: Game) -> String {
        guard isJX3(game), let executableURL = game.appExeURL else {
            return game.steamAppID != 0 ? String(game.steamAppID) : game.id
        }
        return executableURL.path(percentEncoded: false)
    }
}

struct OnlineGameInstallation: Sendable {
    let clientURL: URL?
    let launcherURL: URL?
    let workingDirectoryURL: URL?

    init(
        clientURL: URL?,
        launcherURL: URL?,
        workingDirectoryURL: URL? = nil
    ) {
        self.clientURL = clientURL
        self.launcherURL = launcherURL
        self.workingDirectoryURL = workingDirectoryURL
    }

    /// A client executable alone is not a supported installation: the game
    /// must be entered through SeasunGame.exe.
    var isDetected: Bool { launcherURL != nil }

    /// Keep login, patching, region selection, and anti-cheat setup inside the
    /// launcher's normal flow instead of bypassing it with the client EXE.
    var preferredLaunchURL: URL? { launcherURL }

    /// The launcher executable is installed one level above the versioned
    /// CEF payload. Wine must inherit that payload directory as its current
    /// directory or CefViewWing cannot find its Qt/CEF resources.
    var preferredWorkingDirectory: URL? {
        workingDirectoryURL ?? launcherURL?.deletingLastPathComponent()
    }

    var preferredLaunchArguments: [String] { [] }

    /// The selected executable is the only trustworthy process to track.
    /// SeasunGame.exe is a launcher and can exit while the client never starts.
    var preferredProcessNames: [String] {
        preferredLaunchURL.map { [$0.lastPathComponent] } ?? []
    }
}

enum OnlineGameDiscovery {
    static func selectedBottleURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL { return url }
        return URL(fileURLWithPath: trimmed)
    }

    static func jx3GameDirectory(in bottleURL: URL) -> URL? {
        let expectedURL = OnlineGameMode.jx3GameDirectoryComponents.reduce(bottleURL) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        if (try? expectedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return expectedURL
        }

        let clientURL = jx3Installation(in: bottleURL).clientURL
        return clientURL?.deletingLastPathComponent()
    }

    /// The JX3 client keeps its runtime DLLs in the sibling `bin64` folder,
    /// not in the `zhcn_hd` content directory itself.
    static func jx3BinaryDirectory(in bottleURL: URL) -> URL? {
        guard let gameDirectoryURL = jx3GameDirectory(in: bottleURL) else {
            return nil
        }
        return gameDirectoryURL.appendingPathComponent("bin64", isDirectory: true)
    }

    static func jx3Installation(in bottleURL: URL) -> OnlineGameInstallation {
        let driveC = bottleURL.appendingPathComponent("drive_c", isDirectory: true)
        guard FileManager.default.fileExists(atPath: driveC.path) else {
            return OnlineGameInstallation(
                clientURL: nil,
                launcherURL: nil,
                workingDirectoryURL: nil
            )
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: driveC,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return OnlineGameInstallation(
                clientURL: nil,
                launcherURL: nil,
                workingDirectoryURL: nil
            )
        }

        var clientURL: URL?
        var launcherURL: URL?
        for case let url as URL in enumerator {
            guard
                let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true,
                values.isSymbolicLink != true
            else {
                continue
            }
            switch url.lastPathComponent.lowercased() {
            case OnlineGameMode.jx3ClientName.lowercased():
                clientURL = clientURL ?? url
            case OnlineGameMode.jx3LauncherName.lowercased():
                launcherURL = launcherURL ?? url
            default:
                break
            }
            if clientURL != nil && launcherURL != nil { break }
        }
        return OnlineGameInstallation(
            clientURL: clientURL,
            launcherURL: launcherURL,
            workingDirectoryURL: preferredWorkingDirectory(for: launcherURL)
        )
    }

    private static func preferredWorkingDirectory(for launcherURL: URL?) -> URL? {
        guard let launcherURL else { return nil }
        let launcherRoot = launcherURL.deletingLastPathComponent()
        let fileManager = FileManager.default

        // Seasun's current launcher layout keeps one or more versioned CEF
        // payloads beside SeasunGame.exe. Prefer the newest complete payload
        // so stale updater directories are not selected accidentally.
        let versionDirectories = (try? fileManager.contentsOfDirectory(
            at: launcherRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter { directory in
            guard directory.lastPathComponent.lowercased().hasPrefix("seasungame_") else {
                return false
            }
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return false
            }
            return fileManager.fileExists(
                atPath: directory.appendingPathComponent("CefViewWing.exe").path
            ) && fileManager.fileExists(
                atPath: directory.appendingPathComponent("libcef.dll").path
            )
        } ?? []

        return versionDirectories.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
        }.first ?? launcherRoot
    }

    static func games(in bottleURL: URL) -> [Game] {
        let installation = jx3Installation(in: bottleURL)
        guard installation.isDetected else { return [] }

        // Metadata stays deliberately empty until it is supplied by the game
        // maintainer. This is just a local executable identity, not Steam data.
        var game = Game.emptyGame
        game.id = OnlineGameMode.jx3GameID
        game.name = "剑网 3 启动器"
        game.type = "launcher"
        game.isNative = false
        game.isCustom = false
        game.isInstalled = true
        game.downloadProgress = 100
        game.platforms = Platforms(windows: true, mac: false, linux: false)
        game.appExeURL = installation.preferredLaunchURL
        game.appNames = installation.preferredProcessNames
        OnlineGamePresentationStore.apply(
            OnlineGamePresentationStore.presentation(for: game.id),
            to: &game
        )
        return [game]
    }
}
