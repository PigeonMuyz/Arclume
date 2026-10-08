import Foundation

/// Adapter for upstream's manifest. Never reinterpret its prefix ABI as Arclume's.
nonisolated enum NefinitaRuntime {
    static let version = "0.3.0"
    static let revision = "cadaabf0705efa677e4683a2af86d1da3316e8bb"
    static var installationURL: URL {
        ARCLUME_SUPPORT_FOLDER_URL.appendingPathComponent("OnlineGameRuntimes/nefinita-\(version)-\(revision.prefix(8))", isDirectory: true)
    }
    static var buildRoot: URL { ARCLUME_SUPPORT_FOLDER_URL.appendingPathComponent("RuntimeBuilds/Nefinita", isDirectory: true) }

    struct Manifest: Decodable, Sendable {
        struct Engine: Decodable, Sendable {
            let wineVersion: String
            let crossOverSourceVersion: String
            let finewineRevision: String
        }
        let schemaVersion: Int
        let id: String
        let version: String
        let runtimeABI: Int
        let prefixABI: String
        let architecture: String
        let win32: Bool
        let peArchitectures: [String]
        let minimumMacOS: String
        let archive: ArclumeRuntimeManifest.Archive?
        let engine: Engine

        func validate() throws {
            guard schemaVersion == 1, id == "dev.macgamestater.runtime.wine", version == NefinitaRuntime.version,
                  runtimeABI == 1, prefixABI == "macgamestater-prefix-1", architecture == "x86_64",
                  win32, Set(peArchitectures) == Set(["i386", "x86_64"]), minimumMacOS == "13.0",
                  engine.wineVersion == "11.0", engine.crossOverSourceVersion == "26.3.0",
                  engine.finewineRevision == "e5d4ccad235eefe32d912733e57e4c0bb53a5b58" else { throw NefinitaBuildError.invalidRuntime }
            if let archive {
                guard archive.name == "nefinita-runtime.tar.xz", archive.rootDirectory == "mgstarter-wine-runtime-x86_64",
                      archive.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NefinitaBuildError.invalidRuntime }
            }
        }
    }

    static func isReady(at root: URL = installationURL) -> Bool {
        guard (try? String(contentsOf: root.appendingPathComponent(".arclume-nefinita-revision"), encoding: .utf8)) == revision else { return false }
        return (try? validateLayout(at: root)) != nil
    }

    static func validateLayout(at root: URL) throws {
        let fm = FileManager.default
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent(".mgstarter-runtime.json")))
        try manifest.validate()
        for path in ["lib/wine/x86_64-unix/wine", "bin/wineserver"] {
            let file = root.appendingPathComponent(path)
            guard fm.isExecutableFile(atPath: file.path) else { throw NefinitaBuildError.invalidRuntime }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            // Native loader must be x86_64 Mach-O, not an ARM executable or a PE file.
            guard try handle.read(upToCount: 8) == Data([0xcf, 0xfa, 0xed, 0xfe, 7, 0, 0, 1]) else { throw NefinitaBuildError.invalidRuntime }
        }
        for path in ["lib/wine/x86_64-unix/ntdll.so", "lib/wine/x86_64-unix/winegstreamer.so",
                     "lib/wine/i386-windows/ntdll.dll", "lib/wine/i386-windows/kernel32.dll",
                     "lib/wine/x86_64-windows/ntdll.dll", "lib64/libgnutls.30.dylib",
                     "lib64/libgstreamer-1.0.0.dylib", "lib64/libfreetype.6.dylib", "share/wine/wine.inf"] {
            guard fm.fileExists(atPath: root.appendingPathComponent(path).path) else { throw NefinitaBuildError.invalidRuntime }
        }
    }

    static func install(archive: URL, manifestURL: URL, destination: URL = installationURL) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        try manifest.validate()
        guard let info = manifest.archive, try DownloadedResourceFiles.hash(archive) == info.sha256 else { throw NefinitaBuildError.invalidRuntime }
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".nefinita-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try SafeArchiveExtractor.extract(archive, to: staging)
        let runtime = staging.appendingPathComponent(info.rootDirectory)
        try validateLayout(at: runtime)
        try revision.write(to: runtime.appendingPathComponent(".arclume-nefinita-revision"), atomically: true, encoding: .utf8)
        try ArclumeWineStopService.withRuntimeMaintenance {
            guard try ArclumeWineStopService.snapshot(root: destination.resolvingSymlinksInPath().path).isEmpty else { throw ResourceDownloadError.busyRuntime }
            if isReady(at: destination) { return }
            // Do not overwrite an unknown directory. No container is touched here.
            guard !fm.fileExists(atPath: destination.path) else { throw NefinitaBuildError.invalidRuntime }
            try fm.moveItem(at: runtime, to: destination)
        }
    }
}
