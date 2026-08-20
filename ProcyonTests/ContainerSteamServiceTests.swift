//
//  ContainerSteamServiceTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Procyon

struct ContainerSteamServiceTests {
    @Test func detectsStandardSteamAndParsesContainerConfiguration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let steamRoot = fixture.bottleURL
            .appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        try fixture.createFile(at: steamRoot.appendingPathComponent("steam.exe"))
        let configURL = steamRoot.appendingPathComponent("config", isDirectory: true)
        try fixture.write(
            #"""
            "users"
            {
                "76561198000000001"
                {
                    "AccountName" "test_account"
                    "PersonaName" "Test Player"
                    "RememberPassword" "1"
                    "MostRecent" "1"
                    "Timestamp" "1700000000"
                }
            }
            """#,
            to: configURL.appendingPathComponent("loginusers.vdf")
        )

        let externalLibrary = fixture.rootURL.appendingPathComponent(
            "External Steam", isDirectory: true)
        try FileManager.default.createDirectory(
            at: externalLibrary, withIntermediateDirectories: true)
        let dosDevicesURL = fixture.bottleURL.appendingPathComponent(
            "dosdevices", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dosDevicesURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: dosDevicesURL.appendingPathComponent("d:"),
            withDestinationURL: externalLibrary
        )
        try fixture.write(
            #"""
            "libraryfolders"
            {
                "0"
                {
                    "path" "C:\\Program Files (x86)\\Steam"
                    "label" ""
                    "apps"
                    {
                        "620" "1"
                    }
                }
                "1"
                {
                    "path" "D:\\Games"
                    "label" "External"
                    "apps"
                    {
                        "1245620" "1"
                    }
                }
            }
            """#,
            to:
                steamRoot
                .appendingPathComponent("steamapps", isDirectory: true)
                .appendingPathComponent("libraryfolders.vdf")
        )

        let detection = ContainerSteamService().detect(in: fixture.bottleURL)
        #expect(detection.status == .ready)
        #expect(detection.canLaunchSteam)

        let installation = try #require(detection.installation)
        #expect(installation.discoverySource == .standard)
        #expect(installation.steamExecutableURL.lastPathComponent.lowercased() == "steam.exe")
        #expect(installation.activeUser?.steamID == "76561198000000001")
        #expect(installation.activeUser?.personaName == "Test Player")
        #expect(installation.hasRememberedUser)
        #expect(installation.libraries.count == 2)

        let primary = try #require(installation.libraries.first(where: { $0.identifier == "0" }))
        #expect(primary.hostURL == steamRoot.standardizedFileURL)
        #expect(primary.installedAppIDs == Set([620]))

        let external = try #require(installation.libraries.first(where: { $0.identifier == "1" }))
        #expect(external.label == "External")
        #expect(
            external.hostURL
                == externalLibrary.appendingPathComponent("Games", isDirectory: true)
                .standardizedFileURL)
        #expect(
            external.steamAppsURL
                == external.hostURL?.appendingPathComponent("steamapps", isDirectory: true))
        #expect(external.installedAppIDs == Set([1_245_620]))
    }

    @Test func overrideIsPreferredAndFallsBackToDefaultLibrary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let standardRoot = fixture.bottleURL
            .appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        try fixture.createFile(at: standardRoot.appendingPathComponent("Steam.exe"))
        let overrideRoot = fixture.bottleURL
            .appendingPathComponent("drive_c/Custom Steam", isDirectory: true)
        try fixture.createFile(at: overrideRoot.appendingPathComponent("Steam.exe"))

        let detection = ContainerSteamService().detect(
            in: fixture.bottleURL,
            steamOverride: overrideRoot
        )

        #expect(detection.status == .executableFound)
        let installation = try #require(detection.installation)
        #expect(installation.discoverySource == .override)
        #expect(installation.steamRootURL == overrideRoot.standardizedFileURL)
        #expect(installation.libraries.count == 1)
        #expect(installation.libraries[0].windowsPath == "C:\\Custom Steam")
        #expect(installation.libraries[0].hostURL == overrideRoot.standardizedFileURL)
    }

    @Test func missingSteamReportsEveryCandidate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let overrideURL = fixture.bottleURL.appendingPathComponent(
            "drive_c/My Steam", isDirectory: true)
        let detection = ContainerSteamService().detect(
            in: fixture.bottleURL,
            steamOverride: overrideURL
        )

        #expect(detection.status == .notFound)
        #expect(detection.installation == nil)
        #expect(detection.searchedExecutableURLs.count == 3)
        #expect(
            detection.searchedExecutableURLs[0] == overrideURL.appendingPathComponent("Steam.exe"))
    }

    @Test func launchRequestsUseArgumentsWithoutShellInterpolation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let steamRoot = fixture.bottleURL
            .appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        try fixture.createFile(at: steamRoot.appendingPathComponent("Steam.exe"))
        let crossOverAppURL = fixture.rootURL.appendingPathComponent(
            "CrossOver Preview.app", isDirectory: true)
        let wineURL = crossOverAppURL.appendingPathComponent(
            "Contents/SharedSupport/CrossOver/bin/wine"
        )
        try fixture.createFile(at: wineURL)

        let service = ContainerSteamService()
        let installation = try #require(service.detect(in: fixture.bottleURL).installation)
        let request = try service.makeInstallRequest(
            appID: 1_245_620,
            in: installation,
            using: crossOverAppURL
        )

        #expect(request.executableURL == wineURL.standardizedFileURL)
        #expect(
            request.arguments == [
                "--bottle",
                fixture.bottleURL.lastPathComponent,
                steamRoot.appendingPathComponent("Steam.exe").path,
                "steam://install/1245620",
            ])
        #expect(request.currentDirectoryURL == steamRoot.standardizedFileURL)
        #expect(request.environmentOverrides["CX_GRAPHICS_BACKEND"] == "d3dmetal")
        #expect(!request.arguments.contains("-c"))
    }

    @Test func gameInstallationProgressIsClamped() {
        let bottleURL = URL(fileURLWithPath: "/tmp/TestBottle", isDirectory: true)
        let downloading = ContainerGameInstallation(
            appID: 10,
            bottleURL: bottleURL,
            state: .downloading,
            library: nil,
            manifestURL: nil,
            installDirectoryURL: nil,
            bytesDownloaded: 120,
            bytesToDownload: 100
        )
        let notInstalled = ContainerGameInstallation(
            appID: 11,
            bottleURL: bottleURL,
            state: .notInstalled,
            library: nil,
            manifestURL: nil,
            installDirectoryURL: nil,
            bytesDownloaded: nil,
            bytesToDownload: nil
        )

        #expect(downloading.progress == 1)
        #expect(notInstalled.progress == 0)
    }
}

private struct Fixture {
    let rootURL: URL
    let bottleURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        bottleURL = rootURL.appendingPathComponent("Bottle With Spaces", isDirectory: true)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
    }

    func createFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
    }

    func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
