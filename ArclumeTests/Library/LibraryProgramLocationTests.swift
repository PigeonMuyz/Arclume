import Foundation
import Testing
@testable import Arclume

struct LibraryProgramLocationTests {
    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryLocation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test func executableAndMissingPaths() throws {
        try withRoot { root in
            var game = Game.emptyGame
            game.appExeURL = root.appendingPathComponent("SeasunGame.exe")
            #expect(LibraryProgramLocation.directory(for: game) == nil)
            try Data().write(to: game.appExeURL!)
            #expect(LibraryProgramLocation.directory(for: game) == root)
            game.appExeURL = root.appendingPathComponent("unresolved.lnk")
            try Data().write(to: game.appExeURL!)
            #expect(LibraryProgramLocation.directory(for: game) == nil)
            game.installedBottleURL = root
            #expect(LibraryProgramLocation.directory(for: game) == nil)
        }
    }

    @Test func nativeBundleOpensContainingDirectory() throws {
        try withRoot { root in
            var game = Game.emptyGame
            game.appExeURL = root.appendingPathComponent("Example.app")
            try FileManager.default.createDirectory(at: game.appExeURL!, withIntermediateDirectories: true)
            #expect(LibraryProgramLocation.directory(for: game) == root)
        }
    }

    @Test func shortcutOpensTargetInsteadOfDesktop() throws {
        try withRoot { root in
            let bottle = root.resolvingSymlinksInPath()
            let directory = bottle.appendingPathComponent("drive_c/Apps/YY", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("YY.exe"))
            let path = Array("C:\\Apps\\YY\\YY.exe".utf8) + [0]
            var bytes = [UInt8](repeating: 0, count: 76 + 28)
            func put(_ value: Int, at offset: Int) {
                for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
            }
            put(76, at: 0)
            bytes.replaceSubrange(4..<20, with: [1, 20, 2, 0, 0, 0, 0, 0, 192, 0, 0, 0, 0, 0, 0, 70])
            put(2, at: 20)
            put(28 + path.count, at: 76)
            put(28, at: 80)
            put(1, at: 84)
            put(28, at: 92)
            bytes += path
            var game = Game.emptyGame
            game.installedBottleURL = bottle
            game.appExeURL = bottle.appendingPathComponent("Desktop.lnk")
            try Data(bytes).write(to: game.appExeURL!)
            #expect(LibraryProgramLocation.directory(for: game) == directory)
            game.isNative = false
            game.isCustom = true
            #expect(LocalProgramAvailability.unavailableIDs(in: [game]).isEmpty)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("YY.exe"))
            #expect(LocalProgramAvailability.unavailableIDs(in: [game]) == [game.id])
        }
    }

    @Test func missingLocalProgramsDisappearAndReturnWithoutChangingMetadata() throws {
        try withRoot { root in
            var jx3 = Game.emptyGame
            jx3.id = OnlineGameMode.jx3GameID
            jx3.isNative = false
            jx3.isCustom = true
            jx3.installedBottleURL = root
            jx3.appExeURL = root.appendingPathComponent("SeasunGame.exe")
            jx3.name = "我的启动器"
            var yy = jx3
            yy.id = "yy"
            yy.appExeURL = root.appendingPathComponent("YY.exe")
            yy.steamAppID = 123 // Linked metadata must not exempt a local program.
            var steam = Game.emptyGame
            steam.id = "owned-steam"
            steam.isCustom = false
            steam.isInstalled = false
            steam.appExeURL = nil
            let games = [jx3, yy, steam]
            #expect(LocalProgramAvailability.unavailableIDs(in: games) == [jx3.id, yy.id])
            try Data().write(to: jx3.appExeURL!)
            try Data().write(to: yy.appExeURL!)
            #expect(LocalProgramAvailability.unavailableIDs(in: games).isEmpty)
            try FileManager.default.removeItem(at: jx3.appExeURL!)
            #expect(LocalProgramAvailability.unavailableIDs(in: games) == [jx3.id])
            try Data().write(to: jx3.appExeURL!)
            #expect(LocalProgramAvailability.unavailableIDs(in: games).isEmpty)
            #expect(jx3.name == "我的启动器")
            #expect(jx3.isInstalled)
        }
    }

    @Test func missingBottleAndInvalidExecutableAreUnavailable() throws {
        try withRoot { root in
            var game = Game.emptyGame
            game.isNative = false
            game.isCustom = true
            game.appExeURL = root.appendingPathComponent("app.exe")
            try Data().write(to: game.appExeURL!)
            game.installedBottleURL = root.appendingPathComponent("missing-bottle")
            #expect(!LocalProgramAvailability.isAvailable(game))
            game.installedBottleURL = root
            #expect(LocalProgramAvailability.isAvailable(game))
            try FileManager.default.removeItem(at: game.appExeURL!)
            try FileManager.default.createDirectory(at: game.appExeURL!, withIntermediateDirectories: true)
            #expect(!LocalProgramAvailability.isAvailable(game))
            game.appExeURL = root.appendingPathComponent("broken.lnk")
            try Data().write(to: game.appExeURL!)
            #expect(!LocalProgramAvailability.isAvailable(game))
            game.installedBottleURL = nil
            #expect(!LocalProgramAvailability.isAvailable(game))
        }
    }

