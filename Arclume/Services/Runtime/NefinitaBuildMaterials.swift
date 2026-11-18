import Foundation

/// Metadata only: original source archives remain outside the App bundle.
nonisolated struct NefinitaBuildMaterial: Codable, Sendable {
    let id: String
    let version: String
    let archive: String
    let originURL: URL
    let sha256: String
    let byteCount: Int64
    let objectKey: String

    var name: String { id == "wine" ? "Wine 源码" : id == "finewine" ? "FineWine 补丁" : id }

    func validate() throws {
        guard id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil,
              version.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
              archive.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
              sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              byteCount > 0, byteCount < 2_000_000_000,
              Self.safeHTTPS(originURL) else { throw NefinitaBuildError.invalidRecipe }
        let expected = id == "wine"
            ? "components/source/codeweavers-wine/org.codeweavers.wine-source/\(version)/\(sha256)/\(archive)"
            : "components/source/\(id)/dev.nefinita.source.\(id)/\(version)/\(sha256)/\(archive)"
        guard objectKey == expected else { throw NefinitaBuildError.invalidRecipe }
    }

    func urls(baseURL: String?) throws -> [URL] {
        try validate()
        guard let baseURL, !baseURL.isEmpty else { return [originURL] }
        guard let base = URL(string: baseURL), Self.safeHTTPS(base) else { throw NefinitaBuildError.sourceUnavailable }
        return [base.appendingPathComponent(objectKey), originURL]
    }

    func accepts(_ file: URL) throws -> Bool {
        guard let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              info.isRegularFile == true, info.isSymbolicLink != true,
              info.fileSize == Int(byteCount) else { return false }
        return try DownloadedResourceFiles.hash(file) == sha256
    }

    private static func safeHTTPS(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }
}

nonisolated struct NefinitaBuildMaterials: Decodable, Sendable {
    let schemaVersion: Int
    let revision: String
    let materials: [NefinitaBuildMaterial]

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let file = bundle.url(forResource: "nefinita-build-materials", withExtension: "json") else {
            throw NefinitaBuildError.invalidRecipe
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }

    /// Locks have already been authenticated by NefinitaBuildRecipe. Never source shell text here.
    func validatedMaterials(sourceRoot: URL, wine: NefinitaWineSourceArchive) throws -> [NefinitaBuildMaterial] {
        guard schemaVersion == 1, revision == NefinitaRuntime.revision,
              Set(materials.map(\.id)).count == materials.count,
              Set(materials.map(\.archive)).count == materials.count else { throw NefinitaBuildError.invalidRecipe }
        var expected = Set<String>()
        for filename in ["FREETYPE_SOURCE.lock", "DEPENDENCIES.lock"] {
            let values = try Self.assignments(String(contentsOf: sourceRoot.appendingPathComponent("sources/\(filename)"), encoding: .utf8))
            for key in values.keys.filter({ $0.hasSuffix("_ARCHIVE") }) {
                let stem = String(key.dropLast(8))
                let id = stem.lowercased().replacingOccurrences(of: "_", with: "-")
                guard let item = materials.first(where: { $0.id == id }),
                      item.archive == values[key], item.version == values["\(stem)_VERSION"],
                      item.sha256 == values["\(stem)_SHA256"], item.originURL.absoluteString == values["\(stem)_URL"] else {
                    throw NefinitaBuildError.invalidRecipe
                }
                expected.insert(id)
            }
        }
        let patches = try Self.assignments(String(contentsOf: sourceRoot.appendingPathComponent("sources/FINEWINE_PATCHSET.lock"), encoding: .utf8))
        guard let patch = materials.first(where: { $0.id == "finewine" }),
              let patchRevision = patches["FINEWINE_PATCHSET_REVISION"],
              patch.version == patchRevision, patch.archive == "finewine-\(patchRevision).tar.gz",
              patch.originURL.absoluteString == "https://codeload.github.com/stoicswe/Endfield_FineWine/tar.gz/\(patchRevision)" else {
            throw NefinitaBuildError.invalidRecipe
        }
        expected.insert("finewine")
        guard expected == Set(materials.map(\.id)) else { throw NefinitaBuildError.invalidRecipe }
        try wine.validate(lock: String(contentsOf: sourceRoot.appendingPathComponent("sources/WINE_SOURCE.lock"), encoding: .utf8))
        let result = [NefinitaBuildMaterial(id: "wine", version: wine.version, archive: wine.archive,
            originURL: wine.originURL, sha256: wine.sha256, byteCount: Int64(wine.byteCount), objectKey: wine.objectKey)] + materials
        for material in result { try material.validate() }
        return result
    }

    static func assignments(_ text: String) throws -> [String: String] {
        let regex = try NSRegularExpression(pattern: #"^([A-Z][A-Z0-9_]*)="([^"$`\\]*)"$"#)
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let keyRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line),
                  values[String(line[keyRange])] == nil else { throw NefinitaBuildError.invalidRecipe }
            values[String(line[keyRange])] = String(line[valueRange])
        }
        return values
    }
}

