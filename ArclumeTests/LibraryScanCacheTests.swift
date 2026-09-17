import Foundation
import Combine
import Testing
@testable import Arclume

struct LibraryScanCacheTests {
    @Test @MainActor func unchangedScanDoesNotPublishAndDeletionClearsOnlyScannedSelection() {
        let model = LibraryPageGlobals()
        var game = Game.emptyGame
        game.id = "scan-fixture"
        game.name = "Fixture"
        game.isCustom = false
        model.games = [game]
        model.selectedGame = game
        model.showDetailView = true
        var publications = 0
        let observation = model.$games.dropFirst().sink { _ in publications += 1 }
        model.applyScannedGames([game])
        #expect(publications == 0)
        #expect(model.selectedGame?.id == game.id)
        model.applyScannedGames([])
        #expect(publications == 1)
        #expect(model.selectedGame == nil)
        #expect(!model.showDetailView)
        withExtendedLifetime(observation) { }
    }

    @Test func scannerReusesManifestsAndReconcilesAddedChangedDeletedGames() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        try fixture.install("10", name: "First")
        let scanner = SteamLibraryScanner()
        let first = try await scanner.scan(fixture.root, native: false)
        #expect(first.count == 1)
        #expect(first.first?.appNames == ["First.exe"])
        // Seed a new worker exactly as the next launch does. Reuse avoids recursive discovery.
        let restarted = SteamLibraryScanner()
        await restarted.seed(first)
        try Data().write(to: fixture.root.appendingPathComponent("common/First/Extra.exe"))
        #expect(try await restarted.scan(fixture.root, native: false) == first)
        try fixture.install("10", name: "Updated")
        try fixture.install("20", name: "Second")
        let changed = try await restarted.scan(fixture.root, native: false)
        #expect(changed.count == 2)
        #expect(changed.first?.appNames == ["Updated.exe"])
        try FileManager.default.removeItem(at: fixture.manifest("10"))
        let deleted = try await restarted.scan(fixture.root, native: false)
        #expect(deleted.map { $0.fields["appid"] } == ["20"])
    }

    @Test func unreadableLibraryThrowsAndPartialManifestRetainsPreviousRecord() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        try fixture.install("10", name: "Game")
        let scanner = SteamLibraryScanner()
        let initial = try await scanner.scan(fixture.root, native: true)
        try Data("partial Steam write".utf8).write(to: fixture.manifest("10"))
        #expect(try await scanner.scan(fixture.root, native: true) == initial)
        do {
            _ = try await scanner.scan(fixture.root.appendingPathComponent("unmounted"), native: true)
            Issue.record("An unavailable library must not be reported as empty")
        } catch { }
    }

    @Test func missingGameDirectoryInvalidatesInstalledState() async throws {
        let fixture = try ScanFixture()
        defer { fixture.remove() }
        try fixture.install("10", name: "Game")
        let scanner = SteamLibraryScanner()
        _ = try await scanner.scan(fixture.root, native: false)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("common/Game"))
        let result = try await scanner.scan(fixture.root, native: false)
        #expect(result.first?.fields["StateFlags"] == "0")
        #expect(result.first?.directoryExists == false)
    }

    @Test @MainActor func snapshotRoundTripIncludesEmptyLibraryAndRejectsWrongContextOrCorruption() throws {
        let suite = "LibraryScanCacheTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = LibrarySnapshot(context: "fixture-prefix", games: [], records: [], metadata: [],
            folders: [], ownership: [10: [.native]], sessions: [.native: "test-account"])
        snapshot.save(to: defaults)
        let restored = try #require(LibrarySnapshot.read(from: defaults, context: "fixture-prefix"))
        #expect(restored.games.isEmpty)
        #expect(restored.ownership[10] == [.native])
        #expect(restored.sessions[.native] == "test-account")
        var populated = snapshot
        var game = Game.emptyGame
        game.id = "fixture-game"
        game.name = "Cached title"
        populated.games = [game]
        populated.save(to: defaults)
        #expect(LibrarySnapshot.read(from: defaults, context: "fixture-prefix")?.games.first?.name == "Cached title")
        #expect(LibrarySnapshot.read(from: defaults, context: "different-prefix") == nil)
        defaults.set(Data("corrupted".utf8), forKey: LibrarySnapshot.defaultsKey)
        #expect(LibrarySnapshot.read(from: defaults, context: "fixture-prefix") == nil)
    }
}

private nonisolated struct ScanFixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("arclume-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func manifest(_ id: String) -> URL { root.appendingPathComponent("appmanifest_\(id).acf") }
    func install(_ id: String, name: String) throws {
        let directory = root.appendingPathComponent("common/\(name)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("\(name).exe"))
        let text = "\"AppState\" { \"appid\" \"\(id)\" \"name\" \"\(name)\" \"installdir\" \"\(name)\" \"StateFlags\" \"4\" }"
        try Data(text.utf8).write(to: manifest(id))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