    @Test func nativeImportsRequireExistingBundle() throws {
        try withRoot { root in
            var game = Game.emptyGame
            game.isNative = true
            game.isNativeAppImport = true
            game.appExeURL = root.appendingPathComponent("Example.app")
            #expect(LocalProgramAvailability.unavailableIDs(in: [game]) == [game.id])
            try FileManager.default.createDirectory(at: game.appExeURL!, withIntermediateDirectories: true)
            #expect(LocalProgramAvailability.unavailableIDs(in: [game]).isEmpty)
        }
    }

    @Test func libraryRefreshHidesStaleCardAndClosesItsDetails() throws {
        try withRoot { root in
            let library = LibraryPageGlobals()
            library.games = []
            var game = Game.emptyGame
            game.id = "availability-fixture"
            game.isCustom = true
            game.isNative = false
            game.appExeURL = root.appendingPathComponent("test.exe")
            try Data().write(to: game.appExeURL!)
            library.customAddedGames = [game]
            #expect(library.allGames.map(\.id) == [game.id])
            library.selectedGame = game
            library.showDetailView = true
            try FileManager.default.removeItem(at: game.appExeURL!)
            library.refreshLocalProgramAvailability()
            #expect(library.allGames.isEmpty)
            #expect(!library.showDetailView)
            #expect(library.selectedGame == nil)
            #expect(library.customAddedGames.map(\.id) == [game.id])
            try Data().write(to: game.appExeURL!)
            library.refreshLocalProgramAvailability()
            #expect(library.allGames.map(\.id) == [game.id])
        }
    }