/// A barrier: all archives must be cached and verified before any build script may start.
nonisolated struct NefinitaBuildMaterialCache: Sendable {
    typealias Fetch = @Sendable (NefinitaBuildMaterial, URL, @escaping @Sendable (Int64) -> Void) async throws -> URL
    private let fetch: Fetch
    private let retryDelay: Duration

    init(retryDelay: Duration = .seconds(1), fetch: Fetch? = nil) {
        self.retryDelay = retryDelay
        self.fetch = fetch ?? Self.download
    }

    @concurrent func prepare(_ materials: [NefinitaBuildMaterial], baseURL: String?, cacheRoot: URL,
                             progress: @escaping @Sendable (ComponentDownloadCoordinator.Snapshot) -> Void) async throws -> [String: URL] {
        guard Set(materials.map(\.archive)).count == materials.count else { throw NefinitaBuildError.invalidRecipe }
        for item in materials { _ = try item.urls(baseURL: baseURL) }
        let state = ProgressState(materials: materials, callback: progress)
        var files: [String: URL] = [:]
        try await withThrowingTaskGroup(of: (String, URL).self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                group.addTask {
                    let item = materials[index]
                    state.start(index)
                    let file = try await cached(item, baseURL: baseURL, cacheRoot: cacheRoot) { state.update(index, bytes: $0) }
                    state.finish(index)
                    return (item.archive, file)
                }
            }
            for _ in 0..<min(3, materials.count) { enqueue(next); next += 1 }
            do {
                while let (archive, file) = try await group.next() {
                    files[archive] = file
                    if next < materials.count { enqueue(next); next += 1 }
                }
            } catch { group.cancelAll(); throw error }
        }
        try Task.checkCancellation()
        return files
    }

    private func cached(_ item: NefinitaBuildMaterial, baseURL: String?, cacheRoot: URL,
                        progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let fm = FileManager.default
        let directory = cacheRoot.appendingPathComponent(item.sha256, isDirectory: true)
        let target = directory.appendingPathComponent(item.archive)
        if try item.accepts(target) { return target }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if fm.fileExists(atPath: target.path) {
            try fm.moveItem(at: target, to: directory.appendingPathComponent(".invalid-\(UUID().uuidString)"))
        }
        for url in try item.urls(baseURL: baseURL) {
            for attempt in 0..<3 {
                try Task.checkCancellation()
                let downloaded: URL
                do { downloaded = try await fetch(item, url, progress) }
                catch {
                    if Task.isCancelled || error is CancellationError { throw CancellationError() }
                    if attempt < 2 { try await Task.sleep(for: retryDelay) }
                    continue
                }
                defer { try? fm.removeItem(at: downloaded) }
                try Task.checkCancellation()
                // Corrupt bytes are not a transport error; never silently change trust source.
                guard try item.accepts(downloaded) else { throw NefinitaBuildError.invalidRecipe }
                let staging = directory.appendingPathComponent(".download-\(UUID().uuidString)")
                defer { try? fm.removeItem(at: staging) }
                try fm.copyItem(at: downloaded, to: staging)
                try Task.checkCancellation()
                if try item.accepts(target) { return target }
                do { try fm.moveItem(at: staging, to: target) }
                catch { if try !item.accepts(target) { throw error } }
                return target
            }
        }
        throw NefinitaBuildError.failed("下载 \(item.name)")
    }

    static func stage(_ materials: [NefinitaBuildMaterial], files: [String: URL], into downloads: URL) throws {
        // Validate the whole set before staging even the first file.
        for item in materials {
            guard let file = files[item.archive], try item.accepts(file) else { throw NefinitaBuildError.invalidRecipe }
        }
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        for item in materials {
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: files[item.archive]!, to: downloads.appendingPathComponent(item.archive))
        }
    }

    private static func download(_ item: NefinitaBuildMaterial, _ url: URL,
                                 progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let (file, response) = try await ComponentArchiveDownloader.transferToDisk(request: request,
            maximumBytes: item.byteCount, progress: progress, configuration: configuration)
        guard response.statusCode == 200, response.url?.scheme == "https" else {
            try? FileManager.default.removeItem(at: file)
            throw NefinitaBuildError.sourceUnavailable
        }
        return file
    }

    private final class ProgressState: @unchecked Sendable {
        private let lock = NSLock()
        private let sizes: [Int64]
        private var received: [Int64]
        private var complete = Set<Int>()
        private var active = Set<Int>()
        private let started = ContinuousClock.now
        private var lastEvent = ContinuousClock.now
        private let callback: @Sendable (ComponentDownloadCoordinator.Snapshot) -> Void

        init(materials: [NefinitaBuildMaterial], callback: @escaping @Sendable (ComponentDownloadCoordinator.Snapshot) -> Void) {
            sizes = materials.map(\.byteCount)
            received = Array(repeating: 0, count: sizes.count)
            self.callback = callback
        }

        func update(_ index: Int, bytes: Int64) {
            lock.withLock {
                received[index] = max(received[index], min(sizes[index], max(0, bytes)))
                if lastEvent.duration(to: .now) >= .milliseconds(200) { emit() }
            }
        }
        func start(_ index: Int) { lock.withLock { active.insert(index); emit() } }
        func finish(_ index: Int) { lock.withLock { active.remove(index); complete.insert(index); emit() } }
        private func emit() {
            lastEvent = .now
            let elapsed = started.duration(to: .now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            let transferred = received.reduce(0, +)
            let readyBytes = sizes.indices.reduce(Int64(0)) { $0 + (complete.contains($1) ? sizes[$1] : received[$1]) }
            callback(.init(downloadedBytes: readyBytes, totalBytes: sizes.reduce(0, +),
                bytesPerSecond: seconds > 0 ? Double(transferred) / seconds : 0,
                completedCount: complete.count, totalCount: sizes.count, activeCount: active.count))
        }
    }
}
