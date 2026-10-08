import Foundation
import Testing
@testable import Arclume

struct NefinitaBuildWorkspaceTests {
    @Test func usesPhysicalSpaceFreeWorkspaceAndPrivatePermissions() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nefinita-workspace-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let workspace = try NefinitaBuildWorkspace.create(bases: [root])
        #expect(NefinitaBuildWorkspace.isSupported(workspace))
        #expect(workspace == workspace.resolvingSymlinksInPath())
        #expect(workspace.deletingLastPathComponent() == root.resolvingSymlinksInPath())
        #expect((try fm.attributesOfItem(atPath: workspace.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func skipsSpaceContainingHomeAndKeepsItUntouched() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nefinita-workspace-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let invalid = root.appendingPathComponent("User Name/Library/Caches")
        let fallback = root.appendingPathComponent("temporary")
        let workspace = try NefinitaBuildWorkspace.create(bases: [invalid, fallback])
        #expect(workspace.deletingLastPathComponent() == fallback.resolvingSymlinksInPath())
        #expect(!fm.fileExists(atPath: invalid.path))
    }

    @Test func doesNotHideUnsafePhysicalPathBehindASymlink() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nefinita-workspace-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let spaced = root.appendingPathComponent("Application Support")
        try fm.createDirectory(at: spaced, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: spaced)
        let fallback = root.appendingPathComponent("safe")
        let workspace = try NefinitaBuildWorkspace.create(bases: [alias, fallback])
        #expect(workspace.deletingLastPathComponent() == fallback.resolvingSymlinksInPath())
        #expect(try fm.contentsOfDirectory(atPath: spaced.path).isEmpty)
    }

    @Test func rejectsMakeAndShellSeparators() {
        for path in ["/tmp/User Name", "/tmp/a#b", "/tmp/a$b", "/tmp/a:b", "/tmp/a\tb"] {
            #expect(!NefinitaBuildWorkspace.isSupported(URL(fileURLWithPath: path)))
        }
        #expect(throws: NefinitaBuildError.self) { try NefinitaBuildWorkspace.create(bases: []) }
    }
}