    @Test func steamUsesManifestLocationAndRejectsTraversal() throws {
        try withRoot { root in
            let directory = root.appendingPathComponent("common/Test Game", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            func snapshot(_ name: String) -> SteamInstallSnapshot {
                SteamInstallSnapshot(appID: 1, state: .installed, phase: .installed, progress: 1,
                    bytesDownloaded: nil, bytesToDownload: nil, bytesStaged: nil, bytesToStage: nil,
                    rawStateFlags: nil, updateResult: nil, installDirectory: name,
                    steamAppsDirectory: root, manifestURL: nil)
            }
            #expect(LibraryProgramLocation.directory(for: .emptyGame, steamSnapshot: snapshot("Test Game")) == directory)
            #expect(LibraryProgramLocation.directory(for: .emptyGame, steamSnapshot: snapshot("..")) == nil)
            #expect(LibraryProgramLocation.directory(for: .emptyGame, steamSnapshot: snapshot("missing")) == nil)
        }
    }

    @Test func jx3GetsOrdinaryManagementWithoutLosingIdentityOrEdits() throws {
        let bottle = URL(fileURLWithPath: "/fixture/Games")
        var discovered = Game.emptyGame
        discovered.id = OnlineGameMode.jx3GameID
        discovered.isCustom = false
        discovered.isNative = false
        discovered.appExeURL = bottle.appendingPathComponent("drive_c/SeasunGame/SeasunGame.exe")
        discovered.appNames = ["SeasunGame.exe"]
        let initial = try #require(StandardLibraryJX3.entry(discovered: discovered, existing: nil,
            bottle: bottle, runtimeKind: "bundledWine", crossOverPath: nil, hidden: []))
        #expect(initial.isCustom == true)
        #expect(initial.installedBottleURL == bottle)
        #expect(OnlineGameMode.isJX3(initial))
        #expect(discovered.isCustom == false) // Dedicated-mode discovery is unchanged.
        var edited = initial
        edited.name = "我的启动器"
        edited.headerImage = "https://example.invalid/cover.png"
        let refreshed = try #require(StandardLibraryJX3.entry(discovered: discovered, existing: edited,
            bottle: bottle, runtimeKind: "bundledWine", crossOverPath: nil, hidden: []))
        #expect(refreshed.name == edited.name)
        #expect(refreshed.headerImage == edited.headerImage)
        #expect(refreshed.appExeURL == discovered.appExeURL)
        for owner in [Optional(bottle), nil] {
            let identity = GameRemovalService.identity(executable: discovered.appExeURL!, bottle: owner)
            #expect(StandardLibraryJX3.entry(discovered: discovered, existing: edited,
                bottle: bottle, runtimeKind: "bundledWine", crossOverPath: nil, hidden: [identity]) == nil)
        }
    }

    private func launcherShortcut(target: String, arguments: String = "\0", workingDirectory: String? = nil) -> Data {
        let path = Array(target.utf8) + [0]
        var bytes = [UInt8](repeating: 0, count: 76 + 28)
        func put(_ value: Int, at offset: Int) {
            for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
        }
        put(76, at: 0)
        bytes.replaceSubrange(4..<20, with: [1, 20, 2, 0, 0, 0, 0, 0, 192, 0, 0, 0, 0, 0, 0, 70])
        put(2 | 0x80 | 32 | (workingDirectory == nil ? 0 : 16), at: 20)
        put(1, at: 60)
        put(28 + path.count, at: 76)
        put(28, at: 80)
        put(1, at: 84)
        put(28, at: 92)
        bytes += path
        for value in [workingDirectory, arguments].compactMap({ $0 }) {
            let count = value.utf16.count
            bytes += [UInt8(truncatingIfNeeded: count), UInt8(truncatingIfNeeded: count >> 8)]
            bytes += value.data(using: .utf16LittleEndian)!
        }
        return Data(bytes)
    }

    @Test func installerJX3ShortcutIsHiddenFromSharedLibraryWithoutChangingSavedEntries() throws {
        try withRoot { root in
            let bottle = root.resolvingSymlinksInPath()
            let executable = bottle.appendingPathComponent("drive_c/SeasunGame/SeasunGame.exe")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x4d, 0x5a]).write(to: executable)
            var canonical = Game.emptyGame
            canonical.id = OnlineGameMode.jx3GameID
            canonical.isNative = false
            canonical.isCustom = true
            canonical.installedBottleURL = bottle
            canonical.appExeURL = executable
            var duplicate = canonical
            duplicate.id = "installer-shortcut"
            duplicate.name = "剑网3系列启动器"
            duplicate.appExeURL = bottle.appendingPathComponent("剑网3系列启动器.lnk")
            let shortcut = launcherShortcut(target: "C:\\SeasunGame\\SeasunGame.exe", workingDirectory: "C:\\SeasunGame\0")
            try shortcut.write(to: duplicate.appExeURL!)
            let library = LibraryPageGlobals(loadSavedLibrary: false)
            library.customAddedGames = [duplicate, canonical]

            #expect(library.allGames.map(\.id) == [canonical.id])
            #expect(library.filteredGames.map(\.id) == [canonical.id])
            #expect(library.customAddedGames.map(\.id) == [duplicate.id, canonical.id])
            #expect(try Data(contentsOf: duplicate.appExeURL!) == shortcut)
            #expect(StandardLibraryJX3.removingDuplicateShortcuts(from: [duplicate]).map(\.id) == [duplicate.id])
            library.customAddedGames = [canonical]
            library.customAddedGames.append(duplicate) // A later installer refresh uses the same shared list.
            #expect(library.allGames.map(\.id) == [canonical.id])
            #expect(library.customAddedGames.count == 2)
        }
    }

    @Test func distinctJX3ShortcutIntentsAndOtherInstallationsStayVisible() throws {
        try withRoot { root in
            let bottle = root.resolvingSymlinksInPath()
            let executable = bottle.appendingPathComponent("drive_c/SeasunGame/SeasunGame.exe")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x4d, 0x5a]).write(to: executable)
            var canonical = Game.emptyGame
            canonical.id = OnlineGameMode.jx3GameID
            canonical.isNative = false
            canonical.isCustom = true
            canonical.installedBottleURL = bottle
            canonical.appExeURL = executable
            var shortcut = canonical
            shortcut.id = "shortcut"
            shortcut.appExeURL = bottle.appendingPathComponent("剑网3系列启动器.lnk")
            func retained(_ candidate: Game) -> Bool {
                StandardLibraryJX3.removingDuplicateShortcuts(from: [canonical, candidate]).map(\.id) == [canonical.id, candidate.id]
            }

            try launcherShortcut(target: "C:\\SeasunGame\\SeasunGame.exe", arguments: "--custom-profile").write(to: shortcut.appExeURL!)
            #expect(retained(shortcut))
            try launcherShortcut(target: "C:\\SeasunGame\\SeasunGame.exe", workingDirectory: "C:\\Other").write(to: shortcut.appExeURL!)
            #expect(retained(shortcut))
            try launcherShortcut(target: "C:\\Other\\SeasunGame.exe").write(to: shortcut.appExeURL!)
            #expect(retained(shortcut))
            try launcherShortcut(target: "C:\\SeasunGame\\SeasunGame.exe").write(to: shortcut.appExeURL!)
            shortcut.installedBottleURL = bottle.appendingPathComponent("AnotherBottle")
            #expect(retained(shortcut))
            shortcut.installedBottleURL = bottle
            shortcut.appExeURL = bottle.appendingPathComponent("我的启动器.lnk")
            try launcherShortcut(target: "C:\\SeasunGame\\SeasunGame.exe").write(to: shortcut.appExeURL!)
            #expect(retained(shortcut))
            shortcut.appExeURL = bottle.appendingPathComponent("剑网3系列启动器.lnk")
            try Data([0, 1, 2]).write(to: shortcut.appExeURL!)
            #expect(retained(shortcut))
        }
    }
}
