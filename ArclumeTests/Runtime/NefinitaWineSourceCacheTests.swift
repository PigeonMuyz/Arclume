import Foundation
import Testing
@testable import Arclume

struct NefinitaWineSourceCacheTests {
    private actor Requests {
        var hosts: [String] = []
        func append(_ url: URL) { hosts.append(url.host ?? "") }
    }
    private func fixture() throws -> (URL, NefinitaWineSourceArchive, Data) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wine-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data("test source archive".utf8), file = root.appendingPathComponent("seed")
        try data.write(to: file)
        let sha = try DownloadedResourceFiles.hash(file)
        return (root, NefinitaWineSourceArchive(schemaVersion: 1, version: "26.3.0",
            archive: "crossover-sources-26.3.0.tar.gz", sha256: sha, byteCount: data.count,
            originURL: URL(string: "https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz")!,
            objectKey: "components/source/codeweavers-wine/org.codeweavers.wine-source/26.3.0/\(sha)/crossover-sources-26.3.0.tar.gz"), data)
    }
    @Test func officialFallbackAndOfflineReuseAcrossBuilds() async throws {
        let (root, source, data) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Requests()
        let service = NefinitaWineSourceCache { url in
            await calls.append(url)
            if url.host == "mirror.test" { throw URLError(.timedOut) }
            let file = root.appendingPathComponent(UUID().uuidString)
            try data.write(to: file)
            return file
        }
        let cache = root.appendingPathComponent("cache")
        let result = try await service.prepare(source, baseURL: "https://mirror.test", cacheRoot: cache) { _ in }
        #expect(await calls.hosts == ["mirror.test", "media.codeweavers.com"])
        let offline = NefinitaWineSourceCache { _ in throw URLError(.notConnectedToInternet) }
        let reused = try await offline.prepare(source, baseURL: nil, cacheRoot: cache) { _ in }
        #expect(reused == result)
        #expect(try source.accepts(result))
    }
    @Test func badMirrorIsNotCachedAndDoesNotFallBack() async throws {
        let (root, source, data) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = Requests()
        let service = NefinitaWineSourceCache { url in
            await calls.append(url)
            let file = root.appendingPathComponent(UUID().uuidString)
            try Data(repeating: 0, count: data.count).write(to: file)
            return file
        }
        let cache = root.appendingPathComponent("cache")
        await #expect(throws: NefinitaBuildError.self) {
            try await service.prepare(source, baseURL: "https://mirror.test", cacheRoot: cache) { _ in }
        }
        #expect(await calls.hosts == ["mirror.test"])
        #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent(source.sha256).appendingPathComponent(source.archive).path))
    }
    @Test func bundledPinAndInvalidLockOrEndpointAreRejected() throws {
        let source = try NefinitaWineSourceArchive.load()
        #expect(source.byteCount == 149054023)
        let lock = "CROSSOVER_VERSION=\"\(source.version)\"\nSOURCE_ARCHIVE=\"\(source.archive)\"\nSOURCE_SHA256=\"\(source.sha256)\"\nSOURCE_URL=\"\(source.originURL.absoluteString)\""
        try source.validate(lock: lock)
        #expect(throws: NefinitaBuildError.self) { try source.validate(lock: lock.replacingOccurrences(of: "26.3.0", with: "26.2.0")) }
        for base in ["http://mirror.test", "https://user:secret@mirror.test", "https://mirror.test?token=secret"] {
            #expect(throws: NefinitaBuildError.self) { try source.urls(baseURL: base) }
        }
    }
}
