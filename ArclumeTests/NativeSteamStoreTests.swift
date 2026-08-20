//
//  NativeSteamStoreTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Arclume

struct NativeSteamStoreTests {
    @Test @MainActor
    func nativeInstallRequestPublishesWaitingState() async throws {
        let launcher = RecordingNativeSteamLauncher()
        let store = NativeSteamStore(launcher: launcher)

        #expect(store.isReady)
        store.install(appID: 322_330)

        #expect(launcher.installedAppIDs == [322_330])
        #expect(store.snapshot(for: 322_330)?.state == .waiting)
        #expect(store.snapshot(for: 322_330)?.phase == .queued)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func nativeInstallRequestWaitsForInitialManifestTimeout() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeSteamStoreTests-\(UUID().uuidString)", isDirectory: true)
        let steamAppsURL = rootURL.appendingPathComponent("steamapps", isDirectory: true)
        try FileManager.default.createDirectory(
            at: steamAppsURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let installation = NativeSteamInstallation(
            steamRootURL: rootURL,
            configURL: rootURL.appendingPathComponent("config", isDirectory: true),
            users: [],
            libraryURLs: [steamAppsURL]
        )
        let store = NativeSteamStore(
            launcher: RecordingNativeSteamLauncher(),
            missingManifestTimeout: .milliseconds(150),
            pollInterval: .milliseconds(10)
        )
        store.refresh(installation: installation)
        store.install(appID: 322_330)

        try await Task.sleep(for: .milliseconds(70))
        #expect(store.snapshot(for: 322_330)?.state == .waiting)

        try await waitUntil { store.snapshot(for: 322_330) == nil }
    }

    @Test @MainActor
    func manifestMissingAfterBeingObservedUsesTransientDebounce() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeSteamStoreTests-\(UUID().uuidString)", isDirectory: true)
        let steamAppsURL = rootURL.appendingPathComponent("steamapps", isDirectory: true)
        try FileManager.default.createDirectory(
            at: steamAppsURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let installation = NativeSteamInstallation(
            steamRootURL: rootURL,
            configURL: rootURL.appendingPathComponent("config", isDirectory: true),
            users: [],
            libraryURLs: [steamAppsURL]
        )
        let store = NativeSteamStore(
            launcher: RecordingNativeSteamLauncher(),
            missingManifestTimeout: .seconds(1),
            pollInterval: .milliseconds(20)
        )
        store.refresh(installation: installation)
        store.install(appID: 322_330)

        try manifest(
            stateFlags: 1 << 20,
            bytesDownloaded: 250,
            bytesToDownload: 1_000
        ).write(to: manifestURL(in: steamAppsURL), atomically: true, encoding: .utf8)
        try await waitUntil { store.snapshot(for: 322_330)?.state == .downloading }

        try FileManager.default.removeItem(at: manifestURL(in: steamAppsURL))
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.snapshot(for: 322_330)?.state == .downloading)

        try await waitUntil { store.snapshot(for: 322_330) == nil }
    }

