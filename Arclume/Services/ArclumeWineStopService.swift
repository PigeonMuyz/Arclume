import Foundation
import Darwin

/// No process-name matching: another Wine/CrossOver installation is out of scope.
nonisolated enum ArclumeWineStopService {
    private final class LaunchGate: @unchecked Sendable {
        let lock = NSLock()
        var generation = 0
        var stopping = false
    }
    private static let gate = LaunchGate()

    static var isStopping: Bool {
        gate.lock.lock()
        defer { gate.lock.unlock() }
        return gate.stopping
    }

    static func launchTicket() throws -> Int {
        gate.lock.lock()
        defer { gate.lock.unlock() }
        guard !gate.stopping else { throw CancellationError() }
        return gate.generation
    }

    static func withLaunchTicket<T>(_ ticket: Int, _ body: () throws -> T) throws -> T {
        gate.lock.lock()
        defer { gate.lock.unlock() }
        guard !gate.stopping, ticket == gate.generation else { throw CancellationError() }
        return try body()
    }

    private static func beginStopping() throws {
        gate.lock.lock()
        defer { gate.lock.unlock() }
        guard !gate.stopping else { throw CancellationError() }
        gate.generation += 1
        gate.stopping = true
    }

    private static func endStopping() {
        gate.lock.lock()
        defer { gate.lock.unlock() }
        gate.stopping = false
    }
    struct Identity: Hashable, Sendable {
        let pid: Int32
        let startedSeconds: UInt64
        let startedMicroseconds: UInt64
        let executable: String
    }

    enum StopError: LocalizedError {
        case enumerationFailed
        case timeout(Int)

        var errorDescription: String? {
            switch self {
            case .enumerationFailed: "无法检查 Arclume Wine 进程，未确认停止完成。"
            case .timeout(let count): count == 0
                ? "Arclume Wine 停止确认超时，请稍后重试。"
                : "仍有 \(count) 个 Arclume Wine 进程未退出，请稍后重试。"
            }
        }
    }

    static func stop(runtimeRoot: URL, prefix: URL? = nil) async throws {
        // A global Stop action may arrive while a Steam-only recovery is
        // draining. Wait for it, then run the full requested scope as well.
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while true {
            try Task.checkCancellation()
            do { try beginStopping(); break }
            catch is CancellationError {
                guard ContinuousClock.now < deadline else { throw StopError.timeout(0) }
                try await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { endStopping() }
        let root = runtimeRoot.resolvingSymlinksInPath().standardizedFileURL.path
        try await drain(
            snapshot: { try snapshot(root: root, prefix: prefix) },
            signal: { identity, signal in
                // PID reuse must never turn into a signal to an unrelated process.
                guard readIdentity(identity.pid) == identity else { return }
                _ = Darwin.kill(identity.pid, signal)
            }
        )
    }

    static func drain(
        grace: Duration = .seconds(2),
        timeout: Duration = .seconds(15),
        quietPeriod: Duration = .milliseconds(600),
        snapshot: @Sendable () throws -> [Identity],
        signal: @Sendable (Identity, Int32) -> Void
    ) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        var emptySince: ContinuousClock.Instant?
        var signalled = Set<Identity>()
        while true {
            try Task.checkCancellation()
            let processes = try snapshot()
            let now = clock.now
            if processes.isEmpty {
                if emptySince == nil { emptySince = now }
                if now - emptySince! >= quietPeriod { return }
            } else {
                emptySince = nil
                let force = now - start >= grace
                for process in processes where force || !signalled.contains(process) {
                    signal(process, force ? SIGKILL : SIGTERM)
                    signalled.insert(process)
                }
            }
            if now - start >= timeout { throw StopError.timeout(processes.count) }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    static func belongsToRuntime(_ executable: String, root: String) -> Bool {
        executable.hasPrefix(root + "/")
    }

    static func snapshot(root: String, prefix: URL? = nil) throws -> [Identity] {
        var capacity = max(Int(proc_listallpids(nil, 0)) + 128, 256)
        for _ in 0..<4 {
            var pids = [Int32](repeating: 0, count: capacity)
            let count = pids.withUnsafeMutableBytes {
                proc_listallpids($0.baseAddress, Int32($0.count))
            }
            guard count > 0 else { throw StopError.enumerationFailed }
            if count >= capacity { capacity *= 2; continue }
            let identities = pids.prefix(Int(count)).compactMap(readIdentity)
            let temporaryLoaders = identities.filter {
                !belongsToRuntime($0.executable, root: root)
                    && ($0.executable.lowercased().hasSuffix(".exe") || $0.executable.contains("/winetemp-"))
            }
            let mapped = try runtimeMappedPIDs(temporaryLoaders, root: root)
            return try identities.filter { identity in
                guard belongsToRuntime(identity.executable, root: root) || mapped.contains(identity.pid) else { return false }
                guard readIdentity(identity.pid) == identity else { return false }
                if let prefix {
                    guard let processPrefix = winePrefix(pid: identity.pid), !processPrefix.isEmpty else {
                        if readIdentity(identity.pid) == identity { throw StopError.enumerationFailed }
                        return false
                    }
                    guard canonicalPath(processPrefix) == canonicalPath(prefix.path) else { return false }
                }
                return readIdentity(identity.pid) == identity
            }
        }
        throw StopError.enumerationFailed
    }

    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// A renamed temporary loader is owned only if its mapped ntdll comes from
    /// our Runtime. A matching .exe name alone is never sufficient.
    static func mappedRuntimePIDs(_ output: String, root: String) -> Set<Int32> {
        var pid: Int32?
        var result = Set<Int32>()
        for line in output.split(separator: "\n") {
            if line.first == "p" { pid = Int32(line.dropFirst()) }
            if line.first == "n", let pid {
                let path = canonicalPath(String(line.dropFirst()))
                if belongsToRuntime(path, root: root),
                   path.hasSuffix("/ntdll.so") { result.insert(pid) }
            }
        }
        return result
    }

    private static func runtimeMappedPIDs(_ candidates: [Identity], root: String) throws -> Set<Int32> {
        guard !candidates.isEmpty else { return [] }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Arclume-ProcessScan-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw StopError.enumerationFailed
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-n", "-P", "-a", "-p", candidates.map { String($0.pid) }.joined(separator: ","), "-d", "txt", "-Fpn"]
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw StopError.enumerationFailed }
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard process.terminationReason == .exit,
              process.terminationStatus == 0 || process.terminationStatus == 1,
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8 * 1024 * 1024 else {
            throw StopError.enumerationFailed
        }
        return mappedRuntimePIDs(try String(contentsOf: url, encoding: .utf8), root: root)
    }

    /// Read only WINEPREFIX from the process environment; never persist or log
    /// the remaining environment (which may contain credentials).
    static func winePrefix(pid: Int32) -> String? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4, size <= 4 * 1024 * 1024 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return nil }
        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { $0.copyBytes(from: bytes.prefix(4)) }
        guard argc >= 0 else { return nil }
        var index = 4
        while index < size && bytes[index] != 0 { index += 1 }
        while index < size && bytes[index] == 0 { index += 1 }
        for _ in 0..<argc {
            while index < size && bytes[index] != 0 { index += 1 }
            index += 1
        }
        while index < size {
            let start = index
            while index < size && bytes[index] != 0 { index += 1 }
            let entry = String(decoding: bytes[start..<index], as: UTF8.self)
            if entry.hasPrefix("WINEPREFIX=") { return String(entry.dropFirst(11)) }
            index += 1
        }
        return nil
    }

    static func readIdentity(_ pid: Int32) -> Identity? {
        guard pid > 1, pid != getpid() else { return nil }
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
                == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid(), info.pbi_status != SZOMB else { return nil }
        // PROC_PIDPATHINFO_MAXSIZE is a C expression macro not imported by Swift.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return Identity(pid: pid, startedSeconds: info.pbi_start_tvsec,
                        startedMicroseconds: info.pbi_start_tvusec,
                        executable: URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path)
    }
}
