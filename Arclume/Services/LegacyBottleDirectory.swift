import Darwin
import Foundation

nonisolated enum LegacyBottleDirectory {
    /// rmdir is atomic and fails for nonempty directories or symlinks.
    /// Never recursively remove an old Bottle, even if contents change concurrently.
    static func removeEmptyDirectory(in supportRoot: URL) {
        let directory = supportRoot.appendingPathComponent("CXPBottles", isDirectory: true)
        _ = directory.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.rmdir($0) } ?? -1
        }
    }
}
