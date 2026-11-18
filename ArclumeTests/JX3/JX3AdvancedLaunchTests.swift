import Foundation
import Testing

@testable import Arclume

@MainActor
struct JX3AdvancedLaunchTests {
    @Test func normalLaunchKeepsLauncherPayloadAndArguments() throws {
        let launcher = URL(fileURLWithPath: "/fixture/SeasunGame/SeasunGame.exe")
        let client = URL(fileURLWithPath: "/fixture/JX3/bin/zhcn_hd/JX3ClientX64.exe")
        let payload = URL(fileURLWithPath: "/fixture/SeasunGame/SeasunGame_2.0.0.525")
        let installation = OnlineGameInstallation(
            clientURL: client, launcherURL: launcher, workingDirectoryURL: payload
        )

        let target = try #require(installation.launchTarget(skipLauncher: false, clientArguments: ["-custom"]))

        #expect(target.executableURL == launcher)
        #expect(target.workingDirectoryURL == payload)
        #expect(target.arguments.isEmpty)
    }

    @Test func directLaunchUsesClientWorkingDirectoryAndExplicitArguments() throws {
        let launcher = URL(fileURLWithPath: "/fixture/SeasunGame/SeasunGame.exe")
        let client = URL(fileURLWithPath: "/fixture/JX3/bin/zhcn_hd/JX3ClientX64.exe")
        let installation = OnlineGameInstallation(
            clientURL: client, launcherURL: launcher,
            workingDirectoryURL: URL(fileURLWithPath: "/fixture/SeasunGame/CEF")
        )

        let target = try #require(installation.launchTarget(skipLauncher: true, clientArguments: ["-custom", "value"]))

        #expect(target.executableURL == client)
        #expect(target.workingDirectoryURL == client.deletingLastPathComponent())
        #expect(target.arguments == [OnlineGameInstallation.directClientArgument, "-custom", "value"])
    }

    @Test func wineAdaptersPassTheDirectTargetToTheChildProcess() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let bottle = fixture.appendingPathComponent("Games Fixture", isDirectory: true)
        let workingDirectory = bottle.appendingPathComponent("drive_c/SeasunGame/Game/JX3/bin/zhcn_hd/bin64", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let launcher = bottle.appendingPathComponent("drive_c/SeasunGame/SeasunGame.exe")
        let client = workingDirectory.appendingPathComponent("JX3ClientX64.exe")
        let installation = OnlineGameInstallation(clientURL: client, launcherURL: launcher)
        let target = try #require(installation.launchTarget(skipLauncher: true, clientArguments: ["-custom"]))

        let stub = fixture.appendingPathComponent("wine-stub")
        try """
        #!/bin/sh
        printf '%s\\n' "$PWD" "$WINEPREFIX" "$@"
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)

        for runtime in [OnlineGameRuntimeKind.bundledWine, .crossOver] {
            let process = OnlineGameLauncher.makeWineProcess(
                wineURL: stub, target: target, bottleURL: bottle,
                runtime: runtime, environment: ["WINEPREFIX": "/unrelated-prefix"]
            )
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let received = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").map(String.init)
            process.waitUntilExit()

            let receivedDirectory = try #require(received.first)
            let actualDirectory = URL(fileURLWithPath: receivedDirectory, isDirectory: true).resolvingSymlinksInPath()
            let prefixArguments = runtime == .crossOver ? ["--bottle", bottle.lastPathComponent] : []
            #expect(process.terminationStatus == 0)
            #expect(actualDirectory == workingDirectory.resolvingSymlinksInPath())
            #expect(Array(received.dropFirst()) == [bottle.path] + prefixArguments + [
                client.path, "DOTNOTSTARTGAMEBYJX3CLIENT.EXE", "-custom"
            ])
        }
    }

    @Test func directClientArgumentIsAddedOnceAndMissingClientDoesNotFallBack() throws {
        let launcher = URL(fileURLWithPath: "/fixture/SeasunGame/SeasunGame.exe")
        let client = URL(fileURLWithPath: "/fixture/JX3/bin/zhcn_hd/JX3ClientX64.exe")
        let installation = OnlineGameInstallation(clientURL: client, launcherURL: launcher)
        let target = try #require(installation.launchTarget(
            skipLauncher: true,
            clientArguments: ["-custom", "dotnotstartgamebyjx3client.exe", OnlineGameInstallation.directClientArgument]
        ))
        #expect(target.arguments == [OnlineGameInstallation.directClientArgument, "-custom"])
        #expect(installation.launchTarget(skipLauncher: true)?.arguments == [OnlineGameInstallation.directClientArgument])
        #expect(OnlineGameInstallation(clientURL: nil, launcherURL: launcher).launchTarget(skipLauncher: true) == nil)
    }

    @Test func directLaunchDoesNotFallBackWhenClientIsMissing() {
        let installation = OnlineGameInstallation(
            clientURL: nil, launcherURL: URL(fileURLWithPath: "/fixture/SeasunGame.exe")
        )
        #expect(installation.launchTarget(skipLauncher: true) == nil)
        #expect(installation.launchTarget(skipLauncher: false) != nil)
    }

    @Test func skipLauncherDefaultsOffAndSavedChoiceRoundTrips() throws {
        let legacy = try JSONDecoder().decode(GameOptionsData.self, from: Data("{}".utf8))
        let options = GameOptions(jx3SkipLauncher: true)
        options.set(data: legacy)
        #expect(!options.jx3SkipLauncher)

        options.jx3SkipLauncher = true
        let encoded = try JSONEncoder().encode(GameOptionsData(data: options))
        let restored = GameOptions()
        restored.set(data: try JSONDecoder().decode(GameOptionsData.self, from: encoded))
        #expect(restored.jx3SkipLauncher)
    }

    @Test func exactArrowAndMixedCaseLetterSequencesUnlock() {
        for keys in [["↑", "↑", "↓", "↓", "←", "←", "→", "→"],
                     ["W", "w", "s", "S", "A", "a", "d", "D"]] {
            var sequence = JX3AdvancedLaunchUnlockSequence()
            for key in keys.dropLast() {
                let unlocked = sequence.accept(key)
                #expect(!unlocked)
            }
            let unlocked = sequence.accept(keys.last!)
            #expect(unlocked)
        }
    }

    @Test func incorrectOrMixedSequencesStayLockedAndOverlappingPrefixRecovers() {
        var sequence = JX3AdvancedLaunchUnlockSequence()
        for key in ["w", "w", "s", "s", "a", "a", "d", "x", "↑", "↑", "s", "s", "a", "a", "d", "d"] {
            let unlocked = sequence.accept(key)
            #expect(!unlocked)
        }
        for key in ["w", "w", "w", "s", "s", "a", "a", "d"] {
            let unlocked = sequence.accept(key)
            #expect(!unlocked)
        }
        let unlocked = sequence.accept("d")
        #expect(unlocked)

        sequence = JX3AdvancedLaunchUnlockSequence()
        for key in ["s", "s", "a", "a", "d", "d"] {
            let unlocked = sequence.accept(key)
            #expect(!unlocked)
        }
    }
}
