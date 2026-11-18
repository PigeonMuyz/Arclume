import Foundation
import CryptoKit
import Metal

nonisolated enum GameDXBCPrecompile {
    struct Result: Codable, Sendable {
        let processed: Int
        let compiled: Int
        let failed: Int
        let unsupported: Int
    }

    private struct Inventory: Codable {
        let signature: String
        let count: Int
    }

    private struct Compilation: Codable {
        let signature: String
        let result: Result
    }

    private struct Event: Decodable {
        let event: String
        let shaderCount: Int?
        let processed: Int?
        let compiled: Int?
        let failed: Int?
        let unsupported: Int?
        let message: String?
    }

    private static var tools: URL? { Bundle.main.resourceURL?.appendingPathComponent("GameMetalShaderTools") }

    private final class Reader {
        private let handle: FileHandle
        private var pending = Data()

        init(_ path: URL) throws { handle = try FileHandle(forReadingFrom: path) }
        deinit { try? handle.close() }

        func read() throws -> [Event] {
            if let bytes = try handle.read(upToCount: 65_536) { pending.append(bytes) }
            var records: [Event] = []
            while let newline = pending.firstIndex(of: 10) {
                let line = Data(pending.prefix(upTo: newline))
                pending = Data(pending.dropFirst(line.count + 1))
                if line.first == 123 { records.append(try JSONDecoder().decode(Event.self, from: line)) }
            }
            guard pending.count < 65_536 else { throw failure(nil) }
            return records
        }
    }

    static func gameRoot(gameID: String, launcher: URL?) -> URL? {
        guard gameID == "online.jx3.flagship", let launcher else { return nil }
        return launcher.deletingLastPathComponent().appendingPathComponent("Game/JX3", isDirectory: true)
    }

    @concurrent static func inventory(gameRoot: URL, prefix: URL, gameID: String,
                                      onCount: @escaping @Sendable (Int) -> Void) async throws -> Int {
        let fingerprint = try signature(gameRoot)
        let cache = GameMetalShaderCache.directory(prefix: prefix, gameID: gameID)
        let path = cache.appendingPathComponent("dxbc-inventory.json")
        if let data = try? Data(contentsOf: path),
           let saved = try? JSONDecoder().decode(Inventory.self, from: data), saved.signature == fingerprint, saved.count >= 0 {
            onCount(saved.count)
            return saved.count
        }
        let total = try await count(gameRoot: gameRoot, onCount: onCount)
        guard try signature(gameRoot) == fingerprint else { throw failure("游戏资源已变化，请重新读取。") }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try JSONEncoder().encode(Inventory(signature: fingerprint, count: total)).write(to: path, options: .atomic)
        return total
    }

    @concurrent static func completedResult(gameRoot: URL, prefix: URL, gameID: String) async throws -> Result? {
        try completedResult(signature: signature(gameRoot), prefix: prefix, gameID: gameID)
    }

    private static func completedResult(signature: String, prefix: URL, gameID: String) throws -> Result? {
        let cache = GameMetalShaderCache.directory(prefix: prefix, gameID: gameID)
        let path = cache.appendingPathComponent("dxbc-compilation.json")
        guard let data = try? Data(contentsOf: path), let saved = try? JSONDecoder().decode(Compilation.self, from: data),
              saved.signature == signature, saved.result.failed == 0,
              saved.result.compiled + saved.result.unsupported == saved.result.processed else { return nil }
        let librariesPresent = ["shaders_310.db", "shaders_320.db"].contains { name in
            let file = cache.appendingPathComponent(name)
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0
        }
        return librariesPresent || saved.result.compiled == 0 ? saved.result : nil
    }

    @concurrent static func pendingCount(gameRoot: URL, prefix: URL, gameID: String,
                                         onCount: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> Int {
        if try await completedResult(gameRoot: gameRoot, prefix: prefix, gameID: gameID) != nil { return 0 }
        return try await inventory(gameRoot: gameRoot, prefix: prefix, gameID: gameID, onCount: onCount)
    }

    @concurrent static func count(gameRoot: URL, onCount: @escaping @Sendable (Int) -> Void) async throws -> Int {
        guard let tools else { throw CocoaError(.fileNoSuchFile) }
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let events = workspace.appendingPathComponent("scanner.jsonl")
        let output = try log(at: events)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = tools.appendingPathComponent("jx3-shader-scan")
        process.arguments = ["--count-only", "--game-root", gameRoot.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = output
        let reader = try Reader(events)
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        while process.isRunning {
            if let value = try reader.read().last?.shaderCount { onCount(value) }
            try await Task.sleep(for: .milliseconds(300))
        }
        let records = try readEvents(events)
        guard process.terminationStatus == 0,
              let count = records.last(where: { $0.event == "complete" })?.shaderCount else {
            throw failure(records.last?.message)
        }
        onCount(count)
        return count
    }

    @concurrent static func compile(gameRoot: URL, prefix: URL, gameID: String, workers: Int = 1,
                                     onProgress: @escaping @Sendable (Result) -> Void) async throws -> Result {
        guard let tools else { throw CocoaError(.fileNoSuchFile) }
        guard await !OnlineGameLauncher.isJX3ClientRunning() else { throw failure("请先退出游戏。") }
        let fingerprint = try signature(gameRoot)
        if let completed = try completedResult(signature: fingerprint, prefix: prefix, gameID: gameID) {
            onProgress(completed)
            return completed
        }
        let runtime = try WineRuntimeProvider.ensureRuntime(for: prefix)
        let configuration = try BundledWineRuntime.makeLaunchConfiguration(runtimeURL: runtime,
            graphicsBackend: "dxmt", d3dMetal4Enabled: false, mtlHudEnabled: false, wineMSync: true)
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let scannerLog = workspace.appendingPathComponent("scanner.jsonl")
        let compilerLog = workspace.appendingPathComponent("compiler.jsonl")
        let diagnostics = workspace.appendingPathComponent("wine.log")
        let scannerOutput = try log(at: scannerLog)
        let compilerOutput = try log(at: compilerLog)
        let diagnosticOutput = try log(at: diagnostics)
        defer {
            try? scannerOutput.close()
            try? compilerOutput.close()
            try? diagnosticOutput.close()
        }
        var environment = configuration.environment
        environment["WINEPREFIX"] = workspace.appendingPathComponent("Prefix").path
        environment["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d;mscoree=d;mshtml=d"
        try GameMetalShaderCache.configure(environment: &environment, prefix: prefix, gameID: gameID)
        let pipe = Pipe()
        let scanner = Process()
        scanner.executableURL = tools.appendingPathComponent("jx3-shader-scan")
        scanner.arguments = ["--game-root", gameRoot.path]
        scanner.standardInput = FileHandle.nullDevice
        scanner.standardOutput = pipe
        scanner.standardError = scannerOutput
        let compiler = Process()
        compiler.executableURL = configuration.wineURL
        compiler.arguments = [tools.appendingPathComponent("game-dxbc-compile.exe").path, "--workers", String(workers)]
        compiler.environment = environment
        compiler.currentDirectoryURL = workspace
        compiler.standardInput = pipe
        compiler.standardOutput = compilerOutput
        compiler.standardError = diagnosticOutput
        let reader = try Reader(compilerLog)
        try compiler.run()
        defer {
            if scanner.isRunning { scanner.terminate() }
            if compiler.isRunning { compiler.terminate() }
            let server = Process()
            server.executableURL = runtime.appendingPathComponent("bin/wineserver")
            server.arguments = ["-k"]
            server.environment = environment
            server.standardInput = FileHandle.nullDevice
            server.standardOutput = FileHandle.nullDevice
            server.standardError = FileHandle.nullDevice
            if (try? server.run()) != nil { _ = ContainerInitializationProcess.wait(server, timeout: 5) }
        }
        try scanner.run()
        while compiler.isRunning || scanner.isRunning {
            if let last = try reader.read().last, let result = result(last) { onProgress(result) }
            try await Task.sleep(for: .milliseconds(300))
        }
        let records = try readEvents(compilerLog)
        let scanRecords = try readEvents(scannerLog)
        guard compiler.terminationStatus == 0, scanner.terminationStatus == 0,
              let final = records.last(where: { $0.event == "complete" }).flatMap(result),
              final.compiled + final.failed + final.unsupported == final.processed,
              final.processed == scanRecords.last(where: { $0.event == "complete" })?.shaderCount else {
            throw failure(records.last?.message ?? scanRecords.last?.message)
        }
        onProgress(final)
        let cache = GameMetalShaderCache.directory(prefix: prefix, gameID: gameID)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(contentsOf: compilerLog).write(to: cache.appendingPathComponent("dxbc-compile.jsonl"), options: .atomic)
        guard try signature(gameRoot) == fingerprint else { throw failure("游戏资源已变化，请重新读取。") }
        try JSONEncoder().encode(Compilation(signature: fingerprint, result: final))
            .write(to: cache.appendingPathComponent("dxbc-compilation.json"), options: .atomic)
        return final
    }

    private static func result(_ event: Event) -> Result? {
        guard let processed = event.processed, let compiled = event.compiled,
              let failed = event.failed, let unsupported = event.unsupported else { return nil }
        return Result(processed: processed, compiled: compiled, failed: failed, unsupported: unsupported)
    }

    private static func readEvents(_ path: URL) throws -> [Event] {
        let data = try Data(contentsOf: path)
        return try data.split(separator: 10).filter { $0.first == 123 }.map {
            try JSONDecoder().decode(Event.self, from: Data($0))
        }
    }

    private static func workspace() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("Arclume-DXBC-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        return path
    }

    private static func log(at path: URL) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: path.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        return try FileHandle(forWritingTo: path)
    }

    private static func failure(_ message: String?) -> NSError {
        NSError(domain: "Arclume.DXBC", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message ?? "着色器编译未完成。"])
    }

    private static func signature(_ root: URL) throws -> String {
        var records = ["DXMT0.80", ProcessInfo.processInfo.operatingSystemVersionString,
                       String(MTLCreateSystemDefaultDevice()?.registryID ?? 0)]
        for relative in ["Pakv4/1033", "bin/zhcn_hd/bin64"] {
            let directory = root.appendingPathComponent(relative)
            if relative == "bin/zhcn_hd/bin64", !FileManager.default.fileExists(atPath: directory.path) {
                records.append(relative + "/missing")
                continue
            }
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where ["dat", "idx", "dll"].contains(file.pathExtension.lowercased()) {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                records.append("\(relative)/\(file.lastPathComponent)/\(values.fileSize ?? 0)/\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)")
            }
        }
        return SHA256.hash(data: Data(records.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
