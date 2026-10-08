import Foundation

/// Fetch only the pinned build inputs, not a working checkout or untrusted scripts.
nonisolated struct NefinitaSourceService: Sendable {
    typealias Fetch = @Sendable (URL) async throws -> URL
    private let fetch: Fetch

    init(fetch: Fetch? = nil) { self.fetch = fetch ?? Self.download }

    static func urls(path: String, recipe: NefinitaBuildRecipe, baseURL: String?) throws -> [URL] {
        guard DownloadableResourceCatalog.safePath(path), let hash = recipe.files[path],
              hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              recipe.revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              DownloadableResourceCatalog.safePath(recipe.version) else { throw NefinitaBuildError.invalidRecipe }
        var result: [URL] = []
        if let baseURL, !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let base = URL(string: baseURL), base.scheme == "https", base.host != nil,
                  base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else {
                throw NefinitaBuildError.sourceUnavailable
            }
            result.append(base.appendingPathComponent("components/build-recipe/nefinita/dev.nefinita.build-recipe/\(recipe.version)-\(recipe.revision.prefix(8))/\(hash)/\(path)"))
        }
        result.append(URL(string: "https://raw.githubusercontent.com/nefinita/mac-gamestater/\(recipe.revision)/runtime/\(path)")!)
        return result
    }

    @concurrent func prepare(recipe: NefinitaBuildRecipe, baseURL: String?, cacheRoot: URL,
                             progress: @escaping @Sendable (Int, Int) -> Void) async throws -> URL {
        let fm = FileManager.default
        guard recipe.revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else { throw NefinitaBuildError.invalidRecipe }
        let destination = cacheRoot.appendingPathComponent(recipe.revision, isDirectory: true)
        if let cached = try? recipe.validateSource(destination) { return cached }
        try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let staging = cacheRoot.appendingPathComponent(".source-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let paths = recipe.files.keys.sorted()
        progress(0, paths.count)
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            func enqueue(_ path: String) {
                group.addTask {
                    let candidates = try Self.urls(path: path, recipe: recipe, baseURL: baseURL)
                    let target = staging.appendingPathComponent(path)
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    for url in candidates {
                        try Task.checkCancellation()
                        do {
                            let file = try await fetch(url)
                            defer { try? FileManager.default.removeItem(at: file) }
                            // Transport is disk-backed; never execute an unchecked download.
                            guard let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                                  bytes > 0, bytes <= 2 * 1024 * 1024,
                                  try DownloadedResourceFiles.hash(file) == recipe.files[path] else {
                                throw NefinitaBuildError.invalidRecipe
                            }
                            try FileManager.default.moveItem(at: file, to: target)
                            return
                        } catch {
                            if Task.isCancelled || error is CancellationError { throw CancellationError() }
                            // A bad hash is not a transport failure: do not silently trust another source.
                            if let buildError = error as? NefinitaBuildError, case .invalidRecipe = buildError { throw buildError }
                        }
                    }
                    throw NefinitaBuildError.sourceUnavailable
                }
            }
            for _ in 0..<min(3, paths.count) { enqueue(paths[next]); next += 1 }
            var complete = 0
            while try await group.next() != nil {
                complete += 1
                progress(complete, paths.count)
                if next < paths.count { enqueue(paths[next]); next += 1 }
            }
        }
        try Task.checkCancellation()
        _ = try recipe.validateSource(staging)
        if fm.fileExists(atPath: destination.path) {
            try fm.moveItem(at: destination, to: cacheRoot.appendingPathComponent(".invalid-\(UUID().uuidString)"))
        }
        try fm.moveItem(at: staging, to: destination)
        return destination
    }

    private static func download(_ url: URL) async throws -> URL {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (file, response) = try await session.download(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https" else {
            try? FileManager.default.removeItem(at: file)
            throw NefinitaBuildError.sourceUnavailable
        }
        return file
    }
}
