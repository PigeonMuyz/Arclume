//
//  SteamInstallMonitorTests.swift
//  ProcyonTests
//

import Foundation
import Testing
@testable import Arclume

struct SteamInstallMonitorTests {
    private let monitor = SteamInstallMonitor()

    @Test func missingManifestIsNotInstalled() throws {
        let steamAppsDirectory = try makeSteamAppsDirectory()
        defer { try? FileManager.default.removeItem(at: steamAppsDirectory) }

        let snapshot = monitor.status(for: 42, in: [steamAppsDirectory])

        #expect(snapshot.state == .notInstalled)
        #expect(snapshot.progress == 0)
        #expect(snapshot.manifestURL == nil)
    }

    @Test func completeManifestIsInstalled() throws {
        let steamAppsDirectory = try makeSteamAppsDirectory()
        defer { try? FileManager.default.removeItem(at: steamAppsDirectory) }
        try writeManifest(
            appID: 42,
            to: steamAppsDirectory,
            contents: manifest(
                appID: 42,
                stateFlags: 4,
                bytesDownloaded: 1_000,
                bytesToDownload: 1_000
            )
        )

        let snapshot = monitor.status(for: 42, in: [steamAppsDirectory])

        #expect(snapshot.state == .installed)
        #expect(snapshot.progress == 1)
        #expect(snapshot.installDirectory == "Example Game")
    }

    @Test func downloadingManifestReportsProgress() throws {
        let steamAppsDirectory = try makeSteamAppsDirectory()
        defer { try? FileManager.default.removeItem(at: steamAppsDirectory) }
        try writeManifest(
            appID: 42,
            to: steamAppsDirectory,
            contents: manifest(
                appID: 42,
                stateFlags: 1026,
                bytesDownloaded: 250,
                bytesToDownload: 1_000
            )
        )

        let snapshot = monitor.status(for: 42, in: [steamAppsDirectory])

        #expect(snapshot.state == .downloading)
        #expect(snapshot.progress == 0.25)
        #expect(snapshot.progressPercent == 25)
        #expect(snapshot.bytesDownloaded == 250)
        #expect(snapshot.bytesToDownload == 1_000)
        #expect(snapshot.phase == .preparing)
    }

    @Test func stagingManifestUsesStagingProgress() throws {
        let steamAppsDirectory = try makeSteamAppsDirectory()
        defer { try? FileManager.default.removeItem(at: steamAppsDirectory) }
        try writeManifest(
            appID: 42,
            to: steamAppsDirectory,
            contents: manifest(
                appID: 42,
                stateFlags: 1 << 21,
                bytesDownloaded: 1_000,
                bytesToDownload: 1_000,
                bytesStaged: 400,
                bytesToStage: 1_000
            )
        )

        let snapshot = monitor.status(for: 42, in: [steamAppsDirectory])

        #expect(snapshot.state == .downloading)
        #expect(snapshot.phase == .staging)
        #expect(snapshot.progress == 0.4)
        #expect(snapshot.bytesStaged == 400)
        #expect(snapshot.bytesToStage == 1_000)
    }

    @Test func malformedManifestIsUnknown() throws {
        let steamAppsDirectory = try makeSteamAppsDirectory()
        defer { try? FileManager.default.removeItem(at: steamAppsDirectory) }
        try writeManifest(
            appID: 42,
            to: steamAppsDirectory,
            contents: """
            "AppState"
            {
                "appid" "42"
                "StateFlags" "4"
            """
        )

        let snapshot = monitor.status(for: 42, in: [steamAppsDirectory])

        #expect(snapshot.state == .unknown)
        #expect(snapshot.progress == 0)
        #expect(snapshot.manifestURL?.lastPathComponent == "appmanifest_42.acf")
    }

    @Test func queuedAndFailedManifestsAreClassified() throws {
        let steamAppsDirectory = try makeSteamAppsDirectory()
        defer { try? FileManager.default.removeItem(at: steamAppsDirectory) }
        try writeManifest(
            appID: 42,
            to: steamAppsDirectory,
            contents: manifest(
                appID: 42,
                stateFlags: 2,
                bytesDownloaded: 0,
                bytesToDownload: 1_000
            )
        )
        try writeManifest(
            appID: 43,
            to: steamAppsDirectory,
            contents: manifest(
                appID: 43,
                stateFlags: 2,
                bytesDownloaded: 0,
                bytesToDownload: 1_000,
                updateResult: 6
            )
        )

        #expect(monitor.status(for: 42, in: [steamAppsDirectory]).state == .waiting)
        #expect(monitor.status(for: 43, in: [steamAppsDirectory]).state == .failed)
    }

    @Test func observationPublishesChangesAndCanBeCancelled() async throws {
        let steamAppsDirectory = try makeSteamAppsDirectory()
        defer { try? FileManager.default.removeItem(at: steamAppsDirectory) }
        let observation = monitor.observe(
            appID: 42,
            in: [steamAppsDirectory],
            pollInterval: .milliseconds(10)
        )
        var iterator = observation.updates.makeAsyncIterator()

        let initialSnapshot = await iterator.next()
        #expect(initialSnapshot?.state == .notInstalled)

        try writeManifest(
            appID: 42,
            to: steamAppsDirectory,
            contents: manifest(
                appID: 42,
                stateFlags: 4,
                bytesDownloaded: 1_000,
                bytesToDownload: 1_000
            )
        )
        let installedSnapshot = await iterator.next()
        #expect(installedSnapshot?.state == .installed)

        observation.cancel()
        let finalSnapshot = await iterator.next()
        #expect(finalSnapshot == nil)
    }

    private func makeSteamAppsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteamInstallMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func writeManifest(appID: Int, to directory: URL, contents: String) throws {
        let manifestURL = directory
            .appendingPathComponent("appmanifest_\(appID).acf", isDirectory: false)
        try contents.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    private func manifest(
        appID: Int,
        stateFlags: UInt64,
        bytesDownloaded: UInt64,
        bytesToDownload: UInt64,
        bytesStaged: UInt64? = nil,
        bytesToStage: UInt64? = nil,
        updateResult: Int = 0
    ) -> String {
        let stagingValues: String
        if let bytesStaged, let bytesToStage {
            stagingValues = """
                "BytesToStage" "\(bytesToStage)"
                "BytesStaged" "\(bytesStaged)"
            """
        } else {
            stagingValues = ""
        }
        return """
        "AppState"
        {
            "appid" "\(appID)"
            "name" "Example Game"
            "StateFlags" "\(stateFlags)"
            "installdir" "Example Game"
            "UpdateResult" "\(updateResult)"
            "BytesToDownload" "\(bytesToDownload)"
            "BytesDownloaded" "\(bytesDownloaded)"
            \(stagingValues)
        }
        """
    }
}
