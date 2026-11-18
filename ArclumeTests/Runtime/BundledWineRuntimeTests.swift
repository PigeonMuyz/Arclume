//
//  BundledWineRuntimeTests.swift
//  ArclumeTests
//

import Foundation
import Testing

@testable import Arclume

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
        try manifest.validate()
        #expect(!manifest.version.isEmpty)
        #expect(manifest.archive.name == "arclume-wine-\(manifest.version)-x86_64.tar.xz")
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

    @Test func d3dMetalUsesTheRuntimeModuleDirectoriesAndExposesActiveBackend() {
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
            runtime.appendingPathComponent("lib/wine/x86_64-windows").path,
            runtime.appendingPathComponent("lib/wine/i386-windows").path,
            runtime.appendingPathComponent("lib/wine").path
        ].joined(separator: ":"))
        #expect(environment["DYLD_FALLBACK_LIBRARY_PATH"] == [
            graphicsRoot.appendingPathComponent("external").path,
            graphicsRoot.path,
            runtime.appendingPathComponent("lib64").path
        ].joined(separator: ":"))
        #expect(environment["CX_GRAPHICS_BACKEND"] == "d3dmetal")
        #expect(environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "d3dmetal")
        #expect(environment["CX_APPLEGPTK_LIBD3DSHARED_PATH"] == graphicsRoot
            .appendingPathComponent("external/libd3dshared.dylib").path)
        let metal4Enabled = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        )
        #expect(environment["D3DM_MTL4"] == (metal4Enabled ? "1" : "0"))
    }

    @Test(arguments: ["4.0b2", "4.0b3", "3.0"])
    func d3dMetalRejectsStaleFrameworksBeforeInstallingModules(_ version: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("external/D3DMetal.framework/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": version, "CFBundleVersion": version],
            format: .xml, options: 0
        )
        try info.write(to: resources.appendingPathComponent("Info.plist"))

        if version == "4.0b3" {
            try BundledOnlineGameResources.validateD3DMetalVersion(at: root)
        } else {
            #expect(throws: BundledOnlineGameResourceError.self) {
                try BundledOnlineGameResources.validateD3DMetalVersion(at: root)
            }
        }
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

        #expect(environment["WINEDLLPATH"] == [
            runtime.appendingPathComponent("lib/wine/x86_64-windows").path,
            runtime.appendingPathComponent("lib/wine/i386-windows").path,
            runtime.appendingPathComponent("lib/wine").path
        ].joined(separator: ":"))
        #expect(environment["PROCYON_DLL_PATH"] == "")
        #expect(environment["DYLD_FALLBACK_LIBRARY_PATH"] == runtime.appendingPathComponent("lib64").path)
        #expect(environment["CX_GRAPHICS_BACKEND"] == "dxvk")
        #expect(environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "dxvk")
    }

    @Test func d3dMetalInstallationRepairsSeparateCopiesOfTheSharedLibrary() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("D3DMetalInstall-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let graphics = root.appendingPathComponent("graphics")
        let runtime = root.appendingPathComponent("runtime")
        let shared = graphics.appendingPathComponent("external/libd3dshared.dylib")
        try files.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sharedBytes = Data("shared library".utf8)
        try sharedBytes.write(to: shared)
        let moduleNames = ["d3d11", "d3d12", "d3d12core", "dxgi"]
        for directory in ["x86_64-windows", "x86_64-unix"] {
            try files.createDirectory(
                at: graphics.appendingPathComponent("wine/\(directory)"), withIntermediateDirectories: true
            )
            try files.createDirectory(
                at: runtime.appendingPathComponent("lib/wine/\(directory)"), withIntermediateDirectories: true
            )
        }
        for name in moduleNames {
            let dll = graphics.appendingPathComponent("wine/x86_64-windows/\(name).dll")
            try Data(name.utf8).write(to: dll)
            try files.copyItem(
                at: dll, to: runtime.appendingPathComponent("lib/wine/x86_64-windows/\(name).dll")
            )
            try files.createSymbolicLink(
                at: graphics.appendingPathComponent("wine/x86_64-unix/\(name).so"),
                withDestinationURL: shared
            )
            try sharedBytes.write(to: runtime.appendingPathComponent("lib/wine/x86_64-unix/\(name).so"))
        }
        try "d3dmetal4\n".write(
            to: runtime.appendingPathComponent(".arclume-d3dmetal-version"),
            atomically: true, encoding: .utf8
        )

        for _ in 0..<2 {
            try BundledWineRuntime.installD3DMetalModules(
                from: graphics.appendingPathComponent("wine"), into: runtime, version: "4"
            )
            for name in moduleNames {
                let module = runtime.appendingPathComponent("lib/wine/x86_64-unix/\(name).so")
                #expect(try files.attributesOfItem(atPath: module.path)[.type] as? FileAttributeType == .typeSymbolicLink)
                #expect(module.resolvingSymlinksInPath() == shared)
            }
        }
    }

    @Test func dxmtSwitchRestoresOriginalModulesAndKeepsD3DMetalSharedLinks() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("GraphicsSwitch-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let runtime = root.appendingPathComponent("runtime")
        let dxmt = root.appendingPathComponent("v0.80")
        let gptk = root.appendingPathComponent("gptk")
        func write(_ text: String, _ url: URL) throws {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        for directory in ["x86_64-windows", "x86_64-unix", "i386-windows"] {
            try files.createDirectory(at: runtime.appendingPathComponent("lib/wine/\(directory)"), withIntermediateDirectories: true)
        }
        for directory in ["x86_64-windows", "i386-windows"] {
            for name in ["d3d11", "dxgi", "d3d10core", "winemetal"] {
                try write("dxmt-\(name)", dxmt.appendingPathComponent("\(directory)/\(name).dll"))
            }
            try write("original", runtime.appendingPathComponent("lib/wine/\(directory)/d3d10core.dll"))
        }
        try write("dxmt-unix", dxmt.appendingPathComponent("x86_64-unix/winemetal.so"))
        let shared = gptk.appendingPathComponent("external/libd3dshared.dylib")
        try write("shared", shared)
        for name in ["d3d11", "d3d12", "d3d12core", "dxgi"] {
            try write("gptk-\(name)", gptk.appendingPathComponent("wine/x86_64-windows/\(name).dll"))
            let unix = gptk.appendingPathComponent("wine/x86_64-unix/\(name).so")
            try files.createDirectory(at: unix.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.createSymbolicLink(at: unix, withDestinationURL: shared)
        }
        for _ in 0..<2 {
            try BundledWineRuntime.installD3DMetalModules(from: gptk.appendingPathComponent("wine"), into: runtime, version: "4")
            try BundledWineRuntime.installDXMTModules(from: dxmt, into: runtime)
            #expect(try String(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"), encoding: .utf8) == "dxmt-d3d11")
            #expect(!files.fileExists(atPath: runtime.appendingPathComponent("lib/wine/x86_64-unix/d3d11.so").path))
            try BundledWineRuntime.installD3DMetalModules(from: gptk.appendingPathComponent("wine"), into: runtime, version: "4")
            #expect(try String(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-windows/d3d10core.dll"), encoding: .utf8) == "original")
            #expect(!files.fileExists(atPath: runtime.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so").path))
            #expect(runtime.appendingPathComponent("lib/wine/x86_64-unix/d3d11.so").resolvingSymlinksInPath() == shared)
        }
        try files.removeItem(at: dxmt.appendingPathComponent("x86_64-unix/winemetal.so"))
        #expect(throws: BundledOnlineGameResourceError.self) {
            try BundledWineRuntime.installDXMTModules(from: dxmt, into: runtime)
        }
        #expect(runtime.appendingPathComponent("lib/wine/x86_64-unix/d3d11.so").resolvingSymlinksInPath() == shared)
    }

    @Test func dxmtLaunchConfigurationUsesItsArchiveWithoutGPTKResources() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("DXMTLaunch-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let runtime = root.appendingPathComponent("runtime")
        let graphics = root.appendingPathComponent("v0.80")
        let runtimeFiles = ["lib/wine/x86_64-unix/wine", "lib/wine/x86_64-unix/ntdll.so",
            "bin/wineserver", "share/wine/wine.inf", "dxvk/x64/dxgi.dll"]
        for name in runtimeFiles {
            let file = runtime.appendingPathComponent(name)
            try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.utf8).write(to: file)
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        try BundledWineRuntime.manifest.version.write(
            to: runtime.appendingPathComponent(BundledWineRuntime.versionMarkerFileName), atomically: true, encoding: .utf8
        )
        for directory in ["x86_64-windows", "i386-windows"] {
            try files.createDirectory(at: runtime.appendingPathComponent("lib/wine/\(directory)"), withIntermediateDirectories: true)
            try files.createDirectory(at: graphics.appendingPathComponent(directory), withIntermediateDirectories: true)
            for name in ["d3d11", "dxgi", "d3d10core", "winemetal"] {
                try Data(name.utf8).write(to: graphics.appendingPathComponent("\(directory)/\(name).dll"))
            }
        }
        try files.createDirectory(at: graphics.appendingPathComponent("x86_64-unix"), withIntermediateDirectories: true)
        try Data("unix".utf8).write(to: graphics.appendingPathComponent("x86_64-unix/winemetal.so"))
        let configuration = try BundledWineRuntime.makeLaunchConfiguration(
            runtimeURL: runtime, graphicsBackend: "dxmt", d3dMetal4Enabled: false,
            mtlHudEnabled: false, wineMSync: true, graphicsRoot: graphics
        )
        #expect(configuration.environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "dxmt")
        #expect(configuration.environment["PROCYON_DLL_PATH"] == graphics.path)
        #expect(configuration.environment["CX_APPLEGPTK_LIBD3DSHARED_PATH"] == "")
        #expect(configuration.environment["D3DMETAL_FRAMEWORK_PATH"] == "")
        #expect(configuration.environment["D3DM_MTL4"] == "0")
        #expect(configuration.environment["MTL_HUD_ENABLED"] == "0")
        #expect(configuration.environment["__CX_UNIX_MTL_HUD_ENABLED"] == "0")

        let withHUD = try BundledWineRuntime.makeLaunchConfiguration(
            runtimeURL: runtime, graphicsBackend: "dxmt", d3dMetal4Enabled: false,
            mtlHudEnabled: true, wineMSync: true, graphicsRoot: graphics
        )
        #expect(withHUD.environment["MTL_HUD_ENABLED"] == "1")
        #expect(withHUD.environment["__CX_UNIX_MTL_HUD_ENABLED"] == "1")
    }

    @Test func graphicsSwitchIgnoresIdleServicesAndDetectsLoadedD3DModules() {
        let mappings = """
        p41
        n/tmp/runtime/bin/wineserver
        p42
        n/tmp/runtime/lib/wine/x86_64-unix/ntdll.so
        n/tmp/wine-keepalive.exe
        p43
        n/tmp/runtime/lib/wine/x86_64-unix/winemac.so
        p44
        n/tmp/prefix/drive_c/windows/system32/D3D11.dll
        p45
        n/tmp/runtime/lib/wine/x86_64-unix/winemetal.so
        """
        #expect(BundledWineRuntime.graphicsModulePIDs(mappings) == Set([44, 45]))
    }
}
