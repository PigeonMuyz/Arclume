import Foundation
import Testing
@testable import Arclume

struct GameAssociatedDataTests {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("AssociatedDataTests-\(UUID().uuidString)")
    }
    private func fixture(_ bottle: URL) throws -> GameRemovalPlan {
        let rule = try #require(GameAdaptationRules.rule(id: "endfield"))
        let directory = rule.directory(in: bottle)
        for file in [rule.executable] + rule.requiredFiles {
            let url = directory.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x4d, 0x5a]).write(to: url)
        }
        return try GameRemovalService.plan(executable: directory.appendingPathComponent(rule.executable), bottle: bottle, ownedBottles: [bottle], linkedExecutables: [])
    }

    @Test func bundledJSONHasStablePathsAndLaunchDefaults() throws {
        #expect(GameAdaptationRules.all.count >= 2)
        let rule = try #require(GameAdaptationRules.rule(id: "endfield"))
        #expect(rule.launcherID == "hypergryph-launcher")
        #expect(rule.gameDBID == 194558)
        #expect(rule.windowsDirectory == #"C:\Program Files\Hypergryph Launcher\games\Arknights Endfield"#)
        #expect(rule.registryKey == #"Software\\Hypergryph\\Endfield"#)
    }

    @Test func ruleDecoderRejectsTraversalAndUnknownVersion() throws {
        let valid = #"{"schemaVersion":1,"rules":[{"id":"test","name":"Test","kind":"game","installDirectory":"Games/Test","executable":"Test.exe","alternateExecutables":[],"requiredFiles":[],"defaultArguments":[]}]}"#
        #expect(try GameAdaptationRules.decode(Data(valid.utf8)).count == 1)
        for invalid in [valid.replacingOccurrences(of: "Games/Test", with: "Games/../Shared"), valid.replacingOccurrences(of: "schemaVersion\":1", with: "schemaVersion\":9")] {
            #expect(throws: (any Error).self) { try GameAdaptationRules.decode(Data(invalid.utf8)) }
        }
        #expect(!GameAdaptationRules.safeRelativePath("/tmp"))
        #expect(!GameAdaptationRules.safeRelativePath("Games//Test"))
    }

    @Test func classifiesOnlyVerifiedDataNames() throws {
        let rule = try #require(GameAdaptationRules.rule(id: "endfield"))
        #expect(GameAssociatedDataService.category(for: "Player.log", rule: rule) == .logs)
        #expect(GameAssociatedDataService.category(for: "ClientData", rule: rule) == .local)
        #expect(GameAssociatedDataService.category(for: "sdk_data_f654bce49f1470d3852027a0da9f09a4", rule: rule) == .login)
        #expect(GameAssociatedDataService.category(for: "sdk_data_unknown", rule: rule) == nil)
        #expect(GameAssociatedDataService.category(for: "OtherGame", rule: rule) == nil)
    }

    @Test func scanSeparatesLogsSettingsLoginAndPreservesSharedData() throws {
        let bottle = root()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let plan = try fixture(bottle)
        let userData = bottle.appendingPathComponent("drive_c/users/test/AppData/LocalLow/Hypergryph/Endfield")
        for name in ["Player.log", "ClientData/settings.json", "sdkdata/login", "Unknown/keep"] {
            let url = userData.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: url)
        }
        let items = try GameAssociatedDataService.scan(plan)
        #expect(Set(items.map(\.category)) == [.logs, .local, .login])
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.bytes > 0 })
        #expect(FileManager.default.fileExists(atPath: userData.appendingPathComponent("Unknown/keep").path))
        #expect(FileManager.default.fileExists(atPath: plan.executable.path))
    }

    @Test func scanRejectsSymlinkedUserData() throws {
        let bottle = root()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let plan = try fixture(bottle)
        let data = bottle.appendingPathComponent("drive_c/users/test/AppData/LocalLow/Hypergryph/Endfield")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: data.appendingPathComponent("sdklogs"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
        #expect(throws: (any Error).self) { try GameAssociatedDataService.scan(plan) }
    }

    @Test func registrySplitPreservesNeighborsAndHandlesMultilineValues() throws {
        let key = #"Software\\Hypergryph\\Endfield"#
        let before = "WINE REGISTRY Version 2\n\n[Software\\\\Other]\n\"value\"=\"keep\"\n\n"
        let selected = "[\(key)] 123\n\"binary\"=hex:01,\\\n  02,03\n\n[\(key)\\\\Child]\n\"x\"=dword:00000001\n\n"
        let after = "[\(key)Other]\n\"value\"=\"keep too\"\n"
        let split = try GameAssociatedDataService.splitRegistry(before + selected + after, registryKey: key)
        #expect(split.remaining == before + after)
        #expect(split.selected + "\n" == selected)
        #expect(throws: (any Error).self) { try GameAssociatedDataService.splitRegistry("invalid", registryKey: key) }
    }

    @Test func knownNSISInstallerReceivesFixedDefaultDirectoryWithoutSilentInstall() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let exe = directory.appendingPathComponent("HypergryphLauncher_fixture.exe")
        try Data("MZ_NullsoftInst".utf8).write(to: exe)
        let args = try WindowsInstallerService.arguments(for: exe)
        #expect(args.dropFirst().joined(separator: " ") == #"/D=C:\Program Files\Hypergryph Launcher"#)
        #expect(!args.contains("/S"))
        try Data("MZ_unknown".utf8).write(to: exe)
        #expect(throws: (any Error).self) { try WindowsInstallerService.arguments(for: exe) }
    }

    @Test func registryReplacementIsPrivateAndRejectsStalePreview() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("user.reg")
        let original = Data("fixture old".utf8), replacement = Data("fixture kept keys".utf8)
        try original.write(to: url)
        try GameAssociatedDataService.replaceRegistryFile(url, expected: original, replacement: replacement)
        #expect(try Data(contentsOf: url) == replacement)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #expect(throws: (any Error).self) {
            try GameAssociatedDataService.replaceRegistryFile(url, expected: original, replacement: Data())
        }
        #expect(try Data(contentsOf: url) == replacement)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["user.reg"])
    }
}
