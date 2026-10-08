//
//  ArclumeGameLogStore.swift
//  Arclume
//

import Foundation

/// Owns the user-visible JX3/Wine diagnostics. Keeping every related log in
/// one place makes support exports predictable and prevents failed helpers
/// from consuming storage without a bound.
enum ArclumeGameLogStore {
    nonisolated static let maximumStorageBytes: UInt64 = 50 * 1024 * 1024

    nonisolated static var directoryURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/Arclume", isDirectory: true)
    }

    /// Retained only for cleanup of logs created before the shared diagnostics
    /// directory was introduced.
    nonisolated static var legacyDirectoryURL: URL {
        ARCLUME_SUPPORT_FOLDER_URL
            .appendingPathComponent("OnlineGameLogs", isDirectory: true)
    }

    nonisolated static var storageUsageText: String {
        let bytes = storageUsageBytes(in: managedDirectories)
        return "\(formattedSize(bytes)) / \(formattedSize(maximumStorageBytes))"
    }

    nonisolated static func createLaunchLogURL() throws -> URL {
        try ensureDirectoryExists()
        enforceStorageLimit()

        let timestamp = Int(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(8)
        let url = directoryURL.appendingPathComponent("JX3-\(timestamp)-\(suffix).log")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    /// Returns a Finder-safe directory after applying the same retention rule
    /// used by launch and crash collection.
    nonisolated static func directoryForUser() -> URL {
        try? ensureDirectoryExists()
        enforceStorageLimit()
        return directoryURL
    }

    nonisolated static func enforceStorageLimit() {
        enforceStorageLimit(in: managedDirectories, maximumBytes: maximumStorageBytes)
    }

    nonisolated static func enforceStorageLimit(
        in directories: [URL],
        maximumBytes: UInt64
    ) {
        let fileManager = FileManager.default
        let files = logFiles(in: directories, fileManager: fileManager)
        var total = files.reduce(UInt64.zero) { $0 + $1.size }
        guard total > maximumBytes else { return }

        for file in files.sorted(by: oldestFirst) where total > maximumBytes {
            guard (try? fileManager.removeItem(at: file.url)) != nil else { continue }
            total -= min(total, file.size)
        }
    }

    nonisolated static func storageUsageBytes(in directories: [URL]) -> UInt64 {
        logFiles(in: directories, fileManager: .default)
            .reduce(UInt64.zero) { $0 + $1.size }
    }

    private struct LogFile {
        let url: URL
        let size: UInt64
        let modifiedAt: Date
    }

    nonisolated private static var managedDirectories: [URL] {
        [directoryURL, legacyDirectoryURL]
    }

    nonisolated private static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    nonisolated private static func logFiles(
        in directories: [URL],
        fileManager: FileManager
    ) -> [LogFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        return directories.flatMap { directory -> [LogFile] in
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            return enumerator.compactMap { element -> LogFile? in
                guard let url = element as? URL,
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true
                else {
                    return nil
                }
                return LogFile(
                    url: url,
                    size: UInt64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            }
        }
    }

    nonisolated private static func oldestFirst(_ lhs: LogFile, _ rhs: LogFile) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt < rhs.modifiedAt
        }
        return lhs.url.path < rhs.url.path
    }

    nonisolated private static func formattedSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
