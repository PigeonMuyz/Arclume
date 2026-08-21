//
//  SteamIdentity.swift
//  Procyon
//

import Foundation

nonisolated enum SteamClientKind: String, Hashable, Sendable {
    case native
    case container
}

nonisolated enum SteamIdentitySource: Hashable, Sendable {
    case native
    case crossOverBottle(URL)
    case winePrefix(URL)

    var cacheKey: String {
        switch self {
        case .native:
            return "native"
        case .crossOverBottle(let bottleURL):
            return "bottle:\(bottleURL.standardizedFileURL.path)"
        case .winePrefix(let prefixURL):
            return "wine-prefix:\(prefixURL.standardizedFileURL.path)"
        }
    }
}

nonisolated struct SteamClientSession: Identifiable, Hashable, Sendable {
    let identity: SteamIdentity
    let steamRootURL: URL
    let source: SteamIdentitySource
    let clientKind: SteamClientKind

    var id: String { cacheKey }

    var cacheKey: String {
        [
            clientKind.rawValue,
            source.cacheKey,
            identity.steamID,
            steamRootURL.standardizedFileURL.path,
        ].joined(separator: "#")
    }
}

nonisolated struct SteamIdentity: Identifiable, Hashable, Sendable {
    let steamID: String
    let accountName: String
    let personaName: String
    let rememberPassword: Bool
    let mostRecent: Bool
    let timestamp: Int?
    let source: SteamIdentitySource
    let avatarURL: URL?

    var id: String { "\(source.cacheKey)#\(steamID)" }

    var cacheKey: String { id }

    var displayName: String {
        let persona = personaName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persona.isEmpty { return persona }
        let account = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return account.isEmpty ? steamID : account
    }
}

nonisolated struct NativeSteamInstallation: Sendable {
    let steamRootURL: URL
    let configURL: URL
    let users: [SteamIdentity]
    let libraryURLs: [URL]

    var activeUser: SteamIdentity? {
        users.sorted(by: SteamIdentity.preferredOrder).first
    }
}

extension SteamIdentity {
    nonisolated static func preferredOrder(
        _ lhs: SteamIdentity,
        _ rhs: SteamIdentity
    ) -> Bool {
        if lhs.mostRecent != rhs.mostRecent { return lhs.mostRecent }
        if lhs.rememberPassword != rhs.rememberPassword { return lhs.rememberPassword }
        if lhs.timestamp != rhs.timestamp { return (lhs.timestamp ?? 0) > (rhs.timestamp ?? 0) }
        return lhs.steamID < rhs.steamID
    }
}
