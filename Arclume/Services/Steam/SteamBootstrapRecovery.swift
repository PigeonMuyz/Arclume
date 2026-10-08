import Foundation

nonisolated enum SteamBootstrapRecovery {
    static let maximumTailBytes = 32 * 1024

    static func logURL(in steamRoot: URL) -> URL {
        steamRoot.appendingPathComponent("logs/bootstrap_log.txt")
    }

    static func size(of url: URL) -> UInt64 {
        // URL resource values can be cached while Steam keeps appending.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    static func newTail(at url: URL, initialSize: UInt64) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let current = try handle.seekToEnd()
        let baseline = current < initialSize ? 0 : initialSize
        let start = max(baseline, current > UInt64(maximumTailBytes) ? current - UInt64(maximumTailBytes) : 0)
        try handle.seek(toOffset: start)
        return String(decoding: try handle.read(upToCount: maximumTailBytes) ?? Data(), as: UTF8.self)
    }

    static func completedButShuttingDown(_ tail: String) -> Bool {
        let lines = tail.split(whereSeparator: \.isNewline)
        guard let last = lines.last, last.hasSuffix("Shutdown") else { return false }
        return lines.suffix(12).contains {
            $0.contains("更新完成，正在启动 Steam") || $0.contains("Update complete, launching Steam")
        }
    }

    static func hasStalledBootstrapper(_ processes: [ArclumeWineStopService.Identity]) -> Bool {
        let names = processes.map { URL(fileURLWithPath: $0.executable).lastPathComponent.lowercased() }
        return names.contains("steam.exe") && !names.contains("steamwebhelper.exe")
    }
}
