//
//  SteamOwnedLibraryService.swift
//  Procyon
//

import Foundation

struct SteamOwnedLibraryScanResult: Equatable {
    let appIDs: [String]
    let didReadAllRoots: Bool
}

struct SteamOwnedLibraryService {
    static let steamID64AccountOffset: UInt64 = 76_561_197_960_265_728

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func ownedAppIDs(
        steamID: String,
        steamRootURLs: [URL]
    ) -> [String] {
        scanOwnedAppIDs(
            steamID: steamID,
            steamRootURLs: steamRootURLs
        ).appIDs
    }

    func scanOwnedAppIDs(
        steamID: String,
        steamRootURLs: [URL]
    ) -> SteamOwnedLibraryScanResult {
        guard let accountID = accountID(for: steamID) else {
            return SteamOwnedLibraryScanResult(
                appIDs: [],
                didReadAllRoots: false
            )
        }

        var appIDs = Set<Int>()
        var didReadAllRoots = true
        let steamRoots = uniqueDirectories(steamRootURLs)
        for steamRootURL in steamRoots {
            let libraryCacheURL = steamRootURL
                .appendingPathComponent("userdata", isDirectory: true)
                .appendingPathComponent(String(accountID), isDirectory: true)
                .appendingPathComponent("config", isDirectory: true)
                .appendingPathComponent("librarycache", isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: libraryCacheURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                didReadAllRoots = false
                continue
            }

            for file in files where file.pathExtension.caseInsensitiveCompare("json") == .orderedSame {
                guard let appID = Int(file.deletingPathExtension().lastPathComponent),
                      appID > 0,
                      appID != 228_980
                else {
                    continue
                }
                appIDs.insert(appID)
            }
        }

        return SteamOwnedLibraryScanResult(
            appIDs: appIDs.sorted().map(String.init),
            didReadAllRoots: didReadAllRoots && !steamRoots.isEmpty
        )
    }

    func accountID(for steamID: String) -> UInt64? {
        guard let steamID64 = UInt64(steamID),
              steamID64 >= Self.steamID64AccountOffset
        else {
            return nil
        }
        return steamID64 - Self.steamID64AccountOffset
    }

    func ownershipByAppID(
        sessions: [SteamClientSession],
        appIDsBySteamID: [String: Set<String>]
    ) -> [Int: Set<SteamClientKind>] {
        var ownership: [Int: Set<SteamClientKind>] = [:]
        for session in sessions {
            for appIDString in appIDsBySteamID[session.identity.steamID] ?? []
                where appIDString != "228980" {
                guard let appID = Int(appIDString), appID > 0 else { continue }
                ownership[appID, default: []].insert(session.clientKind)
            }
        }
        return ownership
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
