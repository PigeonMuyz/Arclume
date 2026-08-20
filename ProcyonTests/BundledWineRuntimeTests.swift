//
//  BundledWineRuntimeTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Procyon

struct BundledWineRuntimeTests {
    @Test func runtimeManifestDefinesAnAppOwnedReleaseIdentity() throws {
        let manifest = ArclumeRuntimeManifest(
            schemaVersion: 1,
            id: "io.arclume.runtime.wine",
            displayName: "Arclume Wine",
            version: "1.0.0",
            channel: "stable",
            runtimeABI: 1,
            prefixABI: "arclume-jx3-prefix-1",
            architecture: "x86_64",
            minimumMacOS: "26.0",
            legacyInstallRoots: ["legacy-runtime"],
            legacyInstallMarkers: ["wine-11.0-procyon.7"],
            archive: .init(
                name: "arclume-wine-1.0.0-x86_64.tar.xz",
                sha256: String(repeating: "a", count: 64),
                rootDirectory: "arclume-wine-runtime-x86_64"
            )
        )

        try manifest.validate()
        #expect(manifest.version == "1.0.0")
        #expect(manifest.archive.rootDirectory == "arclume-wine-runtime-x86_64")
    }

    @Test func bundledRuntimeManifestLoadsFromTheHostApp() throws {
        let manifest = try ArclumeRuntimeManifest.load()

        #expect(manifest.id == "io.arclume.runtime.wine")
        #expect(manifest.version == "1.0.0")
        #expect(manifest.archive.name == "arclume-wine-1.0.0-x86_64.tar.xz")
    }

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
                expectedVersion: "1.0.0"
            )
        )

        let markerURL = root.appendingPathComponent(
            BundledWineRuntime.versionMarkerFileName
        )
        try "1.0.0\n".write(
            to: markerURL,
            atomically: true,
            encoding: .utf8
        )
        #expect(
            BundledWineRuntime.installedRuntimeVersion(at: root)
                == "1.0.0"
        )
        #expect(
            BundledWineRuntime.isCurrentRuntime(
                at: root,
                expectedVersion: "1.0.0"
            )
        )
        #expect(
            !BundledWineRuntime.isCurrentRuntime(
                at: root,
                expectedVersion: "1.0.1"
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

    @Test func validExistingPrefixCanReceiveRuntimeUpdateInPlace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ProcyonWineRuntimeUpdateTest-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        let prefix = root.appendingPathComponent("Games", isDirectory: true)
        let wineURL = runtime.appendingPathComponent("lib/wine/x86_64-unix/wine")
        let wineServerURL = runtime.appendingPathComponent("bin/wineserver")
        let ntdllURL = runtime.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so")
        let wineInfURL = runtime.appendingPathComponent("share/wine/wine.inf")
        let dxvkURL = runtime.appendingPathComponent("dxvk/x64/dxgi.dll")
        for url in [wineURL, wineServerURL, ntdllURL, wineInfURL, dxvkURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        for url in [wineURL, wineServerURL] {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }
        try "0.9.0\n".write(
            to: runtime.appendingPathComponent(BundledWineRuntime.versionMarkerFileName),
            atomically: true,
            encoding: .utf8
        )

        try FileManager.default.createDirectory(
            at: prefix.appendingPathComponent("drive_c"),
            withIntermediateDirectories: true
        )
        for name in ["system.reg", "user.reg", "cxbottle.conf"] {
            FileManager.default.createFile(
                atPath: prefix.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        #expect(BundledWineRuntime.requiresRuntimeUpdate(
            runtimeURL: runtime,
            prefixURL: prefix,
            expectedVersion: "1.0.0"
        ))
        #expect(!BundledWineRuntime.requiresRuntimeUpdate(
            runtimeURL: runtime,
            prefixURL: prefix,
            expectedVersion: "0.9.0"
        ))
    }

    @Test func d3dMetalModulesPrecedeWineBuiltinsAndExposeActiveBackend() {
        let runtime = URL(fileURLWithPath: "/tmp/procyon-runtime", isDirectory: true)
        let graphicsRoot = URL(fileURLWithPath: "/tmp/d3dMetal4", isDirectory: true)
        let graphicsWine = graphicsRoot.appendingPathComponent("wine", isDirectory: true)

        let environment = BundledWineRuntime.graphicsRuntimeEnvironment(
            runtimeURL: runtime,
            graphicsRootURL: graphicsRoot,
            graphicsWineURL: graphicsWine,
            graphicsBackend: "d3dmetal4",
            d3dMetal4Enabled: true
        )

        #expect(environment["WINEDLLPATH"] == [
            graphicsWine.path,
            runtime.appendingPathComponent("lib/wine").path
        ].joined(separator: ":"))
        #expect(environment["DYLD_FALLBACK_LIBRARY_PATH"] == [
            graphicsRoot.appendingPathComponent("external").path,
            graphicsRoot.path,
            runtime.appendingPathComponent("lib64").path
        ].joined(separator: ":"))
        #expect(environment["CX_GRAPHICS_BACKEND"] == "d3dmetal")
        #expect(environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "d3dmetal")
        #expect(environment["D3DM_MTL4"] == "1")
    }

    @Test func dxvkKeepsWineBuiltinsAheadOfD3DMetalModules() {
        let runtime = URL(fileURLWithPath: "/tmp/procyon-runtime", isDirectory: true)
        let graphicsRoot = URL(fileURLWithPath: "/tmp/d3dMetal4", isDirectory: true)
        let graphicsWine = graphicsRoot.appendingPathComponent("wine", isDirectory: true)

        let environment = BundledWineRuntime.graphicsRuntimeEnvironment(
            runtimeURL: runtime,
            graphicsRootURL: graphicsRoot,
            graphicsWineURL: graphicsWine,
            graphicsBackend: "dxvk",
            d3dMetal4Enabled: false
        )

        #expect(environment["WINEDLLPATH"] == runtime.appendingPathComponent("lib/wine").path)
        #expect(environment["PROCYON_DLL_PATH"] == "")
        #expect(environment["DYLD_FALLBACK_LIBRARY_PATH"] == runtime.appendingPathComponent("lib64").path)
        #expect(environment["CX_GRAPHICS_BACKEND"] == "dxvk")
        #expect(environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "dxvk")
    }
}
