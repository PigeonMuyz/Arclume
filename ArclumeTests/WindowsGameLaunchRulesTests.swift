import Foundation
import Testing
@testable import Arclume

struct WindowsGameLaunchRulesTests {
    private func makeGame(in bottle: URL, path: String = "Program Files/Hypergryph Launcher/games/Arknights Endfield") throws -> URL {
        let directory = bottle.appendingPathComponent("drive_c/\(path)")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Endfield_Data"), withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("Endfield.exe")
        try Data([0x4d, 0x5a]).write(to: executable)
        try Data([0x4d, 0x5a]).write(to: directory.appendingPathComponent("UnityPlayer.dll"))
        try Data("hdr-display-enabled=0".utf8).write(to: directory.appendingPathComponent("Endfield_Data/boot.config"))
        return executable
    }

    private func temporaryBottle() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("EndfieldRules-\(UUID().uuidString)")
    }

    @Test func discoversDirectGameOnceAndUsesVerifiedArguments() throws {
        let bottle = temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let executable = try makeGame(in: bottle)
        let candidates = WindowsGameLaunchRules.discover(in: bottle)
        #expect(candidates.count == 1)
        #expect(candidates.first?.entry == executable.resolvingSymlinksInPath())
        #expect(candidates.first?.name == "明日方舟：终末地")
        #expect(WindowsGameLaunchRules.arguments(for: executable, userArguments: []) == [
            "-launcher_lang=zh-cn", "-launcher_sub_channel=1", "-screen-fullscreen", "0",
            "-screen-width", "1280", "-screen-height", "720"
        ])
    }

    @Test func preservesExplicitUserOverrides() throws {
        let bottle = temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let executable = try makeGame(in: bottle)
        let overrides = ["-screen-width", "1600", "-screen-fullscreen=1", "-launcher_lang=en-us", "-custom"]
        let arguments = WindowsGameLaunchRules.arguments(for: executable, userArguments: overrides)
        #expect(arguments == ["-launcher_sub_channel=1", "-screen-height", "720"] + overrides)
    }

    @Test func rejectsIncompleteInstallAndDoesNotAlterOtherPrograms() throws {
        let bottle = temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let executable = try makeGame(in: bottle)
        let launcher = executable.deletingLastPathComponent().appendingPathComponent("Games.exe")
        #expect(WindowsGameLaunchRules.arguments(for: launcher, userArguments: ["--reason=0"]) == ["--reason=0"])
        try FileManager.default.removeItem(at: executable.deletingLastPathComponent().appendingPathComponent("UnityPlayer.dll"))
        #expect(!WindowsGameLaunchRules.isEndfield(executable))
        #expect(WindowsGameLaunchRules.discover(in: bottle).isEmpty)
    }

    @Test func rejectsCustomInstallOutsideManagedRuleDirectory() throws {
        let bottle = temporaryBottle()
        defer { try? FileManager.default.removeItem(at: bottle) }
        let executable = try makeGame(in: bottle, path: "Games/Endfield")
        #expect(WindowsGameLaunchRules.discover(in: bottle).isEmpty)
        #expect(throws: (any Error).self) { try GameAdaptationRules.validate(executable, bottle: bottle) }
        let candidate = InstalledProgramCandidate(entry: executable, executable: executable, name: "终末地", fingerprint: "1")
        let launcher = InstalledProgramCandidate(entry: bottle.appendingPathComponent("Launcher.lnk"),
            executable: bottle.appendingPathComponent("Games.exe"), name: "鹰角启动器", fingerprint: "1")
        let found = InstalledProgramDiscovery.added(after: [], current: [launcher, candidate])
        #expect(found.count == 2)
        #expect(found.contains(candidate))
        #expect(found.contains(launcher))
        #expect(InstalledProgramDiscovery.added(after: [launcher, candidate], current: found).isEmpty)
    }

    @Test func fastProbeCannotFollowGameSymlinkOutsidePrefix() throws {
        let bottle = temporaryBottle()
        let external = temporaryBottle()
        defer {
            try? FileManager.default.removeItem(at: bottle)
            try? FileManager.default.removeItem(at: external)
        }
        let target = try makeGame(in: external)
        let link = bottle.appendingPathComponent("drive_c/Program Files/Hypergryph Launcher/games/Arknights Endfield")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.deletingLastPathComponent())
        #expect(WindowsGameLaunchRules.discover(in: bottle).isEmpty)
    }
}
