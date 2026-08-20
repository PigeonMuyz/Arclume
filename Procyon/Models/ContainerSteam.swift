//
//  ContainerSteam.swift
//  Procyon
//

import Foundation

enum ContainerSteamDetectionStatus: String, Codable, CaseIterable, Sendable {
    case notFound
    case executableFound
    case configured
    case ready
}

enum ContainerSteamDiscoverySource: String, Codable, Sendable {
    case standard
    case override
}

struct ContainerSteamUser: Identifiable, Codable, Equatable, Sendable {
    let steamID: String
    let accountName: String
    let personaName: String
    let rememberPassword: Bool
    let mostRecent: Bool
    let timestamp: Int?

    var id: String { steamID }
}

struct ContainerSteamLibrary: Identifiable, Codable, Equatable, Sendable {
    let identifier: String
    let label: String?
    let windowsPath: String
    let hostURL: URL?
    let installedAppIDs: Set<Int>

    var id: String {
        hostURL?.standardizedFileURL.path ?? windowsPath.lowercased()
    }

    var steamAppsURL: URL? {
        hostURL?.appendingPathComponent("steamapps", isDirectory: true)
    }
}

struct ContainerSteamInstallation: Identifiable, Codable, Equatable, Sendable {
    let bottleURL: URL
    let steamRootURL: URL
    let steamExecutableURL: URL
    let discoverySource: ContainerSteamDiscoverySource
    let users: [ContainerSteamUser]
    let libraries: [ContainerSteamLibrary]
    let hasLoginUsersConfiguration: Bool
    let hasLibraryFoldersConfiguration: Bool

    var id: String { bottleURL.standardizedFileURL.path }

    nonisolated var configURL: URL {
        steamRootURL.appendingPathComponent("config", isDirectory: true)
    }

    var activeUser: ContainerSteamUser? {
        users.sorted { lhs, rhs in
            if lhs.mostRecent != rhs.mostRecent { return lhs.mostRecent }
            if lhs.rememberPassword != rhs.rememberPassword { return lhs.rememberPassword }
            if lhs.timestamp != rhs.timestamp { return (lhs.timestamp ?? 0) > (rhs.timestamp ?? 0) }
            return lhs.steamID < rhs.steamID
        }.first
    }

    var hasRememberedUser: Bool {
        users.contains(where: \.rememberPassword)
    }
}

struct ContainerSteamDetection: Equatable, Sendable {
    let bottleURL: URL
    let status: ContainerSteamDetectionStatus
    let installation: ContainerSteamInstallation?
    let searchedExecutableURLs: [URL]

    var canLaunchSteam: Bool { installation != nil }
}

enum ContainerGameInstallationState: String, Codable, CaseIterable, Sendable {
    case notInstalled
    case queued
    case downloading
    case installed
    case updateRequired
    case damaged
}

struct ContainerGameInstallation: Identifiable, Codable, Equatable, Sendable {
    let appID: Int
    let bottleURL: URL
    let state: ContainerGameInstallationState
    let library: ContainerSteamLibrary?
    let manifestURL: URL?
    let installDirectoryURL: URL?
    let bytesDownloaded: Int64?
    let bytesToDownload: Int64?

    var id: String {
        "\(bottleURL.standardizedFileURL.path)#\(appID)"
    }

    var progress: Double? {
        if state == .installed {
            return 1
        }
        guard let bytesDownloaded, let bytesToDownload, bytesToDownload > 0 else {
            return state == .notInstalled ? 0 : nil
        }
        return min(max(Double(bytesDownloaded) / Double(bytesToDownload), 0), 1)
    }
}
