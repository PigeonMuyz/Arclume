import Foundation

nonisolated struct NefinitaBuildService: Sendable {
    struct EnvironmentReport: Sendable {
        let missing: [String]
        var isReady: Bool { missing.isEmpty }
    }
    static var toolPath: String {
        // Prepared OSS tool packs can be staged here later; do not change the user's PATH.
        [ARCLUME_SUPPORT_FOLDER_URL.appendingPathComponent("BuildTools/bin").path,
         "/opt/homebrew/opt/bison/bin", "/usr/local/opt/bison/bin",
         "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
    }
    static var environment: [String: String] {
        let allowed = Set(["HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL", "DEVELOPER_DIR"])
        var env = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
        env["PATH"] = toolPath
        env["JOBS"] = String(min(4, max(1, ProcessInfo.processInfo.activeProcessorCount - 1)))
        env["WINE_SIGN_IDENTITY"] = "-"
        return env
    }

    @concurrent static func inspectEnvironment() async -> EnvironmentReport {
        var missing: [String] = []
        if !probe("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"]) { missing.append("Xcode Command Line Tools") }
        if !probe("/usr/bin/xcrun", ["--find", "clang"]) { missing.append("Apple Clang") }
        #if arch(arm64)
        if !probe("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]) { missing.append("Rosetta 2") }
        #endif
        for tool in ["cmake", "meson", "ninja", "pkg-config", "python3", "i686-w64-mingw32-gcc", "i686-w64-mingw32-strip", "x86_64-w64-mingw32-strip"] {
            if !probe("/usr/bin/env", [tool, "--version"]) { missing.append(tool) }
        }
        if let version = output("/usr/bin/env", ["bison", "--version"]),
           let first = version.split(separator: "\n").first,
           let major = first.split(separator: " ").last?.split(separator: ".").first.flatMap({ Int($0) }), major >= 3 {} else {
            missing.append("Bison 3 或以上")
        }
        return EnvironmentReport(missing: missing)
    }

    @concurrent func build(onProgress: @escaping @Sendable (Double, String, URL) -> Void) async throws {
        guard !ArclumeTestEnvironment.isTesting else { throw NefinitaBuildError.sourceUnavailable }
        let report = await Self.inspectEnvironment()
        guard report.isReady else { throw NefinitaBuildError.missingTools(report.missing) }
        let recipe = try NefinitaBuildRecipe.load()
        let fm = FileManager.default
        let session = try NefinitaBuildWorkspace.create()
        let logDirectory = NefinitaRuntime.buildRoot.appendingPathComponent(session.lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("build.log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data("Build workspace: \(session.path)\n".utf8))
        let sourceRoot = try await NefinitaSourceService().prepare(recipe: recipe,
            baseURL: Bundle.main.object(forInfoDictionaryKey: "ArclumeResourceBaseURL") as? String,
            cacheRoot: NefinitaRuntime.buildRoot.appendingPathComponent("Sources")) { completed, total in
                onProgress(0.1 * Double(completed) / Double(max(1, total)), "下载编译材料（\(completed)/\(total)）", log)
            }
        // Copy only authenticated inputs, not the user's existing work/deps/dist trees.
        for path in recipe.files.keys.sorted() {
            let target = session.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: sourceRoot.appendingPathComponent(path), to: target)
        }
        _ = try recipe.validateSource(session) // closes source-copy TOCTOU before executing scripts
        let wineSource = try NefinitaWineSourceArchive.load()
        try wineSource.validate(lock: String(contentsOf: session.appendingPathComponent("sources/WINE_SOURCE.lock"), encoding: .utf8))
        let archive = try await NefinitaWineSourceCache().prepare(wineSource,
            baseURL: Bundle.main.object(forInfoDictionaryKey: "ArclumeResourceBaseURL") as? String,
            cacheRoot: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Arclume/BuildSources")) { status in
                onProgress(0.1, status, log)
            }
        // Leave the pinned upstream scripts untouched. Their normal cache hit path
        // consumes this verified archive and verifies it again before extraction.
        let downloads = session.appendingPathComponent("work/downloads", isDirectory: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        try fm.copyItem(at: archive, to: downloads.appendingPathComponent(wineSource.archive))
        let phases = [("sync-wine-source.sh", "下载并准备 Wine 源码"), ("sync-deps.sh", "下载并构建依赖组件"),
                      ("apply-finewine.sh", "准备并应用 FineWine 补丁"), ("build-runtime.sh", "编译 Nefinita")]
        for (index, phase) in phases.enumerated() {
            try Task.checkCancellation()
            onProgress(0.1 + Double(index) / 5, phase.1, log)
            var arguments = [session.appendingPathComponent("script/\(phase.0)").path]
            if phase.0 == "build-runtime.sh" { arguments += ["--output", session.appendingPathComponent("dist/nefinita-runtime.tar.xz").path] }
            // Observe bounded log chunks without buffering compiler output in memory.
            // Only recognized events become UI labels; raw paths/URLs stay in the log.
            let monitor = NefinitaBuildProgress.monitor(log: log) { detail in
                onProgress(0.1 + Double(index) / 5, detail, log)
            }
            do {
                try await Self.run(arguments: arguments, directory: session, log: handle, phase: phase.1)
            } catch {
                monitor.cancel()
                await monitor.value
                throw error
            }
            monitor.cancel()
            await monitor.value
        }
        try Task.checkCancellation()
        onProgress(0.9, "检查并安装 Nefinita", log)
        try NefinitaRuntime.install(archive: session.appendingPathComponent("dist/nefinita-runtime.tar.xz"),
                                    manifestURL: session.appendingPathComponent("dist/nefinita-runtime.runtime.json"))
        onProgress(1, "Nefinita 已就绪", log)
    }

    private static func run(arguments: [String], directory: URL, log: FileHandle, phase: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = log
            process.standardError = log
            process.terminationHandler = { process in
                if process.terminationStatus == 0 { continuation.resume() }
                else { continuation.resume(throwing: NefinitaBuildError.failed(phase)) }
            }
            do { try process.run() }
            catch { process.terminationHandler = nil; continuation.resume(throwing: NefinitaBuildError.failed(phase)) }
        }
    }

    private static func probe(_ executable: String, _ arguments: [String]) -> Bool { output(executable, arguments) != nil }
    private static func output(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        } catch { return nil }
    }
}
