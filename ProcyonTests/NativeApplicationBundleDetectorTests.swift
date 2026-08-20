//
//  NativeApplicationBundleDetectorTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Procyon

struct NativeApplicationBundleDetectorTests {
    @Test func extensionlessSteamBundleIsDetectedAndProvidesRuntimeIdentity() throws {
        let fixture = try NativeApplicationFixture(
            directoryName: "Stardew Valley",
            bundleIdentifier: "com.concernedape.stardewvalley",
            executableName: "StardewValley",
            displayName: "Stardew Valley"
        )
        defer { fixture.remove() }

        let application = try #require(
            NativeApplicationBundleDetector.application(at: fixture.applicationURL)
        )

        #expect(getIsNative(fromURL: fixture.applicationURL))
        #expect(application.bundleIdentifier == "com.concernedape.stardewvalley")
        #expect(application.executableName == "StardewValley")
        #expect(application.processNames.contains("Stardew Valley"))
        #expect(application.processNames.contains("StardewValley"))
        #expect(
            getAppNames(isNative: true, gameURL: fixture.applicationURL)
                == application.processNames
        )
    }

    @Test func embeddedWindowsExecutableDoesNotCancelNativeBundleDetection() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fixture = try NativeApplicationFixture(
            rootURL: rootURL,
            directoryName: "Example Game.app",
            bundleIdentifier: "example.native.game",
            executableName: "ExampleGame",
            displayName: "Example Game"
        )
        defer { fixture.remove() }
        try Data().write(
            to: rootURL.appendingPathComponent("WindowsLauncher.exe", isDirectory: false)
        )

        #expect(getIsNative(fromURL: rootURL))
        #expect(
            NativeApplicationBundleDetector.applications(in: rootURL)
                .map(\.bundleIdentifier) == ["example.native.game"]
        )
    }

    @Test @MainActor
    func playCoverStyleFlatBundleIsDetectedAsDirectNativeApplication() throws {
        let fixture = try NativeApplicationFixture(
            directoryName: "Sky.app",
            bundleIdentifier: "com.netease.sky",
            executableName: "Sky-iOS-Gold",
            displayName: "Sky",
            usesFlatBundleLayout: true
        )
        defer { fixture.remove() }

        let application = try #require(
            NativeApplicationBundleDetector.application(at: fixture.applicationURL)
        )
        var game = Game.mock
        game.isNative = true
        game.isNativeAppImport = false
        game.appExeURL = fixture.applicationURL
        game.nativeAppBundleIdentifier = "com.netease.sky"

        #expect(application.bundleIdentifier == "com.netease.sky")
        #expect(application.executableName == "Sky-iOS-Gold")
        #expect(game.isDirectNativeApplication)
        #expect(!game.usesCrossOverRuntime)
        #expect(!game.supportsCrossOverCompatibility)
    }

    @Test func ordinaryWindowsDirectoryIsNotDetectedAsNative() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try Data().write(to: rootURL.appendingPathComponent("Game.exe"))

        #expect(!getIsNative(fromURL: rootURL))
        #expect(NativeApplicationBundleDetector.applications(in: rootURL).isEmpty)
    }

    @Test func steamManifestPipelineKeepsBundleIdentityAndProcessNames() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let steamAppsURL = rootURL.appendingPathComponent("steamapps", isDirectory: true)
        let commonURL = steamAppsURL.appendingPathComponent("common", isDirectory: true)
        _ = try NativeApplicationFixture(
            rootURL: commonURL,
            directoryName: "Stardew Valley",
            bundleIdentifier: "com.concernedape.stardewvalley",
            executableName: "StardewValley",
            displayName: "Stardew Valley"
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifest = """
        "AppState"
        {
            "appid" "413150"
            "name" "Stardew Valley"
            "installdir" "Stardew Valley"
            "BytesDownloaded" "456794576"
            "BytesToDownload" "456794576"
        }
        """
        try manifest.write(
            to: steamAppsURL.appendingPathComponent("appmanifest_413150.acf"),
            atomically: true,
            encoding: .utf8
        )

        let metadata = try #require(try getGamesMeta(from: steamAppsURL).first)

        #expect(metadata.isNative)
        #expect(metadata.nativeAppBundleIdentifier == "com.concernedape.stardewvalley")
        #expect(metadata.appNames.contains("StardewValley"))
        #expect(metadata.appNames.contains("Stardew Valley"))
    }

    @Test func downloadingEntryFromNativeSteamLibraryRemainsNative() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let steamAppsURL = rootURL.appendingPathComponent("steamapps", isDirectory: true)
        let commonURL = steamAppsURL.appendingPathComponent("common", isDirectory: true)
        try FileManager.default.createDirectory(
            at: commonURL.appendingPathComponent("Don't Starve Together", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifest = """
        "AppState"
        {
            "appid" "322330"
            "name" "Don't Starve Together"
            "StateFlags" "1048578"
            "installdir" "Don't Starve Together"
            "UpdateResult" "0"
            "BytesDownloaded" "250"
            "BytesToDownload" "1000"
        }
        """
        try manifest.write(
            to: steamAppsURL.appendingPathComponent("appmanifest_322330.acf"),
            atomically: true,
            encoding: .utf8
        )

        let metadata = try #require(
            try getGamesMeta(from: steamAppsURL, isNativeSteamLibrary: true).first
        )

        #expect(metadata.isNative)
        #expect(metadata.isFromNativeSteamLibrary == true)
        #expect(!metadata.isDownloaded())
        #expect(metadata.BytesDownloaded == "250")
        #expect(metadata.BytesToDownload == "1000")
    }

    @Test @MainActor
    func crossOverCompatibilityOnlyAppliesToTheActualWindowsRuntime() {
        var nativeInstalled = Game.mock
        nativeInstalled.isNative = true
        nativeInstalled.isInstalled = true
        #expect(!nativeInstalled.usesCrossOverRuntime)
        #expect(!nativeInstalled.supportsCrossOverCompatibility)

        var officialMacUninstalled = Game.mock
        officialMacUninstalled.isNative = false
        officialMacUninstalled.isInstalled = false
        officialMacUninstalled.platforms = Platforms(windows: true, mac: true, linux: false)
        #expect(!officialMacUninstalled.usesCrossOverRuntime)

        var installedWindowsCopy = officialMacUninstalled
        installedWindowsCopy.isInstalled = true
        #expect(installedWindowsCopy.usesCrossOverRuntime)
        #expect(installedWindowsCopy.supportsCrossOverCompatibility)

        installedWindowsCopy.isFromNativeSteamLibrary = true
        #expect(!installedWindowsCopy.usesCrossOverRuntime)
        #expect(!installedWindowsCopy.supportsCrossOverCompatibility)

        var windowsOnlyUninstalled = officialMacUninstalled
        windowsOnlyUninstalled.platforms.mac = false
        #expect(windowsOnlyUninstalled.usesCrossOverRuntime)
        #expect(windowsOnlyUninstalled.supportsCrossOverCompatibility)
    }
}

private struct NativeApplicationFixture {
    let rootURL: URL
    let applicationURL: URL

    init(
        rootURL: URL? = nil,
        directoryName: String,
        bundleIdentifier: String,
        executableName: String,
        displayName: String,
        usesFlatBundleLayout: Bool = false
    ) throws {
        let rootURL = rootURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let applicationURL = rootURL.appendingPathComponent(directoryName, isDirectory: true)
        let contentsURL = usesFlatBundleLayout
            ? applicationURL
            : applicationURL.appendingPathComponent("Contents", isDirectory: true)
        let executableDirectoryURL = usesFlatBundleLayout
            ? applicationURL
            : contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(
            at: executableDirectoryURL,
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundlePackageType": "APPL",
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleExecutable": executableName,
            "CFBundleName": displayName,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        try Data().write(to: executableDirectoryURL.appendingPathComponent(executableName))

        self.rootURL = rootURL
        self.applicationURL = applicationURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
