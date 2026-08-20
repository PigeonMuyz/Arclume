//
//  SteamDiscoveryServiceTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Procyon

struct SteamDiscoveryServiceTests {
    @Test func detectsNativeUsersAndChoosesNewestRememberedAccount() throws {
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteamDiscoveryServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: homeURL) }
        let steamRootURL = homeURL.appendingPathComponent(
            "Library/Application Support/Steam",
            isDirectory: true
        )
        let configURL = steamRootURL.appendingPathComponent("config", isDirectory: true)
        let steamAppsURL = steamRootURL.appendingPathComponent("steamapps", isDirectory: true)
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: steamAppsURL, withIntermediateDirectories: true)
        let avatarURL = configURL
            .appendingPathComponent("avatarcache", isDirectory: true)
            .appendingPathComponent("76561198000000002.png")
        try FileManager.default.createDirectory(
            at: avatarURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: avatarURL)
        try """
        "users"
        {
            "76561198000000001"
            {
                "AccountName" "older"
                "PersonaName" "Older Player"
                "RememberPassword" "1"
                "MostRecent" "0"
                "Timestamp" "100"
            }
            "76561198000000002"
            {
                "AccountName" "newer"
                "PersonaName" "Newer Player"
                "RememberPassword" "1"
                "MostRecent" "0"
                "Timestamp" "200"
            }
        }
        """.write(
            to: configURL.appendingPathComponent("loginusers.vdf"),
            atomically: true,
            encoding: .utf8
        )

        let installation = try #require(
            SteamDiscoveryService().detectNativeSteam(homeDirectory: homeURL)
        )

        #expect(installation.users.count == 2)
        #expect(installation.activeUser?.steamID == "76561198000000002")
        #expect(installation.activeUser?.source == .native)
        #expect(installation.activeUser?.avatarURL == avatarURL.standardizedFileURL)
        #expect(installation.libraryURLs == [steamAppsURL.standardizedFileURL])
    }

    @Test func currentBottleIdentityWinsAndKeepsItsSource() throws {
        let nativeIdentity = SteamIdentity(
            steamID: "native-user",
            accountName: "native",
            personaName: "Native",
            rememberPassword: true,
            mostRecent: true,
            timestamp: 300,
            source: .native,
            avatarURL: nil
        )
        let nativeInstallation = NativeSteamInstallation(
            steamRootURL: URL(fileURLWithPath: "/tmp/native"),
            configURL: URL(fileURLWithPath: "/tmp/native/config"),
            users: [nativeIdentity],
            libraryURLs: []
        )
        let bottleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteamDiscoveryBottle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: bottleURL) }
        let bottleAvatarURL = bottleURL
            .appendingPathComponent("Steam/config/avatarcache", isDirectory: true)
            .appendingPathComponent("bottle-user.png")
        try FileManager.default.createDirectory(
            at: bottleAvatarURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: bottleAvatarURL)
        let bottleInstallation = ContainerSteamInstallation(
            bottleURL: bottleURL,
            steamRootURL: bottleURL.appendingPathComponent("Steam"),
            steamExecutableURL: bottleURL.appendingPathComponent("Steam/Steam.exe"),
            discoverySource: .standard,
            users: [
                ContainerSteamUser(
                    steamID: "bottle-user",
                    accountName: "bottle",
                    personaName: "Bottle",
                    rememberPassword: false,
                    mostRecent: false,
                    timestamp: 1
                ),
            ],
            libraries: [],
            hasLoginUsersConfiguration: true,
            hasLibraryFoldersConfiguration: false
        )

        let preferred = try #require(
            SteamDiscoveryService().preferredIdentity(
                nativeInstallation: nativeInstallation,
                containerInstallation: bottleInstallation
            )
        )

        #expect(preferred.steamID == "bottle-user")
        #expect(preferred.source == .crossOverBottle(bottleURL))
        #expect(preferred.cacheKey.contains(bottleURL.path))
        #expect(preferred.avatarURL == bottleAvatarURL.standardizedFileURL)
    }

    @Test func clientSessionsKeepAccountsAndRootsSeparated() {
        let nativeIdentity = SteamIdentity(
            steamID: "native-user",
            accountName: "native",
            personaName: "Native",
            rememberPassword: true,
            mostRecent: true,
            timestamp: 2,
            source: .native,
            avatarURL: nil
        )
        let bottleURL = URL(fileURLWithPath: "/tmp/Bottle", isDirectory: true)
        let containerIdentity = SteamIdentity(
            steamID: "container-user",
            accountName: "container",
            personaName: "Container",
            rememberPassword: true,
            mostRecent: true,
            timestamp: 3,
            source: .crossOverBottle(bottleURL),
            avatarURL: nil
        )
        let nativeSession = SteamClientSession(
            identity: nativeIdentity,
            steamRootURL: URL(fileURLWithPath: "/tmp/NativeSteam", isDirectory: true),
            source: .native,
            clientKind: .native
        )
        let containerSession = SteamClientSession(
            identity: containerIdentity,
            steamRootURL: bottleURL.appendingPathComponent("Steam", isDirectory: true),
            source: .crossOverBottle(bottleURL),
            clientKind: .container
        )

        #expect(nativeSession.identity.steamID == "native-user")
        #expect(containerSession.identity.steamID == "container-user")
        #expect(nativeSession.cacheKey != containerSession.cacheKey)
        #expect(nativeSession.clientKind == .native)
        #expect(containerSession.clientKind == .container)

        let globals = AppGlobals()
        globals.nativeSteamSession = nativeSession
        globals.containerSteamSession = containerSession

        #expect(globals.steamSessions == [nativeSession, containerSession])
        #expect(globals.steamSessionsCacheKey.contains(nativeSession.cacheKey))
        #expect(globals.steamSessionsCacheKey.contains(containerSession.cacheKey))
    }
}
