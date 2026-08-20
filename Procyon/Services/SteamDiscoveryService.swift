//
//  SteamDiscoveryService.swift
//  Procyon
//

import Foundation

nonisolated struct SteamDiscoveryService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectNativeSteam(
        homeDirectory: URL? = nil
    ) -> NativeSteamInstallation? {
        let homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        let steamRootURL = homeDirectory
            .appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: steamRootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        let configURL = steamRootURL.appendingPathComponent("config", isDirectory: true)
        let users = parseUsers(
            at: configURL.appendingPathComponent("loginusers.vdf"),
            source: .native
        )
        let libraryURLs = parseNativeLibraries(
            steamRootURL: steamRootURL,
            configURL: configURL
        )
        return NativeSteamInstallation(
            steamRootURL: steamRootURL,
            configURL: configURL,
            users: users,
            libraryURLs: libraryURLs
        )
    }

    func identities(in installation: ContainerSteamInstallation) -> [SteamIdentity] {
        installation.users.map { user in
            SteamIdentity(
                steamID: user.steamID,
                accountName: user.accountName,
                personaName: user.personaName,
                rememberPassword: user.rememberPassword,
                mostRecent: user.mostRecent,
                timestamp: user.timestamp,
                source: .crossOverBottle(installation.bottleURL),
                avatarURL: avatarURL(
                    for: user.steamID,
                    in: installation.configURL
                )
            )
        }.sorted(by: SteamIdentity.preferredOrder)
    }

    func preferredIdentity(
        nativeInstallation: NativeSteamInstallation?,
        containerInstallation: ContainerSteamInstallation?
    ) -> SteamIdentity? {
        if let containerInstallation {
            let users = identities(in: containerInstallation)
            return activeUser(in: users) ?? nativeInstallation?.activeUser
        }
        return nativeInstallation?.activeUser
    }

    private func parseUsers(at url: URL, source: SteamIdentitySource) -> [SteamIdentity] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              let users = dictionaryValue(
                in: parseVDFToDict(from: contents),
                forKey: "users"
              ) as? [String: Any]
        else {
            return []
        }

        return users.compactMap { steamID, value -> SteamIdentity? in
            guard let user = value as? [String: Any] else { return nil }
            return SteamIdentity(
                steamID: steamID,
                accountName: stringValue(in: user, forKey: "AccountName") ?? "",
                personaName: stringValue(in: user, forKey: "PersonaName") ?? "",
                rememberPassword: boolValue(in: user, forKey: "RememberPassword"),
                mostRecent: boolValue(in: user, forKey: "MostRecent"),
                timestamp: stringValue(in: user, forKey: "Timestamp").flatMap(Int.init),
                source: source,
                avatarURL: avatarURL(
                    for: steamID,
                    in: url.deletingLastPathComponent()
                )
            )
        }.sorted(by: compareUsers)
    }

    private func parseNativeLibraries(steamRootURL: URL, configURL: URL) -> [URL] {
        let defaultLibraryURL = steamRootURL.appendingPathComponent(
            "steamapps",
            isDirectory: true
        )
        let candidates = [
            defaultLibraryURL.appendingPathComponent("libraryfolders.vdf"),
            configURL.appendingPathComponent("libraryfolders.vdf"),
        ]

        var libraryURLs = [defaultLibraryURL]
        for candidate in candidates {
            guard let contents = try? String(contentsOf: candidate, encoding: .utf8),
                  let libraries = dictionaryValue(
                    in: parseVDFToDict(from: contents),
                    forKey: "libraryfolders"
                  ) as? [String: Any]
            else {
                continue
            }

            for value in libraries.values {
                let path: String?
                if let dictionary = value as? [String: Any] {
                    path = stringValue(in: dictionary, forKey: "path")
                } else {
                    path = value as? String
                }
                guard let path, path.hasPrefix("/") else { continue }
                let rootURL = URL(fileURLWithPath: path, isDirectory: true)
                let steamAppsURL = rootURL.lastPathComponent
                    .caseInsensitiveCompare("steamapps") == .orderedSame
                    ? rootURL
                    : rootURL.appendingPathComponent("steamapps", isDirectory: true)
                libraryURLs.append(steamAppsURL.standardizedFileURL)
            }
            break
        }

        var seen = Set<String>()
        return libraryURLs.filter { url in
            var isDirectory: ObjCBool = false
            return seen.insert(url.standardizedFileURL.path).inserted
                && fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private func activeUser(in users: [SteamIdentity]) -> SteamIdentity? {
        users.sorted(by: SteamIdentity.preferredOrder).first
    }

    private func compareUsers(_ lhs: SteamIdentity, _ rhs: SteamIdentity) -> Bool {
        SteamIdentity.preferredOrder(lhs, rhs)
    }

    private func dictionaryValue(in dictionary: [String: Any], forKey key: String) -> Any? {
        dictionary.first(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        })?.value
    }

    private func stringValue(in dictionary: [String: Any], forKey key: String) -> String? {
        dictionaryValue(in: dictionary, forKey: key) as? String
    }

    private func boolValue(in dictionary: [String: Any], forKey key: String) -> Bool {
        guard let value = stringValue(in: dictionary, forKey: key)?.lowercased() else {
            return false
        }
        return value == "1" || value == "true" || value == "yes"
    }

    private func avatarURL(for steamID: String, in configURL: URL) -> URL? {
        let avatarCacheURL = configURL.appendingPathComponent(
            "avatarcache",
            isDirectory: true
        )
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: avatarCacheURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return candidates.first { candidate in
            candidate.deletingPathExtension().lastPathComponent == steamID
                && candidate.pathExtension.caseInsensitiveCompare("png") == .orderedSame
        }?.standardizedFileURL
    }
}
