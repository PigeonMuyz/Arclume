import Foundation

/// Captures only the selected program's stderr, including children inheriting the pipe.
/// No input, command-line arguments, registry or application data is collected.
nonisolated final class WindowsProgramDiagnosticLog: @unchecked Sendable {
    private let pipe = Pipe()
    private let output: FileHandle
    private let lock = NSLock()
    private var written = 0
    private var closed = false
    static let byteLimit = 4 * 1024 * 1024
    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return closed
    }

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        output = try FileHandle(forWritingTo: url)
    }

    func attach(to process: Process) {
        process.standardError = pipe
        // Break the capture cycle on EOF, after the final child closes stderr.
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            if data.isEmpty { finish(); return }
            append(data)
        }
    }

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !closed, written < Self.byteLimit else { return }
        let chunk = data.prefix(Self.byteLimit - written)
        try? output.write(contentsOf: chunk)
        written += chunk.count
        if written == Self.byteLimit { try? output.write(contentsOf: Data("\n[Arclume: diagnostic log reached 4 MiB; further output omitted]\n".utf8)) }
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        pipe.fileHandleForReading.readabilityHandler = nil
        try? output.close()
        try? pipe.fileHandleForReading.close()
    }

    static func configure(_ process: Process, executable: URL?, bottle: URL,
                          environment: inout [String: String]) throws -> WindowsProgramDiagnosticLog? {
        guard let executable, let rule = GameAdaptationRules.matching(executable),
              rule.captureErrors == true, rule.allows(executable, in: bottle) else { return nil }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arclume/WindowsProgramLogs")
        guard root.resolvingSymlinksInPath().path == root.standardizedFileURL.path else { throw GameRemovalError.unsafePath }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent("\(UUID().uuidString).log")
        let capture = try WindowsProgramDiagnosticLog(url: url)
        capture.append(Data("Arclume Windows diagnostic: \(rule.name) / \(executable.lastPathComponent) / \(Date().ISO8601Format())\n".utf8))
        environment["WINEDEBUG"] = "-all,err+all"
        capture.attach(to: process)
        return capture
    }
}
