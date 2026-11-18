//
//  OnlineGame.swift
//  Arclume
//

import Foundation
import Metal

enum OnlineGameMode {
    static let jx3GameID = "online.jx3.flagship"
    nonisolated static let jx3ClientName = "JX3ClientX64.exe"
    nonisolated static let jx3LauncherName = "SeasunGame.exe"
    static let defaultBottleName = "Games"
    nonisolated static let jx3GameDirectoryComponents = [
        "drive_c", "SeasunGame", "Game", "JX3", "bin", "zhcn_hd"
    ]
    private static let allOnlineGraphicsBackends: DropdownOptions = [
        (id: "d3dmetal4", label: "D3DMetal 4 Beta 3"),
        (id: "dxmt", label: "DXMT 0.80")
    ]
    nonisolated static let d3dMetal4RequirementMessage =
        "D3DMetal 4 Beta 3 需要 macOS 26 和支持 Metal 4 的 GPU，当前 Mac 无法使用。"

    /// D3DMetal 4 requires the Metal 4 GPU family. Checking the actual
    /// default device is more reliable than inferring support from the Mac
    /// model name, and also handles future Apple Silicon generations.
    static var supportsD3DMetal4: Bool {
        guard #available(macOS 26.0, *),
              let device = MTLCreateSystemDefaultDevice()
        else {
            return false
        }
        return device.supportsFamily(.metal4)
    }

    static var onlineGraphicsBackends: DropdownOptions {
        graphicsBackends(supportingD3DMetal4: supportsD3DMetal4)
    }

    static var defaultGraphicsBackend: String {
        defaultGraphicsBackend(supportingD3DMetal4: supportsD3DMetal4)
    }

    nonisolated static func graphicsBackends(
        supportingD3DMetal4: Bool
    ) -> DropdownOptions {
        supportingD3DMetal4
            ? allOnlineGraphicsBackends
            : allOnlineGraphicsBackends.filter { $0.id == "dxmt" }
    }

    nonisolated static func defaultGraphicsBackend(
        supportingD3DMetal4: Bool
    ) -> String {
        "d3dmetal4"
    }

    nonisolated static func resolvedGraphicsBackend(
        _ requestedBackend: String,
        supportingD3DMetal4: Bool
    ) -> String {
        requestedBackend == "dxmt" ? "dxmt" : "d3dmetal4"
    }

    static var isEnabled: Bool {
        false // A single library now owns all games; legacy mode values are ignored.
    }

    static func isJX3(_ game: Game) -> Bool {
        game.id == jx3GameID
    }

    /// Library presentation must not change which container owns the game.
    /// In standard mode selectedBottle belongs to Steam, not to JX3.
    static func jx3BottleURL(appGlobals: AppGlobals) -> URL? {
        if isEnabled {
            return OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle)
        }
        return OnlineGameRuntimeKind.configuredBottleURL(for: .selected())
    }

    static func applyDefaultRuntimePreferences(to options: GameOptions) {
        let resolvedBackend = resolvedGraphicsBackend(
            options.cxGraphicsBackend,
            supportingD3DMetal4: supportsD3DMetal4
        )
        options.cxGraphicsBackend = resolvedBackend
        // Both launch routes consume the same persisted graphics choice.
        options.d3dMtl4Enabled = resolvedBackend == "d3dmetal4"
    }

    /// Preserve the same per-client options that users already configured
    /// before the game was discovered by the Arclume JX3 mode.
    static func gameOptionsIdentifier(for game: Game) -> String {
        guard isJX3(game), let executableURL = game.appExeURL else {
            return game.steamAppID != 0 ? String(game.steamAppID) : game.id
        }
        return executableURL.path(percentEncoded: false)
    }
}

nonisolated struct OnlineGameInstallation: Sendable {
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

    /// Automatic discovery continues to require the normal launcher.
    var isDetected: Bool { launcherURL != nil }

    /// The default entry point retains the launcher's login and update flow.
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

    struct LaunchTarget: Sendable {
        let executableURL: URL
        let arguments: [String]
        let workingDirectoryURL: URL?
    }

    // Zeratulag-'s documented client CLI (2024-02-07):
    // https://www.sina.cn/news/detail/4998898374149137.html
    static let directClientArgument = "DOTNOTSTARTGAMEBYJX3CLIENT.EXE"

    func launchTarget(skipLauncher: Bool, clientArguments: [String] = []) -> LaunchTarget? {
        if skipLauncher {
            guard let clientURL else { return nil }
            return LaunchTarget(
                executableURL: clientURL,
                arguments: [Self.directClientArgument] + clientArguments.filter {
                    $0.caseInsensitiveCompare(Self.directClientArgument) != .orderedSame
                },
                workingDirectoryURL: clientURL.deletingLastPathComponent()
            )
        }
        guard let preferredLaunchURL else { return nil }
        return LaunchTarget(
            executableURL: preferredLaunchURL,
            arguments: preferredLaunchArguments,
            workingDirectoryURL: preferredWorkingDirectory
        )
    }
}

enum OnlineGameDiscovery {
    static func selectedBottleURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL { return url }
        return URL(fileURLWithPath: trimmed)
    }

    nonisolated static func defaultJX3GameDirectory(in bottleURL: URL) -> URL {
        OnlineGameMode.jx3GameDirectoryComponents.reduce(bottleURL) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
    }

    nonisolated static func jx3GameDirectory(
        in bottleURL: URL,
        installation: OnlineGameInstallation? = nil
    ) -> URL? {
        if let installation, let directory = discoveredJX3GameDirectory(in: installation) {
            return directory
        }

        let expectedURL = defaultJX3GameDirectory(in: bottleURL)
        if (try? expectedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return expectedURL
        }

        guard installation == nil else { return nil }
        return discoveredJX3GameDirectory(in: jx3Installation(in: bottleURL))
    }

    nonisolated private static func discoveredJX3GameDirectory(in installation: OnlineGameInstallation) -> URL? {
        if let binaryDirectory = installation.clientURL?.deletingLastPathComponent() {
            let clientDirectory = binaryDirectory.lastPathComponent.caseInsensitiveCompare("bin64") == .orderedSame
                ? binaryDirectory.deletingLastPathComponent() : binaryDirectory
            if (try? clientDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return clientDirectory
            }
        }
        guard let launcherURL = installation.launcherURL else { return nil }
        let launcherRelativeURL = OnlineGameMode.jx3GameDirectoryComponents.dropFirst(2)
            .reduce(launcherURL.deletingLastPathComponent()) {
                $0.appendingPathComponent($1, isDirectory: true)
            }
        return (try? launcherRelativeURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            ? launcherRelativeURL : nil
    }

    /// The JX3 client keeps its runtime DLLs in the sibling `bin64` folder,
    /// not in the `zhcn_hd` content directory itself.
    static func jx3BinaryDirectory(in bottleURL: URL) -> URL? {
        guard let gameDirectoryURL = jx3GameDirectory(in: bottleURL) else {
            return nil
        }
        return gameDirectoryURL.appendingPathComponent("bin64", isDirectory: true)
    }

    nonisolated static func jx3Installation(in bottleURL: URL) -> OnlineGameInstallation {
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

    nonisolated private static func preferredWorkingDirectory(for launcherURL: URL?) -> URL? {
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
        games(from: jx3Installation(in: bottleURL))
    }

    static func games(from installation: OnlineGameInstallation) -> [Game] {
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
