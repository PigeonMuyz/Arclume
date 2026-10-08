import Foundation
import Testing
@testable import Arclume

struct LibraryLifecycleTests {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("LibraryLifecycle-\(UUID().uuidString)")
    }

    @Test func runtimeAdoptionPreservesLegacyBottlePreference() throws {
        let name = "RuntimePolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let old = URL(fileURLWithPath: "/tmp/LegacyBottle")
        let selected = BundledRuntimePolicy.adopt(defaults: defaults, selectedBottle: old.absoluteString, online: false)
        #expect(selected == BundledWineRuntime.standardSteamPrefixURL.absoluteString)
        #expect(defaults.string(forKey: "standard-game-runtime-crossover-bottle") == old.absoluteString)
        #expect(defaults.string(forKey: StandardGameRuntimeKind.defaultsKey) == "bundledWine")
        _ = BundledRuntimePolicy.adopt(defaults: defaults, selectedBottle: selected, online: false)
        #expect(defaults.string(forKey: "standard-game-runtime-crossover-bottle") == old.absoluteString)
        var legacy = Game.emptyGame
        legacy.isNative = false
        legacy.installedRuntimeKind = "crossOver"
        #expect(BundledRuntimePolicy.needsReconfiguration(legacy))
    }

    @Test func metadataUsesSafeImagesAndOnlyFillsMissingFields() throws {
        let json = #"{"id":194558,"name":"Arknights: Endfield","summary":"Summary","cover":{"id":1,"url":"//images.igdb.com/igdb/image/upload/t_thumb/test.jpg"},"genres":[{"id":12,"name":"RPG"}]}"#
        let metadata = try JSONDecoder().decode(GameDBMetadata.self, from: Data(json.utf8))
        var game = Game.emptyGame
        game.name = "手工名称"
        game.shortDescription = "手工简介"
        game.appExeURL = URL(fileURLWithPath: "/tmp/Endfield.exe")
        game.gameDBLink = GameDBLink(metadata: metadata, fetchedAt: Date())
        let result = GameDBMetadataResolver.resolve(game)
        #expect(result.name == game.name)
        #expect(result.shortDescription == "手工简介")
        #expect(result.detailedDescription == "Summary")
        #expect(result.appExeURL == game.appExeURL)
        #expect(result.headerImage.contains("t_cover_big_2x"))
        #expect(GameDBMetadataService.artworkURL(.init(id: 1, url: "https://untrusted.example/a.jpg")) == nil)
        #expect(GameDBMetadataService.bucket(for: "Arknights: Endfield") == "ar")
        #expect(GameDBMetadataService.bucket(for: "A Way Out") == "a")
        #expect(GameDBMetadataService.bucket(for: "终末地") == "@")
        let restored = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        #expect(restored.gameDBLink?.metadata.id == 194558)
    }

    private func game(in bottle: URL) throws -> URL {
        let directory = bottle.appendingPathComponent("drive_c/Program Files/Hypergryph Launcher/games/Arknights Endfield")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Endfield_Data"), withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("Endfield.exe")
        try Data([0x4d, 0x5a]).write(to: executable)
        try Data([0x4d, 0x5a]).write(to: directory.appendingPathComponent("UnityPlayer.dll"))
        try Data().write(to: directory.appendingPathComponent("Endfield_Data/boot.config"))
        return executable
    }

    @Test func removalPlanRetainsSharedLauncherAndDoesNotDeleteFiles() throws {
        let bottle = root()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let executable = try game(in: bottle)
        let plan = try GameRemovalService.plan(executable: executable, bottle: bottle, ownedBottles: [bottle], linkedExecutables: [])
        #expect(plan.launcher != nil)
        #expect(FileManager.default.fileExists(atPath: executable.path))
        let sibling = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("OtherGame")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
        #expect(try GameRemovalService.plan(executable: executable, bottle: bottle, ownedBottles: [bottle], linkedExecutables: []).launcher == nil)
        #expect(throws: GameRemovalError.self) {
            try GameRemovalService.plan(executable: executable, bottle: bottle, ownedBottles: [], linkedExecutables: [])
        }
    }

    @Test func removalRejectsLinkedContentAndUnknownExecutable() throws {
        let bottle = root()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let executable = try game(in: bottle)
        let link = executable.deletingLastPathComponent().appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/tmp"))
        #expect(throws: GameRemovalError.self) {
            try GameRemovalService.plan(executable: executable, bottle: bottle, ownedBottles: [bottle], linkedExecutables: [])
        }
        #expect(GameRemovalService.identity(executable: executable, bottle: bottle) == GameRemovalService.identity(executable: executable.standardizedFileURL, bottle: bottle))
    }
}
