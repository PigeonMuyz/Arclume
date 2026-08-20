//
//  NativeSteamLauncher.swift
//  Procyon
//

import AppKit
import Foundation

enum NativeSteamLauncherError: Error, Equatable, LocalizedError {
    case invalidAppID(Int)
    case steamApplicationMissing
    case invalidInstallURL(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAppID(let appID):
            return L10n.format("Invalid Steam app ID: %@", String(appID))
        case .steamApplicationMissing:
            return L10n.string("Steam for macOS was not found.")
        case .invalidInstallURL(let appID):
            return L10n.format("Unable to create the Steam install URL for %@.", String(appID))
        }
    }
}

@MainActor
protocol NativeSteamLaunching {
    var applicationURL: URL? { get }
    func install(appID: Int) throws
}

@MainActor
final class WorkspaceNativeSteamLauncher: NativeSteamLaunching {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    var applicationURL: URL? {
        if let registeredURL = workspace.urlForApplication(
            withBundleIdentifier: "com.valvesoftware.steam"
        ) {
            return registeredURL.standardizedFileURL
        }

        let candidates = [
            URL(fileURLWithPath: "/Applications/Steam.app", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Steam.app", isDirectory: true),
        ]
        return candidates.first {
            fileManager.fileExists(atPath: $0.path)
        }?.standardizedFileURL
    }

    func install(appID: Int) throws {
        guard appID > 0 else {
            throw NativeSteamLauncherError.invalidAppID(appID)
        }
        guard let applicationURL else {
            throw NativeSteamLauncherError.steamApplicationMissing
        }
        guard let installURL = URL(string: "steam://install/\(appID)") else {
            throw NativeSteamLauncherError.invalidInstallURL(appID)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open(
            [installURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            if let error {
                console.error("Native Steam install request failed: \(error.localizedDescription)")
            }
        }
    }
}
