//
//  BundledWineRuntimeTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Procyon

struct BundledWineRuntimeTests {
    @Test func runtimeChoiceDefaultsToCrossoverAndPersistsExplicitChoice() {
        let suiteName = "ProcyonTests.runtime-choice-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!OnlineGameRuntimeKind.hasExplicitSelection(in: defaults))
        #expect(OnlineGameRuntimeKind.selected(in: defaults) == .crossOver)

        OnlineGameRuntimeKind.select(.bundledWine, in: defaults)

        #expect(OnlineGameRuntimeKind.hasExplicitSelection(in: defaults))
        #expect(OnlineGameRuntimeKind.selected(in: defaults) == .bundledWine)
    }

    @Test func crossoverApplicationValidationRequiresItsWineExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ProcyonCrossOverApplicationTest-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("CrossOver.app", isDirectory: true)
        let wineURL = appURL.appendingPathComponent(
            "Contents/SharedSupport/CrossOver/bin/wine"
        )
        try FileManager.default.createDirectory(
            at: wineURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: wineURL.path, contents: Data())

        #expect(!OnlineGameRuntimeKind.isValidCrossOverApplication(at: appURL))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: wineURL.path
        )
        #expect(OnlineGameRuntimeKind.isValidCrossOverApplication(at: appURL))
    }

    @Test func legacyCompletedCrossoverConfigurationMigratesWithoutChangingBottle() throws {
        let defaultsSuite = "ProcyonTests.runtime-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ProcyonRuntimeMigrationTest-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let crossOverURL = root.appendingPathComponent("CrossOver.app", isDirectory: true)
        let bottleURL = root.appendingPathComponent("Games", isDirectory: true)
        let launcherURL = bottleURL
            .appendingPathComponent("drive_c/SeasunGame/SeasunGame.exe")
        try FileManager.default.createDirectory(
            at: crossOverURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: launcherURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: launcherURL.path, contents: Data())

        #expect(OnlineGameRuntimeKind.migrateLegacyCrossOverConfigurationIfNeeded(
            crossOverPath: crossOverURL.path,
            selectedBottle: bottleURL.absoluteString,
            in: defaults
        ))
        #expect(OnlineGameRuntimeKind.selected(in: defaults) == .crossOver)
        #expect(
            OnlineGameRuntimeKind.configuredBottleURL(
                for: .crossOver,
                in: defaults
            )?.standardizedFileURL == bottleURL.standardizedFileURL
        )
    }

    @Test func runtimeValidationRequiresWineServerDataAndDXVK() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ProcyonWineRuntimeTest-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let wineURL = root.appendingPathComponent("lib/wine/x86_64-unix/wine")
        let wineServerURL = root.appendingPathComponent("bin/wineserver")
        let ntdllURL = root.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so")
        let wineInfURL = root.appendingPathComponent("share/wine/wine.inf")
        let dxvkURL = root.appendingPathComponent("dxvk/x64/dxgi.dll")
        for url in [wineURL, wineServerURL, ntdllURL, wineInfURL, dxvkURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }

        #expect(!BundledWineRuntime.isValidRuntime(at: root))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: wineURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: wineServerURL.path
        )

        #expect(BundledWineRuntime.isValidRuntime(at: root))
        #expect(
            !BundledWineRuntime.isCurrentRuntime(
                at: root,
                expectedVersion: "wine-11.0-procyon.1"
            )
        )

        let markerURL = root.appendingPathComponent(
            BundledWineRuntime.versionMarkerFileName
        )
        try "wine-11.0-procyon.1\n".write(
            to: markerURL,
            atomically: true,
            encoding: .utf8
        )
        #expect(
            BundledWineRuntime.installedRuntimeVersion(at: root)
                == "wine-11.0-procyon.1"
        )
        #expect(
            BundledWineRuntime.isCurrentRuntime(
                at: root,
                expectedVersion: "wine-11.0-procyon.1"
            )
        )
        #expect(
            !BundledWineRuntime.isCurrentRuntime(
                at: root,
                expectedVersion: "wine-11.0-procyon.2"
            )
        )
    }

    @Test func prefixValidationRequiresRegistryDriveAndBottleConfiguration() throws {
        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ProcyonWinePrefixTest-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: prefix) }

        try FileManager.default.createDirectory(
            at: prefix.appendingPathComponent("drive_c"),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: prefix.appendingPathComponent("system.reg").path,
            contents: Data()
        )
        FileManager.default.createFile(
            atPath: prefix.appendingPathComponent("user.reg").path,
            contents: Data()
        )
        #expect(!BundledWineRuntime.isValidPrefix(at: prefix))

        FileManager.default.createFile(
            atPath: prefix.appendingPathComponent("cxbottle.conf").path,
            contents: Data()
        )
        #expect(BundledWineRuntime.isValidPrefix(at: prefix))
    }
}
