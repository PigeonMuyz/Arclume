import Foundation

/// Read-only metadata. Cache files and list entries do not report compilation progress.
nonisolated struct JX3ShaderCacheSnapshot: Sendable {
    struct Cache: Sendable {
        let byteCount: Int64
        let isPartial: Bool
    }

    struct PrewarmList: Sendable {
        let entryCount: Int?
        let modifiedAt: Date?
    }

    let cache: Cache?
    let prewarmList: PrewarmList?

    private static let cacheEntryLimit = 32_768
    private static let prewarmByteLimit = 1_048_576

    static func prewarmListURL(for launcherURL: URL) -> URL {
        launcherURL.deletingLastPathComponent()
            .appendingPathComponent("Game/JX3/bin/zhcn_hd/data/material/Shader/_PreDrawShaderCodeContentList.txt")
    }

    @concurrent static func inspect(cacheDirectory: URL, prewarmList: URL?) async -> Self {
        Self(cache: inspectCache(cacheDirectory), prewarmList: prewarmList.flatMap(inspectPrewarmList))
    }

    private static func inspectCache(_ directory: URL) -> Cache? {
        let root = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard root?.isDirectory == true, root?.isSymbolicLink != true else { return nil }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var isPartial = false
        guard let entries = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
            errorHandler: { _, _ in isPartial = true; return true }
        ) else { return nil }

        var byteCount: Int64 = 0
        for (index, entry) in entries.enumerated() {
            guard !Task.isCancelled else { return nil }
            guard index < cacheEntryLimit else {
                isPartial = true
                break
            }
            guard let url = entry as? URL, let values = try? url.resourceValues(forKeys: keys) else {
                isPartial = true
                continue
            }
            if values.isSymbolicLink != true, values.isRegularFile == true, let size = values.fileSize {
                byteCount += Int64(size)
            }
        }
        return Cache(byteCount: byteCount, isPartial: isPartial)
    }

    private static func inspectPrewarmList(_ url: URL) -> PrewarmList? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
              values.isSymbolicLink != true else { return nil }

        var count: Int?
        if let size = values.fileSize, size <= prewarmByteLimit, let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let data = try? handle.read(upToCount: prewarmByteLimit + 1), data.count <= prewarmByteLimit,
               let text = String(data: data, encoding: .utf8) {
                count = text.split(whereSeparator: \.isNewline).count
            }
        }
        return PrewarmList(entryCount: count, modifiedAt: values.contentModificationDate)
    }
}
