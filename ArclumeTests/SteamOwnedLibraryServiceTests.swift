//
//  SteamOwnedLibraryServiceTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Arclume

struct SteamOwnedLibraryServiceTests {
    @Test func convertsSteamID64ToUserdataAccountID() {
        let service = SteamOwnedLibraryService()

        #expect(service.accountID(for: "76561198296971756") == 336_706_028)
        #expect(service.accountID(for: "invalid") == nil)
    }

    @Test func mergesNativeAndContainerLibraryCachesForTheActiveAccount() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteamOwnedLibraryServiceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let nativeSteamRoot = rootURL.appendingPathComponent("NativeSteam", isDirectory: true)
        let containerSteamRoot = rootURL.appendingPathComponent("ContainerSteam", isDirectory: true)
        try createLibraryCache(
            in: nativeSteamRoot,
            accountID: 336_706_028,
            fileNames: ["413150.json", "228980.json", "achievement_progress.json"]
        )
        try createLibraryCache(
            in: containerSteamRoot,
            accountID: 336_706_028,
            fileNames: ["1260320.json", "413150.json"]
        )
        try createLibraryCache(
            in: nativeSteamRoot,
            accountID: 42,
            fileNames: ["999999.json"]
        )

        let appIDs = SteamOwnedLibraryService().ownedAppIDs(
            steamID: "76561198296971756",
            steamRootURLs: [nativeSteamRoot, containerSteamRoot, nativeSteamRoot]
        )

        #expect(appIDs == ["413150", "1260320"])
    }

    @Test func reportsUnreadableLibraryCacheWithoutTreatingItAsAnEmptyLibrary() {
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingSteamRoot-\(UUID().uuidString)", isDirectory: true)

        let result = SteamOwnedLibraryService().scanOwnedAppIDs(
            steamID: "76561198296971756",
            steamRootURLs: [missingRoot]
        )

        #expect(result.appIDs.isEmpty)
        #expect(!result.didReadAllRoots)
    }

    @Test func sameAccountOwnershipAppliesToBothSteamClients() {
        let steamID = "76561198296971756"
        let nativeIdentity = SteamIdentity(
            steamID: steamID,
            accountName: "same-account",
            personaName: "Same Account",
            rememberPassword: true,
            mostRecent: true,
            timestamp: nil,
            source: .native,
            avatarURL: nil
        )
        let bottleURL = URL(fileURLWithPath: "/tmp/SameAccountBottle", isDirectory: true)
        let containerIdentity = SteamIdentity(
            steamID: steamID,
            accountName: "same-account",
            personaName: "Same Account",
            rememberPassword: true,
            mostRecent: true,
            timestamp: nil,
            source: .crossOverBottle(bottleURL),
            avatarURL: nil
        )
        let sessions = [
            SteamClientSession(
                identity: nativeIdentity,
                steamRootURL: URL(fileURLWithPath: "/tmp/NativeSteam", isDirectory: true),
                source: .native,
                clientKind: .native
            ),
            SteamClientSession(
                identity: containerIdentity,
                steamRootURL: bottleURL.appendingPathComponent("Steam", isDirectory: true),
                source: .crossOverBottle(bottleURL),
                clientKind: .container
            ),
        ]

        let ownership = SteamOwnedLibraryService().ownershipByAppID(
            sessions: sessions,
            appIDsBySteamID: [steamID: ["335190", "228980"]]
        )

        #expect(ownership[335_190] == [.native, .container])
        #expect(ownership[228_980] == nil)
    }

    private func createLibraryCache(
        in steamRootURL: URL,
        accountID: UInt64,
        fileNames: [String]
    ) throws {
        let libraryCacheURL = steamRootURL
            .appendingPathComponent("userdata", isDirectory: true)
            .appendingPathComponent(String(accountID), isDirectory: true)
            .appendingPathComponent("config/librarycache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: libraryCacheURL,
            withIntermediateDirectories: true
        )
        for fileName in fileNames {
            try Data("{}".utf8).write(
                to: libraryCacheURL.appendingPathComponent(fileName)
            )
        }
    }
}
