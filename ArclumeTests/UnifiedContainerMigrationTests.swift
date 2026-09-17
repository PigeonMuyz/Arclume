import Foundation
import Testing
@testable import Arclume

struct UnifiedContainerMigrationTests {
    private let base = "WindowsGameWinePrefixes/Steam"
    private let second = "OnlineGameWinePrefixes/Games"
    private let registry = "WINE REGISTRY Version 2\n;; All keys relative to REGISTRY\\\\Machine\n#arch=win64\n\n"

    private func fixture(_ body: (UnifiedContainerMigration, String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ArclumeMigration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let domain = "arclume.migration.tests.\(UUID())"
        defer {
            UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        let engine = UnifiedContainerMigration(root: root.standardizedFileURL)
        for source in [base, second] {
            for file in UnifiedContainerMigration.registryNames {
                try write(registry, to: root.appendingPathComponent(source + "/" + file))
            }
            try FileManager.default.createDirectory(at: root.appendingPathComponent(source + "/drive_c"), withIntermediateDirectories: true)
        }
        try body(engine, domain)
    }
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func preflightIsReadOnlyAndCopiesUnionWithOriginalsRecoverable() throws {
        try fixture { engine, domain in
            let one = engine.root.appendingPathComponent(base + "/drive_c/PortableApps/YY/YY.exe")
            let two = engine.root.appendingPathComponent(second + "/drive_c/SeasunGame/launcher.exe")
            try write("yy", to: one); try write("jx3", to: two)
            UserDefaults(suiteName: domain)?.set(one.path, forKey: "exe")
            UserDefaults(suiteName: domain)?.set("settings", forKey: "GameOptions." + one.path)
            UserDefaults(suiteName: domain)?.set(try JSONSerialization.data(withJSONObject: ["exe": one.absoluteString]), forKey: "json")
            let before = try FileManager.default.contentsOfDirectory(atPath: engine.root.path).sorted()
            let plan = try engine.preflight(checkIdle: {})
            #expect(plan.conflicts.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: engine.root.path).sorted() == before)
            let record = try engine.migrate(plan, preferencesDomain: domain, checkIdle: {})
            #expect(record.phase == .complete)
            #expect(try engine.requiresMigration()) // Cleanup still gates the library.
            #expect(try String(contentsOf: engine.destination.appendingPathComponent("drive_c/SeasunGame/launcher.exe"), encoding: .utf8) == "jx3")
            #expect(try String(contentsOf: engine.recoveryURL(record).appendingPathComponent("original-0/drive_c/PortableApps/YY/YY.exe"), encoding: .utf8) == "yy")
            #expect(UserDefaults(suiteName: domain)?.string(forKey: "exe") == engine.destination.appendingPathComponent("drive_c/PortableApps/YY/YY.exe").path)
            #expect(UserDefaults(suiteName: domain)?.string(forKey: "GameOptions." + engine.destination.appendingPathComponent("drive_c/PortableApps/YY/YY.exe").path) == "settings")
            #expect(engine.canonicalURL(engine.recoveryURL(record).appendingPathComponent("original-0/drive_c")) == engine.destination.appendingPathComponent("drive_c"))
            try engine.rollback(preferencesDomain: domain, checkIdle: {})
            #expect(try String(contentsOf: one, encoding: .utf8) == "yy")
            #expect(try String(contentsOf: two, encoding: .utf8) == "jx3")
            #expect(!FileManager.default.fileExists(atPath: engine.destination.path))
            #expect(UserDefaults(suiteName: domain)?.string(forKey: "exe") == one.path)
            #expect(try engine.requiresMigration())
        }
    }
    @Test func successfulUpgradeRemovesOnlyItsBackupsAndRefreshesBookmarks() throws {
        try fixture { engine, domain in
            let external = engine.root.appendingPathComponent("external/save")
            try write("external", to: external)
            try FileManager.default.createSymbolicLink(at: engine.root.appendingPathComponent(base + "/drive_c/external"),
                                                      withDestinationURL: external.deletingLastPathComponent())
            let library = engine.root.appendingPathComponent(base + "/drive_c/library")
            try write("game", to: library.appendingPathComponent("game.exe"))
            let bookmark = try library.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults(suiteName: domain)?.set([bookmark], forKey: "steamLibraryBookmarks")
            let unrelated = engine.root.appendingPathComponent("ContainerMigrationRecovery/another-transaction/keep")
            try write("keep", to: unrelated)
            let record = try engine.migrate(engine.preflight(checkIdle: {}), preferencesDomain: domain, checkIdle: {})
            let final = try engine.finalize(preferencesDomain: domain, checkIdle: {})
            #expect(final.phase == .finalized)
            #expect(try !engine.requiresMigration())
            for name in ["original-0", "original-1", "preferences.plist", "preferences-domain.txt"] {
                #expect(!FileManager.default.fileExists(atPath: engine.recoveryURL(record).appendingPathComponent(name).path))
            }
            #expect(try String(contentsOf: external, encoding: .utf8) == "external")
            #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
            let data = try #require((UserDefaults(suiteName: domain)?.array(forKey: "steamLibraryBookmarks") as? [Data])?.first)
            var stale = false
            let resolved = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
            #expect(resolved.resolvingSymlinksInPath().path == engine.destination.appendingPathComponent("drive_c/library").resolvingSymlinksInPath().path)
            #expect(try engine.finalize(preferencesDomain: domain, checkIdle: {}).phase == .finalized)
            #expect(throws: (any Error).self) { try engine.rollback(preferencesDomain: domain, checkIdle: {}) }
        }
    }
    @Test func interruptedCleanupResumesWithoutRollbackOrDeletingNewData() throws {
        for stop in ["cleaning", "cleaned-0", "cleaned-1", "cleaned-2", "cleaned-3"] {
            try fixture { engine, domain in
                _ = try engine.migrate(engine.preflight(checkIdle: {}), preferencesDomain: domain, checkIdle: {})
                #expect(throws: (any Error).self) {
                    try engine.finalize(preferencesDomain: domain, checkIdle: {}, checkpoint: {
                        if $0 == stop { throw CocoaError(.fileWriteUnknown) }
                    })
                }
                #expect(try engine.journal()?.phase == .cleaning)
                #expect(try engine.requiresMigration())
                #expect(throws: (any Error).self) { try engine.rollback(preferencesDomain: domain, checkIdle: {}) }
                let currentSave = engine.destination.appendingPathComponent("drive_c/new.save")
                try write("new", to: currentSave)
                #expect(try engine.finalize(preferencesDomain: domain, checkIdle: {}).phase == .finalized)
                #expect(try String(contentsOf: currentSave, encoding: .utf8) == "new")
            }
        }
    }
    @Test func cleanupRejectsBusyForeignMarkerAndSymlinkedBackup() throws {
        try fixture { engine, domain in
            let record = try engine.migrate(engine.preflight(checkIdle: {}), preferencesDomain: domain, checkIdle: {})
            let backup = engine.recoveryURL(record).appendingPathComponent("original-0")
            #expect(throws: (any Error).self) { try engine.finalize(preferencesDomain: domain, checkIdle: { throw CocoaError(.fileLocking) }) }
            #expect(try engine.journal()?.phase == .complete)
            try write("foreign", to: engine.destination.appendingPathComponent(".arclume-migration-id"))
            #expect(throws: (any Error).self) { try engine.finalize(preferencesDomain: domain, checkIdle: {}) }
            #expect(FileManager.default.fileExists(atPath: backup.path))
            try write(record.id.uuidString, to: engine.destination.appendingPathComponent(".arclume-migration-id"))
            let moved = engine.recoveryURL(record).appendingPathComponent("untouched")
            try FileManager.default.moveItem(at: backup, to: moved)
            try FileManager.default.createSymbolicLink(at: backup, withDestinationURL: moved)
            #expect(throws: (any Error).self) { try engine.finalize(preferencesDomain: domain, checkIdle: {}) }
            #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("system.reg").path))
            #expect(try engine.journal()?.phase == .complete)
        }
    }
    @Test func interruptedTransactionsRecoverAtEverySwitchBoundary() throws {
        for phase in ["copying", "switching", "published", "moved-0", "moved-1", "preferences"] {
            try fixture { engine, domain in
                try write("keep", to: engine.root.appendingPathComponent(second + "/drive_c/save.dat"))
                UserDefaults(suiteName: domain)?.set("before", forKey: "sentinel")
                let plan = try engine.preflight(checkIdle: {})
                #expect(throws: (any Error).self) {
                    try engine.migrate(plan, preferencesDomain: domain, checkIdle: {}, checkpoint: {
                        if $0 == phase { throw CocoaError(.fileWriteUnknown) }
                    })
                }
                #expect(try engine.requiresMigration())
                try engine.rollback(preferencesDomain: domain, checkIdle: {})
                try engine.rollback(preferencesDomain: domain, checkIdle: {}) // idempotent recovery
                #expect(try String(contentsOf: engine.root.appendingPathComponent(second + "/drive_c/save.dat"), encoding: .utf8) == "keep")
                #expect(UserDefaults(suiteName: domain)?.string(forKey: "sentinel") == "before")
                #expect(try engine.preflight(checkIdle: {}).conflicts.isEmpty)
            }
        }
    }
    @Test func activeWineAndChangedSourceNeverPublish() throws {
        try fixture { engine, domain in
            #expect(throws: (any Error).self) { try engine.preflight { throw CocoaError(.fileLocking) } }
            let plan = try engine.preflight(checkIdle: {})
            try write("changed", to: engine.root.appendingPathComponent(second + "/drive_c/new.save"))
            #expect(throws: (any Error).self) { try engine.migrate(plan, preferencesDomain: domain, checkIdle: {}) }
            #expect(!FileManager.default.fileExists(atPath: engine.destination.path))
            #expect(try String(contentsOf: engine.root.appendingPathComponent(second + "/drive_c/new.save"), encoding: .utf8) == "changed")
            try engine.rollback(preferencesDomain: domain, checkIdle: {})
        }
    }
    @Test func blocksApplicationFileRegistryAndCaseConflicts() throws {
        try fixture { engine, _ in
            try write("first", to: engine.root.appendingPathComponent(base + "/drive_c/App/config"))
            try write("second", to: engine.root.appendingPathComponent(second + "/drive_c/App/config"))
            try write("case", to: engine.root.appendingPathComponent(second + "/drive_c/casename.dll"))
            try write("case", to: engine.root.appendingPathComponent(base + "/drive_c/CaseName.dll"))
            try write(registry + "[Software\\\\Wine\\\\DllOverrides]\n\"test\"=\"native\"\n", to: engine.root.appendingPathComponent(base + "/user.reg"))
            try write(registry + "[Software\\\\Wine\\\\DllOverrides]\n\"test\"=\"builtin\"\n", to: engine.root.appendingPathComponent(second + "/user.reg"))
            let plan = try engine.preflight(checkIdle: {})
            #expect(plan.conflicts.contains { $0.contains("App/config") })
            #expect(plan.conflicts.contains { $0.contains("大小写") })
            #expect(plan.conflicts.contains { $0.contains("dlloverrides") })
        }
    }
    @Test func symlinksAreNotTraversedAndAncestorConflictsBlock() throws {
        try fixture { engine, _ in
            let external = engine.root.appendingPathComponent("external")
            try write("untouched", to: external.appendingPathComponent("secret"))
            let link = engine.root.appendingPathComponent(base + "/drive_c/Documents")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
            let plan = try engine.preflight(checkIdle: {})
            #expect(plan.files["drive_c/Documents/secret"] == nil)
            try write("incoming", to: engine.root.appendingPathComponent(second + "/drive_c/Documents/data"))
            #expect(try !engine.preflight(checkIdle: {}).conflicts.isEmpty)
            #expect(try String(contentsOf: external.appendingPathComponent("secret"), encoding: .utf8) == "untouched")
        }
    }
    @Test func preservesExternalLinksAndRejectsForeignDestination() throws {
        try fixture { engine, domain in
            let link = engine.root.appendingPathComponent(base + "/drive_c/Documents")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/nonexistent-user-documents")
            let plan = try engine.preflight(checkIdle: {})
            _ = try engine.migrate(plan, preferencesDomain: domain, checkIdle: {})
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: engine.destination.appendingPathComponent("drive_c/Documents").path) == "/nonexistent-user-documents")
            try write("foreign", to: engine.destination.appendingPathComponent(".arclume-migration-id"))
            #expect(throws: (any Error).self) { try engine.rollback(preferencesDomain: domain, checkIdle: {}) }
        }
    }
    @Test func oneContainerAndFreshInstallAreSupported() throws {
        try fixture { engine, domain in
            try FileManager.default.removeItem(at: engine.root.appendingPathComponent(second))
            #expect(try engine.sources() == [base])
            _ = try engine.migrate(engine.preflight(checkIdle: {}), preferencesDomain: domain, checkIdle: {})
            _ = try engine.finalize(preferencesDomain: domain, checkIdle: {})
            #expect(try !engine.requiresMigration())
            let fresh = UnifiedContainerMigration(root: engine.root.appendingPathComponent("fresh"))
            #expect(try !fresh.requiresMigration())
        }
    }
    @Test func registryPreservesMultilineValuesAndMissingEntries() throws {
        var first = try WineMigrationRegistry(registry + "[Software\\\\App] 1\n#time=abc\n\"a\"=hex:01,\\\n  02\n\n")
        let second = try WineMigrationRegistry(registry + "[Software\\\\App] 2\n\"a\"=hex:01,\\\n  02\n\"b\"=\"new\"\n\n[Software\\\\Other]\n@=dword:00000001\n")
        #expect(first.merge(second).isEmpty)
        #expect(first.serialized.contains("#time=abc"))
        #expect(first.serialized.contains("\"a\"=hex:01,\\\n  02"))
        #expect(first.serialized.contains("\"b\"=\"new\""))
        #expect(first.serialized.contains("[Software\\\\Other]"))
        #expect(throws: (any Error).self) { try WineMigrationRegistry("REGEDIT4") }
    }
    @Test func existingTargetAndUnsafeSourceAreNeverOverwritten() throws {
        try fixture { engine, _ in
            try write("keep", to: engine.destination.appendingPathComponent("sentinel"))
            #expect(throws: (any Error).self) { try engine.requiresMigration() }
            #expect(throws: (any Error).self) { try engine.preflight(checkIdle: {}) }
            #expect(try String(contentsOf: engine.destination.appendingPathComponent("sentinel"), encoding: .utf8) == "keep")
        }
    }
    @Test func rejectsArchitectureMismatchAndDirectorySymlinkEscape() throws {
        try fixture { engine, _ in
            try write(registry.replacingOccurrences(of: "win64", with: "win32"), to: engine.root.appendingPathComponent(second + "/user.reg"))
            #expect(throws: (any Error).self) { try engine.preflight(checkIdle: {}) }
            let alias = engine.root.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: engine.root)
            #expect(throws: (any Error).self) { try UnifiedContainerMigration(root: alias).sources() }
        }
    }
    @Test func conflictingLiveDriveMappingsAreBlocked() throws {
        try fixture { engine, _ in
            for (source, target) in [(base, "drive-one"), (second, "drive-two")] {
                let location = engine.root.appendingPathComponent(target)
                try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
                let drive = engine.root.appendingPathComponent(source + "/dosdevices/d:")
                try FileManager.default.createDirectory(at: drive.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(at: drive, withDestinationURL: location)
            }
            #expect(try engine.preflight(checkIdle: {}).conflicts.contains { $0.contains("dosdevices/d:") })
        }
    }
    @Test func detachedInstallerDeviceLinksAreAutomaticallyResolved() throws {
        try fixture { engine, _ in
            let currentVolume = engine.root.appendingPathComponent("mounted-fixture")
            try FileManager.default.createDirectory(at: currentVolume, withIntermediateDirectories: true)
            for (source, mount, device) in [(base, currentVolume.path, "/dev/zero"),
                (second, "/Volumes/Arclume-unmounted-\(UUID())", "/dev/null")] {
                let folder = engine.root.appendingPathComponent(source + "/dosdevices")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("d:").path, withDestinationPath: mount)
                try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("d::").path, withDestinationPath: device)
            }
            let plan = try engine.preflight(checkIdle: {})
            #expect(plan.conflicts.isEmpty)
            #expect(plan.files["dosdevices/d::"] == 0)
            #expect(plan.notices.contains { $0.contains("已卸载卷") })
        }
    }
}