    @Test @MainActor
    func manifestChangesPublishProgressAndFinishWithoutManualRefresh() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeSteamStoreTests-\(UUID().uuidString)", isDirectory: true)
        let steamAppsURL = rootURL.appendingPathComponent("steamapps", isDirectory: true)
        try FileManager.default.createDirectory(
            at: steamAppsURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let installation = NativeSteamInstallation(
            steamRootURL: rootURL,
            configURL: rootURL.appendingPathComponent("config", isDirectory: true),
            users: [],
            libraryURLs: [steamAppsURL]
        )
        let store = NativeSteamStore(pollInterval: .milliseconds(10))
        var completedAppID: Int?
        store.onInstallationFinished = { completedAppID = $0 }
        store.refresh(installation: installation)

        try manifest(
            stateFlags: 1 << 20,
            bytesDownloaded: 250,
            bytesToDownload: 1_000
        ).write(to: manifestURL(in: steamAppsURL), atomically: true, encoding: .utf8)
        try await waitUntil { store.snapshot(for: 322_330)?.progress == 0.25 }

        #expect(store.snapshot(for: 322_330)?.state == .downloading)
        #expect(completedAppID == nil)

        try FileManager.default.removeItem(at: manifestURL(in: steamAppsURL))
        try await Task.sleep(for: .milliseconds(15))
        #expect(store.snapshot(for: 322_330)?.progress == 0.25)

        try manifest(
            stateFlags: 1 << 21,
            bytesDownloaded: 1_000,
            bytesToDownload: 1_000,
            bytesStaged: 700,
            bytesToStage: 1_000
        ).write(to: manifestURL(in: steamAppsURL), atomically: true, encoding: .utf8)
        try await waitUntil { store.snapshot(for: 322_330)?.progress == 0.7 }

        #expect(store.snapshot(for: 322_330)?.phase == .staging)

        try manifest(
            stateFlags: 4,
            bytesDownloaded: 1_000,
            bytesToDownload: 1_000,
            bytesStaged: 1_000,
            bytesToStage: 1_000
        ).write(to: manifestURL(in: steamAppsURL), atomically: true, encoding: .utf8)
        try await waitUntil { completedAppID == 322_330 }

        #expect(store.snapshot(for: 322_330)?.state == .installed)
        #expect(store.snapshot(for: 322_330)?.progress == 1)
    }

    @Test @MainActor
    func existingInstalledManifestDoesNotEmitFalseCompletion() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeSteamStoreTests-\(UUID().uuidString)", isDirectory: true)
        let steamAppsURL = rootURL.appendingPathComponent("steamapps", isDirectory: true)
        try FileManager.default.createDirectory(
            at: steamAppsURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try manifest(
            stateFlags: 4,
            bytesDownloaded: 1_000,
            bytesToDownload: 1_000
        ).write(to: manifestURL(in: steamAppsURL), atomically: true, encoding: .utf8)

        let installation = NativeSteamInstallation(
            steamRootURL: rootURL,
            configURL: rootURL.appendingPathComponent("config", isDirectory: true),
            users: [],
            libraryURLs: [steamAppsURL]
        )
        let store = NativeSteamStore(pollInterval: .milliseconds(10))
        var completionCount = 0
        store.onInstallationFinished = { _ in completionCount += 1 }
        store.refresh(installation: installation)
        try await waitUntil { store.snapshot(for: 322_330)?.state == .installed }
        try await Task.sleep(for: .milliseconds(40))

        #expect(completionCount == 0)
    }

    private func manifestURL(in steamAppsURL: URL) -> URL {
        steamAppsURL.appendingPathComponent("appmanifest_322330.acf")
    }

    private func manifest(
        stateFlags: UInt64,
        bytesDownloaded: UInt64,
        bytesToDownload: UInt64,
        bytesStaged: UInt64? = nil,
        bytesToStage: UInt64? = nil
    ) -> String {
        let staging: String
        if let bytesStaged, let bytesToStage {
            staging = """
                "BytesStaged" "\(bytesStaged)"
                "BytesToStage" "\(bytesToStage)"
            """
        } else {
            staging = ""
        }
        return """
        "AppState"
        {
            "appid" "322330"
            "name" "Don't Starve Together"
            "StateFlags" "\(stateFlags)"
            "installdir" "Don't Starve Together"
            "UpdateResult" "0"
            "BytesDownloaded" "\(bytesDownloaded)"
            "BytesToDownload" "\(bytesToDownload)"
            \(staging)
        }
        """
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NativeSteamStoreTestTimeout()
    }
}

private struct NativeSteamStoreTestTimeout: Error {}

@MainActor
private final class RecordingNativeSteamLauncher: NativeSteamLaunching {
    var applicationURL: URL? = URL(
        fileURLWithPath: "/Applications/Steam.app",
        isDirectory: true
    )
    private(set) var installedAppIDs: [Int] = []

    func install(appID: Int) throws {
        installedAppIDs.append(appID)
    }
}
