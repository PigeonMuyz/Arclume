import Foundation
import Testing
@testable import Arclume

struct LauncherRemovalTests {
    private func fixture() throws -> (URL, URL, URL) {
        let bottle = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("LauncherRemovalTests-\(UUID().uuidString)")
        let launcher = try #require(GameAdaptationRules.rule(id: "hypergryph-launcher"))
        let game = try #require(GameAdaptationRules.rule(id: "endfield"))
        let directory = launcher.directory(in: bottle)
        let executable = directory.appendingPathComponent(launcher.executable)
        let gameExecutable = game.directory(in: bottle).appendingPathComponent(game.executable)
        for file in [executable, directory.appendingPathComponent("1.5.0/Games.exe"), directory.appendingPathComponent("Cache/cache.bin"), gameExecutable]
            + game.requiredFiles.map({ game.directory(in: bottle).appendingPathComponent($0) }) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x4d, 0x5a]).write(to: file)
        }
        return (bottle, executable, gameExecutable)
    }

    @Test func discoversRelatedGameEvenWhenNotInLibrary() throws {
        let (bottle, exe, game) = try fixture()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let plan = try LauncherRemovalService.plan(executable: exe, bottle: bottle, ownedBottles: [bottle], linkedExecutables: [])
        #expect(plan.hasGames)
        #expect(plan.canRemoveGames)
        #expect(plan.games.map(\.executable) == [game])
        #expect(plan.entries.count == 3)
        #expect(!plan.entries.contains { game.path.hasPrefix($0.url.path + "/") })
    }

    @Test func launcherOnlyRemovalKeepsGameAndUnknownFiles() throws {
        let (bottle, exe, game) = try fixture()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let unknown = exe.deletingLastPathComponent().appendingPathComponent("user-note.txt")
        try Data("keep".utf8).write(to: unknown)
        let plan = try LauncherRemovalService.plan(executable: exe, bottle: bottle, ownedBottles: [bottle], linkedExecutables: [game])
        #expect(plan.retainedEntries.contains(unknown))
        let trash = bottle.appendingPathComponent("fixture-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var completed: [String] = []
        try LauncherRemovalService.trashEntries(plan, completed: &completed) { source in
            try FileManager.default.moveItem(at: source, to: trash.appendingPathComponent(source.lastPathComponent))
        }
        #expect(completed.count == 3)
        #expect(!FileManager.default.fileExists(atPath: exe.path))
        #expect(FileManager.default.fileExists(atPath: game.path))
        #expect(FileManager.default.fileExists(atPath: unknown.path))
    }

    @Test func unknownGameDisablesRemoveTogetherButNotLauncherOnly() throws {
        let (bottle, exe, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let unknown = exe.deletingLastPathComponent().appendingPathComponent("games/Unrecognized")
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        let plan = try LauncherRemovalService.plan(executable: exe, bottle: bottle, ownedBottles: [bottle], linkedExecutables: [])
        #expect(plan.hasGames)
        #expect(!plan.canRemoveGames)
        #expect(plan.unknownGames.contains { $0.path == unknown.path })
        #expect(!plan.entries.isEmpty)
    }

    @Test func changedOrLinkedLauncherFilesAreRejectedBeforeMoving() throws {
        let (bottle, exe, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let plan = try LauncherRemovalService.plan(executable: exe, bottle: bottle, ownedBottles: [bottle], linkedExecutables: [])
        let cache = exe.deletingLastPathComponent().appendingPathComponent("Cache")
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: URL(fileURLWithPath: "/tmp"))
        var completed: [String] = []
        #expect(throws: (any Error).self) { try LauncherRemovalService.trashEntries(plan, completed: &completed) { _ in Issue.record("Must not move anything") } }
        #expect(completed.isEmpty)
        #expect(throws: (any Error).self) { try LauncherRemovalService.plan(executable: exe, bottle: bottle, ownedBottles: [], linkedExecutables: []) }
    }

    @Test func partialFailureReportsOnlyCompletedEntries() throws {
        let (bottle, exe, game) = try fixture()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let plan = try LauncherRemovalService.plan(executable: exe, bottle: bottle, ownedBottles: [bottle], linkedExecutables: [])
        let trash = bottle.appendingPathComponent("fixture-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var calls = 0
        var completed: [String] = []
        #expect(throws: (any Error).self) {
            try LauncherRemovalService.trashEntries(plan, completed: &completed) { source in
                calls += 1
                if calls == 2 { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.moveItem(at: source, to: trash.appendingPathComponent(source.lastPathComponent))
            }
        }
        #expect(completed == [plan.entries[0].url.path])
        #expect(FileManager.default.fileExists(atPath: game.path))
        #expect(FileManager.default.fileExists(atPath: plan.entries[1].url.path))
    }
}
