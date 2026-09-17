import AppKit
import Foundation
import Testing
@testable import Arclume

@MainActor
struct ArclumeResetTests {
    private func fixture(_ body: (URL, String, String, UserDefaults, UserDefaults) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ResetTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let groupName = "reset.tests.group.\(UUID())", appName = "reset.tests.app.\(UUID())"
        let group = try #require(UserDefaults(suiteName: groupName))
        let app = try #require(UserDefaults(suiteName: appName))
        defer {
            group.removePersistentDomain(forName: groupName)
            app.removePersistentDomain(forName: appName)
            try? FileManager.default.removeItem(at: root)
        }
        group.set("jx3", forKey: "mode")
        group.set(["Games"], forKey: "warmup")
        app.set(true, forKey: ArclumeResetService.pendingKey)
        app.set("old", forKey: "windowState")
        try body(root, groupName, appName, group, app)
    }

    @Test func movesOnlyManagedDataAndClearsBothPreferenceDomains() throws {
        try fixture { root, groupName, appName, group, app in
            let support = root.appendingPathComponent("Arclume", isDirectory: true)
            let marker = support.appendingPathComponent("OnlineGameWinePrefixes/Games/drive_c/game.save")
            try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("saved".utf8).write(to: marker)
            let external = root.appendingPathComponent("OtherApp")
            try Data("keep".utf8).write(to: external)
            // Only a private fixture folder stands in for Trash; never use the user's Trash.
            let trash = root.appendingPathComponent("RecoveredArclume", isDirectory: true)
            try ArclumeResetService.reset(supportRoot: support, expectedParent: root,
                preferencesDomain: groupName, appDomain: appName) { try FileManager.default.moveItem(at: $0, to: trash) }
            #expect(!FileManager.default.fileExists(atPath: support.path))
            #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("OnlineGameWinePrefixes/Games/drive_c/game.save").path))
            #expect(try Data(contentsOf: external) == Data("keep".utf8))
            #expect(group.string(forKey: "mode") == nil)
            #expect(group.object(forKey: "warmup") == nil)
            #expect(group.bool(forKey: ArclumeResetService.legacyDefaultsKey))
            #expect(group.bool(forKey: ArclumeResetService.skipLegacyDataKey))
            #expect(app.persistentDomain(forName: appName)?.isEmpty != false)
        }
    }

    @Test func missingSupportStillResetsSettings() throws {
        try fixture { root, groupName, appName, group, app in
            try ArclumeResetService.reset(supportRoot: root.appendingPathComponent("Arclume"), expectedParent: root,
                preferencesDomain: groupName, appDomain: appName) { _ in Issue.record("Must not create or move missing data") }
            #expect(group.string(forKey: "mode") == nil)
            #expect(!app.bool(forKey: ArclumeResetService.pendingKey))
        }
    }

    @Test func moveFailurePreservesSettingsAndRetryIntent() throws {
        try fixture { root, groupName, appName, group, app in
            let support = root.appendingPathComponent("Arclume")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            #expect(throws: (any Error).self) {
                try ArclumeResetService.reset(supportRoot: support, expectedParent: root,
                    preferencesDomain: groupName, appDomain: appName) { _ in throw CocoaError(.fileWriteNoPermission) }
            }
            #expect(group.string(forKey: "mode") == "jx3")
            #expect(app.bool(forKey: ArclumeResetService.pendingKey))
            #expect(FileManager.default.fileExists(atPath: support.path))
        }
    }

    @Test func rejectsBroadTargetsAndRootSymlinks() throws {
        try fixture { root, groupName, appName, group, _ in
            let support = root.appendingPathComponent("Arclume")
            let external = root.appendingPathComponent("External")
            try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: support, withDestinationURL: external)
            for target in [root, external, support] {
                #expect(throws: (any Error).self) {
                    try ArclumeResetService.reset(supportRoot: target, expectedParent: root,
                        preferencesDomain: groupName, appDomain: appName) { _ in Issue.record("Unsafe target moved") }
                }
            }
            #expect(group.string(forKey: "mode") == "jx3")
            #expect(FileManager.default.fileExists(atPath: external.path))
        }
    }

    @Test func resetCommitRunsOnlyAfterSuccessfulDrain() async {
        var events: [String] = []
        var reply: Bool?
        let delegate = ArclumeAppDelegate(beginExit: { events.append("gate") }, stopWine: { events.append("stop") },
            cancelExit: { events.append("cancel") }, reportFailure: { _ in events.append("error") },
            finishExit: { events.append("commit") })
        _ = delegate.requestTermination { reply = $0 }
        for _ in 0..<100 where reply == nil { await Task.yield() }
        #expect(reply == true)
        #expect(events == ["gate", "stop", "commit"])
    }

    @Test func legacyBottleCleanupOnlyRemovesEmptyDirectory() throws {
        try fixture { root, _, _, _, _ in
            let legacy = root.appendingPathComponent("CXPBottles", isDirectory: true)
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            LegacyBottleDirectory.removeEmptyDirectory(in: root)
            #expect(!FileManager.default.fileExists(atPath: legacy.path))
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            let marker = legacy.appendingPathComponent("game.save")
            try Data("keep".utf8).write(to: marker)
            LegacyBottleDirectory.removeEmptyDirectory(in: root)
            #expect(try Data(contentsOf: marker) == Data("keep".utf8))
            let second = root.appendingPathComponent("Other", isDirectory: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            let link = second.appendingPathComponent("CXPBottles")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: legacy)
            LegacyBottleDirectory.removeEmptyDirectory(in: second)
            #expect(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
            #expect(FileManager.default.fileExists(atPath: marker.path))
        }
    }

    @Test func failedDrainNeverCommitsAndFailedCommitCancelsQuit() async {
        for failAtDrain in [true, false] {
            var committed = false, cancelled = false
            var reply: Bool?
            let delegate = ArclumeAppDelegate(beginExit: {}, stopWine: {
                if failAtDrain { throw CocoaError(.fileWriteNoPermission) }
            }, cancelExit: { cancelled = true }, reportFailure: { _ in }, finishExit: {
                committed = true
                throw CocoaError(.fileWriteUnknown)
            })
            _ = delegate.requestTermination { reply = $0 }
            for _ in 0..<100 where reply == nil { await Task.yield() }
            #expect(reply == false)
            #expect(cancelled)
            #expect(committed == !failAtDrain)
        }
    }
}
