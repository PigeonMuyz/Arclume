import CryptoKit
import Darwin
import Foundation

/// DXMT 0.80 stores observed Metal libraries in SQLite cache_18.
/// Preparation receipts count libraries, while scene pipeline state stays owned by DXMT.
nonisolated enum GameMetalShaderCache {
    static let version = "0.80"
    static let maximumWorkers = 16

    struct Snapshot: Codable, Sendable {
        let observed: Int
        let pending: Int
        let prepared: Int
        let computePipelines: Int
        let failed: Int
    }

    struct Progress: Codable, Sendable {
        let processed: Int
        let total: Int
        let failed: Int
        var phase: String? = nil
    }

    private struct GracefulCompilerExit: Error {
        let cause: any Error
    }

    private struct ExternalSource: Codable {
        let path: String
        let bookmark: Data
    }

    private struct Event: Decodable {
        let event: String
        let snapshot: Snapshot?
        let progress: Progress?
        let message: String?
    }

    static var toolsAvailable: Bool {
        helperURL.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
    }

    static func directory(prefix: URL, gameID: String = "online.jx3.flagship", root: URL = ARCLUME_SUPPORT_FOLDER_URL) -> URL {
        let identity = gameID + "\n" + prefix.resolvingSymlinksInPath().standardizedFileURL.path
        let digest = SHA256.hash(data: Data(identity.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let name = String(gameID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.prefix(80))
        let component = name.isEmpty || name == "." || name == ".." ? "game" : name
        return root.appendingPathComponent("Shaders/\(component)/DXMT-\(version)/\(digest)", isDirectory: true)
    }

    static func externalSource(prefix: URL, gameID: String = "online.jx3.flagship") -> URL? {
        let file = directory(prefix: prefix, gameID: gameID).appendingPathComponent("external-source.json")
        guard let data = try? Data(contentsOf: file),
              let source = try? JSONDecoder().decode(ExternalSource.self, from: data) else { return nil }
        var stale = false
        return (try? URL(resolvingBookmarkData: source.bookmark, options: [.withSecurityScope, .withoutUI],
                         relativeTo: nil, bookmarkDataIsStale: &stale)) ?? URL(fileURLWithPath: source.path)
    }

    static func setExternalSource(_ source: URL?, prefix: URL, gameID: String = "online.jx3.flagship") throws {
        let root = directory(prefix: prefix, gameID: gameID)
        let file = root.appendingPathComponent("external-source.json")
        guard let source else {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        guard source.isFileURL else { throw CacheError.invalidSource }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        guard values.isDirectory == true || (values.isRegularFile == true && ["db", "metallib"].contains(source.pathExtension.lowercased()))
        else { throw CacheError.invalidSource }
        let bookmark = try source.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(ExternalSource(path: source.path, bookmark: bookmark)).write(to: file, options: .atomic)
    }

    /// Configure observed shader storage before the game opens its cache.
    static func configure(environment: inout [String: String], prefix: URL, gameID: String = "online.jx3.flagship",
                          executable: String = "JX3ClientX64.exe") throws {
        let cache = directory(prefix: prefix, gameID: gameID)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        environment.removeValue(forKey: "DXMT_SHADER_CACHE")
        environment["DXMT_SHADER_CACHE_PATH"] = cache.path
    }

    @concurrent static func prepare(prefix: URL, gameID: String = "online.jx3.flagship",
                                    executable: String = "JX3ClientX64.exe") async throws {
        guard toolsAvailable else { return }
        _ = try run(mode: "import", prefix: prefix, gameID: gameID, executable: executable,
                    ignoresMissingSource: true, onProgress: { _ in })
    }

    @concurrent static func snapshot(
        prefix: URL, gameID: String = "online.jx3.flagship", executable: String = "JX3ClientX64.exe",
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> Snapshot {
        try run(mode: "inspect", prefix: prefix, gameID: gameID, executable: executable, onProgress: onProgress)
    }

    @concurrent static func optimize(
        prefix: URL, gameID: String = "online.jx3.flagship", executable: String = "JX3ClientX64.exe",
        workers: Int = 1, onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws -> Snapshot {
        // Restore the saved native pair before the compiler process opens Metal.
        _ = try run(mode: "import", prefix: prefix, gameID: gameID, executable: executable, onProgress: onProgress)
        let session = UUID()
        let result: Snapshot
        do {
            result = try run(mode: "optimize", prefix: prefix, gameID: gameID, executable: executable,
                             session: session, workers: max(1, min(maximumWorkers, workers)), onProgress: onProgress)
        } catch let exit as GracefulCompilerExit {
            do {
                try await preserve(prefix: prefix, gameID: gameID, executable: executable, session: session, onProgress: onProgress)
            } catch {
                throw CacheError.failed("保存已完成的原生缓存失败：\(error.localizedDescription)")
            }
            throw exit.cause
        }
        try await preserve(prefix: prefix, gameID: gameID, executable: executable, session: session, onProgress: onProgress)
        return result
    }

    private static func preserve(
        prefix: URL, gameID: String, executable: String, session: UUID,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        // A graceful exit flushes Metal. Finish saving that session even on cancellation.
        _ = try await Task.detached(priority: .utility) {
            try run(mode: "preserve", prefix: prefix, gameID: gameID, executable: executable,
                    session: session, ignoresMissingSource: true, onProgress: onProgress)
        }.value
    }

    private static var helperURL: URL? {
        Bundle.main.url(forResource: "game-metal-shader-cache", withExtension: nil, subdirectory: "GameMetalShaderTools")
            ?? Bundle.main.url(forResource: "game-metal-shader-cache", withExtension: nil)
    }

    private static func run(
        mode: String, prefix: URL, gameID: String, executable: String, session: UUID? = nil,
        workers: Int? = nil, ignoresMissingSource: Bool = false, onProgress: @escaping @Sendable (Progress) -> Void
    ) throws -> Snapshot {
        guard let helperURL, toolsAvailable else { throw CacheError.unavailable }
        guard !executable.isEmpty, executable == (executable as NSString).lastPathComponent,
              !executable.contains("\\") else { throw CacheError.invalidSource }
        let cache = directory(prefix: prefix, gameID: gameID)
        var buffer = [CChar](repeating: 0, count: 4_096)
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count) > 0 else { throw CacheError.cachePath }
        let legacy = URL(fileURLWithFileSystemRepresentation: buffer, isDirectory: true, relativeTo: nil)
            .appendingPathComponent("dxmt/\(executable)", isDirectory: true)
        let process = Process()
        let output = Pipe()
        process.executableURL = helperURL
        process.arguments = [mode, "--cache-dir", cache.path, "--legacy-dir", legacy.path,
                             "--native-cache-dir", legacy.appendingPathComponent("com.apple.metal").path]
        if let session { process.arguments?.append(contentsOf: ["--session", session.uuidString]) }
        if let workers { process.arguments?.append(contentsOf: ["--workers", String(workers)]) }
        let external = mode == "preserve" ? nil : externalSource(prefix: prefix, gameID: gameID)
        let accessing = external?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { external?.stopAccessingSecurityScopedResource() } }
        if let external {
            if FileManager.default.fileExists(atPath: external.path) {
                process.arguments?.append(contentsOf: ["--external-source", external.path])
            } else if !ignoresMissingSource {
                throw CacheError.failed("所选外置着色器缓存当前不可用，请连接存储设备或重新选择。")
            }
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try Task.checkCancellation()
        try process.run()
        defer {
            try? output.fileHandleForReading.close()
        }
        do {
            var pending = Data()
            var result: Snapshot?
            var failure: String?
            let descriptor = output.fileHandleForReading.fileDescriptor
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
            var bytes = [UInt8](repeating: 0, count: 4_096)
            let decoder = JSONDecoder()
            let clock = ContinuousClock()
            var lastOutput = clock.now
            while true {
                try Task.checkCancellation()
                let count = Darwin.read(descriptor, &bytes, bytes.count)
                if count == 0 { break }
                if count < 0 {
                    guard errno == EAGAIN || errno == EINTR else { throw CacheError.invalidResponse }
                    guard clock.now - lastOutput < .seconds(120) else { throw CacheError.failed("着色器准备工具长时间未响应。") }
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                }
                lastOutput = clock.now
                pending.append(contentsOf: bytes.prefix(count))
                guard pending.count <= 65_536 else { throw CacheError.invalidResponse }
                while let newline = pending.firstIndex(of: 10) {
                    let line = Data(pending.prefix(upTo: newline))
                    pending = Data(pending.dropFirst(line.count + 1))
                    let event = try decoder.decode(Event.self, from: line)
                    if let progress = event.progress { onProgress(progress) }
                    if let snapshot = event.snapshot { result = snapshot }
                    if let message = event.message { failure = message }
                }
            }
            let exitDeadline = clock.now + .seconds(5)
            while process.isRunning {
                try Task.checkCancellation()
                guard clock.now < exitDeadline else { throw CacheError.failed("着色器准备工具未能正常退出。") }
                Thread.sleep(forTimeInterval: 0.025)
            }
            process.waitUntilExit()
            try Task.checkCancellation()
            guard process.terminationStatus == 0, let result else {
                throw CacheError.failed(failure ?? "无法完成 DXMT 着色器准备。")
            }
            return result
        } catch {
            if stopOwnedProcess(process) {
                throw CacheError.failed("着色器准备工具未及时退出，已终止本次任务。下次优化可接续上次已保存的进度。")
            }
            if mode == "optimize", !process.isRunning, process.terminationReason == .exit,
               [0, 1, 130].contains(process.terminationStatus) {
                throw GracefulCompilerExit(cause: error)
            }
            throw error
        }
    }

    /// Returns true when a forced stop was needed. Only this Process's child is signalled.
    private static func stopOwnedProcess(_ process: Process) -> Bool {
        guard process.isRunning else { return false }
        let identifier = process.processIdentifier
        process.terminate()
        let clock = ContinuousClock()
        let graceDeadline = clock.now + .seconds(5)
        while process.isRunning && clock.now < graceDeadline { Thread.sleep(forTimeInterval: 0.025) }
        guard process.isRunning else { return false }
        _ = Darwin.kill(identifier, SIGKILL)
        let killDeadline = clock.now + .seconds(2)
        while process.isRunning && clock.now < killDeadline { Thread.sleep(forTimeInterval: 0.025) }
        return true
    }

    enum CacheError: LocalizedError {
        case unavailable, cachePath, invalidResponse, invalidSource, failed(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: "应用中缺少 DXMT 着色器准备工具。"
            case .cachePath: "无法定位 DXMT 已保存的着色器目录。"
            case .invalidResponse: "DXMT 着色器准备工具返回的数据不完整。"
            case .invalidSource: "请选择 DXMT 数据库、Metal 着色器库或包含这些文件的目录。"
            case .failed(let message): message
            }
        }
    }
}
