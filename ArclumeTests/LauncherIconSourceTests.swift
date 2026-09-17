import Foundation
import Testing
@testable import Arclume

struct LauncherIconSourceTests {
    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LauncherIcons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func bundle(at url: URL) throws {
        let resources = url.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist = ["CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture", "CFBundleIconFile": "GameIcon"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        try Data().write(to: resources.appendingPathComponent("GameIcon.icns"))
    }

    @Test func resolvesExtensionlessSteamBundleAndItsRealIcon() throws {
        try withRoot { root in
            try bundle(at: root)
            #expect(LauncherIconSource.resolve(explicit: nil, directory: root, native: true, names: []) == root)
            #expect(LauncherIconSource.nativeIconFile(at: root) == root.appendingPathComponent("Contents/Resources/GameIcon.icns"))
        }
    }

    @Test func resolvesAppInsideSteamInstallation() throws {
        try withRoot { root in
            let app = root.appendingPathComponent("Game.app")
            try bundle(at: app)
            #expect(LauncherIconSource.resolve(explicit: nil, directory: root, native: true, names: ["Game.app"])?.resolvingSymlinksInPath().path == app.resolvingSymlinksInPath().path)
            #expect(LauncherIconSource.resolve(explicit: root.appendingPathComponent("missing.app"), directory: root, native: true, names: [])?.resolvingSymlinksInPath().path == app.resolvingSymlinksInPath().path)
        }
    }

    @Test func windowsUsesKnownGameExecutableNotPosterOrUninstaller() throws {
        try withRoot { root in
            for name in ["game.exe", "uninstall.exe", "header.jpg"] { try Data().write(to: root.appendingPathComponent(name)) }
            #expect(LauncherIconSource.resolve(explicit: nil, directory: root, native: false, names: ["uninstall.exe", "game.exe"])?.resolvingSymlinksInPath().path == root.appendingPathComponent("game.exe").resolvingSymlinksInPath().path)
            #expect(LauncherIconSource.resolve(explicit: nil, directory: root, native: false, names: []) == nil)
            #expect(LauncherIconSource.nativeIconFile(at: root) == nil)
        }
    }

    @Test func explicitExecutableIsAuthoritative() throws {
        try withRoot { root in
            let target = root.appendingPathComponent("Actual.exe")
            try Data().write(to: target)
            #expect(LauncherIconSource.resolve(explicit: target, directory: nil, native: false, names: []) == target)
        }
    }
}
