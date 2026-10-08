import Foundation
import Testing
@testable import Arclume

struct PortableGreenPreparationTests {
    @Test func unsafeGreenRulesAreRejected() throws {
        let base: [String: Any] = [
            "id": "test", "name": "Test", "kind": "application", "installDirectory": "PortableApps/Test",
            "executable": "Test.exe", "alternateExecutables": [], "requiredFiles": ["helper.exe"],
            "defaultArguments": [], "portable": ["scriptPolicy": "skip", "preservePaths": []],
            "userDataDirectory": "AppData/Roaming/Test"
        ]
        for paths in [["../outside"], ["yy"], ["yy/ad", "YY/AD"], ["yy/ad", "yy/ad/banner"], ["yy/NUL"], []] {
            var rule = base
            rule["greenPreparation"] = ["blockedDirectories": paths]
            let encoded = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "rules": [rule]])
            #expect(throws: (any Error).self) { try GameAdaptationRules.decode(encoded) }
        }
    }

    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("GreenTests-\(UUID().uuidString)")
        let rule = try #require(GameAdaptationRules.rule(id: "yyspeak-portable"))
        let exe = rule.directory(in: root).appendingPathComponent(rule.executable)
        let data = root.appendingPathComponent("drive_c/users/test/AppData/Roaming/duowan")
        for file in [exe, exe.deletingLastPathComponent().appendingPathComponent("yylauncher.exe"),
                     data.appendingPathComponent("yy/mainframe/ad/banner.dat"), data.appendingPathComponent("yy/account.db"),
                     data.appendingPathComponent("OtherSDK/account.db")] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("MZ-original".utf8).write(to: file)
        }
        return (root, exe, data)
    }

    @Test func blocksAdsPreservesAccountsAndSupportsIdempotentRestore() throws {
        let (bottle, exe, data) = try fixture(); defer { try? FileManager.default.removeItem(at: bottle) }
        let plan = try PortableGreenPreparation.plan(executable: exe, bottle: bottle, ownedBottles: [bottle])
        let first = PortableGreenPreparation.apply(plan, ownedBottles: [bottle], requireIdle: {})
        #expect(first.error == nil)
        #expect(first.changed == plan.targets.count)
        for target in plan.targets {
            #expect(PortableGreenPreparation.isBlocker(target, ruleID: plan.ruleID))
            #expect((try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue == 0o444)
        }
        #expect(try String(contentsOf: data.appendingPathComponent("yy/account.db"), encoding: .utf8) == "MZ-original")
        #expect(try String(contentsOf: data.appendingPathComponent("OtherSDK/account.db"), encoding: .utf8) == "MZ-original")
        let second = PortableGreenPreparation.apply(plan, ownedBottles: [bottle], requireIdle: {})
        #expect(second.error == nil)
        #expect(second.changed == 0)
        #expect(second.recovery == nil)
        let recovery = try #require(first.recovery)
        #expect(PortableGreenPreparation.latestRecovery(plan)?.path == recovery.path)
        try PortableGreenPreparation.restore(recovery, bottle: bottle, ownedBottles: [bottle], requireIdle: {})
        #expect(try String(contentsOf: data.appendingPathComponent("yy/mainframe/ad/banner.dat"), encoding: .utf8) == "MZ-original")
        #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("yy/cache/loginbanner").path))
        #expect(PortableGreenPreparation.latestRecovery(plan) == nil)
    }

    @Test func runningForeignAndSymlinkedTargetsAreRejected() throws {
        let (bottle, exe, data) = try fixture(); defer { try? FileManager.default.removeItem(at: bottle) }
        #expect(throws: (any Error).self) { try PortableGreenPreparation.plan(executable: exe, bottle: bottle, ownedBottles: []) }
        let plan = try PortableGreenPreparation.plan(executable: exe, bottle: bottle, ownedBottles: [bottle])
        let blocked = PortableGreenPreparation.apply(plan, ownedBottles: [bottle], requireIdle: { throw GameRemovalError.running })
        #expect(blocked.error != nil && blocked.changed == 0 && blocked.recovery == nil)
        let ad = data.appendingPathComponent("yy/mainframe/ad")
        try FileManager.default.moveItem(at: ad, to: data.appendingPathComponent("original-ad"))
        try FileManager.default.createSymbolicLink(at: ad, withDestinationURL: data.appendingPathComponent("original-ad"))
        #expect(throws: (any Error).self) { try PortableGreenPreparation.plan(executable: exe, bottle: bottle, ownedBottles: [bottle]) }
        #expect(PortableGreenPreparation.apply(plan, ownedBottles: [bottle], requireIdle: {}).changed == 0)
    }

    @Test func partialFailureHasRecoveryAndChangedBlockersAreNotDeleted() throws {
        let (bottle, exe, _) = try fixture(); defer { try? FileManager.default.removeItem(at: bottle) }
        let plan = try PortableGreenPreparation.plan(executable: exe, bottle: bottle, ownedBottles: [bottle])
        var calls = 0
        let partial = PortableGreenPreparation.apply(plan, ownedBottles: [bottle], requireIdle: {
            calls += 1
            if calls == 3 { throw GameRemovalError.running }
        })
        #expect(partial.changed == 1 && partial.error != nil)
        let recovery = try #require(partial.recovery)
        let target = try #require(plan.targets.first)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        try Data("user changed".utf8).write(to: target)
        #expect(throws: (any Error).self) { try PortableGreenPreparation.restore(recovery, bottle: bottle, ownedBottles: [bottle], requireIdle: {}) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "user changed")
    }
}
