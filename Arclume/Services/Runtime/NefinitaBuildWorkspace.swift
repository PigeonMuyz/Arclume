import Foundation

/// Autotools/Make inputs must live at a physical path without shell/make separators.
/// A symlink below /tmp is insufficient: build tools can canonicalize it again.
nonisolated enum NefinitaBuildWorkspace {
    static func create(bases: [URL] = defaultBases) throws -> URL {
        let fm = FileManager.default
        for base in bases {
            let physical = base.standardizedFileURL.resolvingSymlinksInPath()
            guard isSupported(physical) else { continue }
            do {
                try fm.createDirectory(at: physical, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                let resolved = physical.resolvingSymlinksInPath()
                guard isSupported(resolved) else { continue }
                let session = resolved.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try fm.createDirectory(at: session, withIntermediateDirectories: false,
                                       attributes: [.posixPermissions: 0o700])
                return session
            } catch { continue }
        }
        throw NefinitaBuildError.failed("创建构建目录")
    }

    static func isSupported(_ url: URL) -> Bool {
        url.isFileURL && url.path.range(of: "^/[A-Za-z0-9/_.-]+$", options: .regularExpression) != nil
    }

    private static var defaultBases: [URL] {
        let fm = FileManager.default
        return (fm.urls(for: .cachesDirectory, in: .userDomainMask) + [fm.temporaryDirectory])
            .map { $0.appendingPathComponent("Arclume/RuntimeBuilds/Nefinita", isDirectory: true) }
    }
}
