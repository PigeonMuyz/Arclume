import Foundation

nonisolated struct NefinitaWineSourceArchive: Decodable, Sendable {
    let schemaVersion: Int
    let version: String
    let archive: String
    let sha256: String
    let byteCount: Int
    let originURL: URL
    let objectKey: String

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let file = bundle.url(forResource: "nefinita-wine-source", withExtension: "json") else {
            throw NefinitaBuildError.invalidRecipe
        }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
        try value.validate()
        return value
    }

    func validate() throws {
        guard schemaVersion == 1, byteCount > 0, byteCount < 2_000_000_000,
              version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
              sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              archive == "crossover-sources-\(version).tar.gz",
              originURL.absoluteString == "https://media.codeweavers.com/pub/crossover/source/\(archive)",
              objectKey == "components/source/codeweavers-wine/org.codeweavers.wine-source/\(version)/\(sha256)/\(archive)" else {
            throw NefinitaBuildError.invalidRecipe
        }
    }

    /// The mirror metadata must agree with the authenticated upstream recipe.
    func validate(lock: String) throws {
        try validate()
        let lines = Set(lock.components(separatedBy: .newlines))
        guard lines.contains("CROSSOVER_VERSION=\"\(version)\""),
              lines.contains("SOURCE_ARCHIVE=\"\(archive)\""),
              lines.contains("SOURCE_SHA256=\"\(sha256)\""),
              lines.contains("SOURCE_URL=\"\(originURL.absoluteString)\"") else {
            throw NefinitaBuildError.invalidRecipe
        }
    }

    func urls(baseURL: String?) throws -> [URL] {
        try validate()
        guard let baseURL, !baseURL.isEmpty else { return [originURL] }
        guard let base = URL(string: baseURL), base.scheme == "https", base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else {
            throw NefinitaBuildError.sourceUnavailable
        }
        return [base.appendingPathComponent(objectKey), originURL]
    }

    func accepts(_ file: URL) throws -> Bool {
        guard let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == byteCount else { return false }
        return try DownloadedResourceFiles.hash(file) == sha256
    }
}

/// A disk-backed, content-addressed archive cache shared by independent build sessions.
nonisolated struct NefinitaWineSourceCache: Sendable {
    typealias Fetch = @Sendable (URL) async throws -> URL
    private let fetch: Fetch
    init(fetch: Fetch? = nil) { self.fetch = fetch ?? Self.download }

    @concurrent func prepare(_ source: NefinitaWineSourceArchive, baseURL: String?, cacheRoot: URL,
                             onStatus: @escaping @Sendable (String) -> Void) async throws -> URL {
        let urls = try source.urls(baseURL: baseURL)
        let fm = FileManager.default
        let directory = cacheRoot.appendingPathComponent(source.sha256, isDirectory: true)
        let target = directory.appendingPathComponent(source.archive)
        onStatus("检查 Wine 源码缓存…")
        if try source.accepts(target) {
            onStatus("使用已缓存的 Wine 源码…")
            return target
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Preserve corrupt/partial old cache for diagnosis, never mistake it for ready input.
        if fm.fileExists(atPath: target.path) {
            try fm.moveItem(at: target, to: directory.appendingPathComponent(".invalid-\(UUID().uuidString)"))
        }
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            onStatus(index == 0 && urls.count > 1 ? "下载 Wine 源码（加速源）…" : "下载 Wine 源码（官方源）…")
            let downloaded: URL
            do { downloaded = try await fetch(url) }
            catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                continue
            }
            defer { try? fm.removeItem(at: downloaded) }
            try Task.checkCancellation()
            onStatus("检查 Wine 源码完整性…")
            // A checksum failure is not a network failure; fail closed.
            guard try source.accepts(downloaded) else { throw NefinitaBuildError.invalidRecipe }
            let staging = directory.appendingPathComponent(".download-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: staging) }
            try fm.copyItem(at: downloaded, to: staging)
            try Task.checkCancellation()
            if try source.accepts(target) { return target }
            try fm.moveItem(at: staging, to: target)
            return target
        }
        throw NefinitaBuildError.sourceUnavailable
    }

    private static func download(_ url: URL) async throws -> URL {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (file, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https" else {
            try? FileManager.default.removeItem(at: file)
            throw NefinitaBuildError.sourceUnavailable
        }
        return file
    }
}
