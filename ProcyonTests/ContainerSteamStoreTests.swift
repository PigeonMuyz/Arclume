//
//  ContainerSteamStoreTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Procyon

struct ContainerSteamStoreTests {
    @Test @MainActor
    func missingManifestReturnsToNotInstalledAfterTimeout() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContainerSteamStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let bottleURL = rootURL.appendingPathComponent("Test Bottle", isDirectory: true)
        let steamExecutableURL = bottleURL.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/Steam.exe",
            isDirectory: false
        )
        let crossOverAppURL = rootURL.appendingPathComponent("CrossOver.app", isDirectory: true)
        let wineURL = crossOverAppURL.appendingPathComponent(
            "Contents/SharedSupport/CrossOver/bin/wine",
            isDirectory: false
        )
        try createFile(at: steamExecutableURL)
        try createFile(at: wineURL)

        let service = ContainerSteamService(processLauncher: RecordingProcessLauncher())
        let store = ContainerSteamStore(
            service: service,
            missingManifestTimeout: .milliseconds(20)
        )
        store.refresh(bottleURL: bottleURL)

        store.install(appID: 42, crossOverAppURL: crossOverAppURL)
        #expect(store.snapshot(for: 42)?.state == .waiting)

        try await Task.sleep(for: .milliseconds(100))

        #expect(store.snapshot(for: 42)?.state == .notInstalled)
        #expect(store.snapshot(for: 42)?.manifestURL == nil)
    }

    @Test @MainActor
    func transientManifestReplacementStillFinishesInstallation() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContainerSteamStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let bottleURL = rootURL.appendingPathComponent("Test Bottle", isDirectory: true)
        let steamRootURL = bottleURL.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam",
            isDirectory: true
        )
        let steamExecutableURL = steamRootURL.appendingPathComponent("Steam.exe")
        let steamAppsURL = steamRootURL.appendingPathComponent("steamapps", isDirectory: true)
        let manifestURL = steamAppsURL.appendingPathComponent("appmanifest_42.acf")
        let crossOverAppURL = rootURL.appendingPathComponent("CrossOver.app", isDirectory: true)
        let wineURL = crossOverAppURL.appendingPathComponent(
            "Contents/SharedSupport/CrossOver/bin/wine",
            isDirectory: false
        )
        try createFile(at: steamExecutableURL)
        try createFile(at: wineURL)
        try FileManager.default.createDirectory(
            at: steamAppsURL,
            withIntermediateDirectories: true
        )

        let store = ContainerSteamStore(
            service: ContainerSteamService(processLauncher: RecordingProcessLauncher()),
            missingManifestTimeout: .milliseconds(500),
            transientManifestTimeout: .milliseconds(200),
            pollInterval: .milliseconds(10)
        )
        store.refresh(bottleURL: bottleURL)
        var completedAppID: Int?
        store.onInstallationFinished = { completedAppID = $0 }
        store.install(appID: 42, crossOverAppURL: crossOverAppURL)

        try downloadingManifest().write(to: manifestURL, atomically: true, encoding: .utf8)
        try await waitUntil { store.snapshot(for: 42)?.state == .downloading }
        let progressBeforeReplacement = store.snapshot(for: 42)?.progress

        try FileManager.default.removeItem(at: manifestURL)
        try await Task.sleep(for: .milliseconds(60))
        #expect(store.snapshot(for: 42)?.state == .downloading)
        #expect(store.snapshot(for: 42)?.progress == progressBeforeReplacement)

        try installedManifest().write(to: manifestURL, atomically: true, encoding: .utf8)
        try await waitUntil { store.snapshot(for: 42)?.state == .installed }

        #expect(store.snapshot(for: 42)?.progress == 1)
        #expect(completedAppID == 42)
    }

    private func createFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
    }

    private func downloadingManifest() -> String {
        """
        "AppState"
        {
            "appid" "42"
            "StateFlags" "1048578"
            "installdir" "Example Game"
            "UpdateResult" "0"
            "BytesToDownload" "1000"
            "BytesDownloaded" "350"
        }
        """
    }

    private func installedManifest() -> String {
        """
        "AppState"
        {
            "appid" "42"
            "StateFlags" "4"
            "installdir" "Example Game"
            "UpdateResult" "0"
            "BytesToDownload" "1000"
            "BytesDownloaded" "1000"
        }
        """
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TestTimeoutError()
    }
}

private struct TestTimeoutError: Error {}

private struct RecordingProcessLauncher: ContainerSteamProcessLaunching {
    func launch(_ request: ContainerSteamLaunchRequest) throws -> Process {
        Process()
    }
}
