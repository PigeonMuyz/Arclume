import Foundation
import Testing
@testable import Arclume

struct NefinitaBuildMaterialsTests {
    private actor Tracker {
        var active = 0
        var maximum = 0
        var calls: [String] = []
        func start(_ value: String) { active += 1; maximum = max(maximum, active); calls.append(value) }
        func finish() { active -= 1 }
    }

    private func fixture(count: Int = 5) throws -> (URL, [NefinitaBuildMaterial], [String: Data]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("build-materials-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var items: [NefinitaBuildMaterial] = [], bytes: [String: Data] = [:]
        for index in 0..<count {
            let id = "fixture-\(index)", data = Data("archive \(index)".utf8)
            let seed = root.appendingPathComponent("seed-\(index)")
            try data.write(to: seed)
            let sha = try DownloadedResourceFiles.hash(seed), archive = "\(id).tar.xz"
            items.append(.init(id: id, version: "1.0", archive: archive, originURL: URL(string: "https://upstream.test/\(archive)")!,
                sha256: sha, byteCount: Int64(data.count), objectKey: "components/source/\(id)/dev.nefinita.source.\(id)/1.0/\(sha)/\(archive)"))
            bytes[id] = data
        }
        return (root, items, bytes)
    }

    @Test func allMaterialsDownloadWithThreeSlotsThenStageAndReuseOffline() async throws {
        let (root, items, data) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tracker = Tracker(), cache = root.appendingPathComponent("cache"), downloads = root.appendingPathComponent("downloads")
        let service = NefinitaBuildMaterialCache(retryDelay: .zero) { item, _, progress in
            await tracker.start(item.id)
            try await Task.sleep(for: .milliseconds(20))
            let file = root.appendingPathComponent(UUID().uuidString)
            try data[item.id]!.write(to: file)
            progress(item.byteCount)
            await tracker.finish()
            #expect(!FileManager.default.fileExists(atPath: downloads.path))
            return file
        }
        let files = try await service.prepare(items, baseURL: "https://mirror.test", cacheRoot: cache) { _ in }
        #expect(await tracker.maximum == 3)
        #expect(await tracker.calls.count == items.count)
        try NefinitaBuildMaterialCache.stage(items, files: files, into: downloads)
        for item in items { #expect(try item.accepts(downloads.appendingPathComponent(item.archive))) }
        let offline = NefinitaBuildMaterialCache { _, _, _ in throw URLError(.notConnectedToInternet) }
        let reused = try await offline.prepare(items, baseURL: nil, cacheRoot: cache) { _ in }
        #expect(reused == files)
    }

    @Test func networkRetriesBeforeOfficialFallback() async throws {
        let (root, items, data) = try fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let tracker = Tracker()
        let service = NefinitaBuildMaterialCache(retryDelay: .zero) { item, url, _ in
            await tracker.start(url.host!)
            await tracker.finish()
            if url.host == "mirror.test" { throw URLError(.secureConnectionFailed) }
            let file = root.appendingPathComponent(UUID().uuidString)
            try data[item.id]!.write(to: file)
            return file
        }
        _ = try await service.prepare(items, baseURL: "https://mirror.test", cacheRoot: root.appendingPathComponent("cache")) { _ in }
        #expect(await tracker.calls == ["mirror.test", "mirror.test", "mirror.test", "upstream.test"])
    }

    @Test func badHashFailsClosedWithoutFallbackOrReadyCache() async throws {
        let (root, items, _) = try fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let tracker = Tracker(), item = items[0], cache = root.appendingPathComponent("cache")
        let service = NefinitaBuildMaterialCache(retryDelay: .zero) { item, url, _ in
            await tracker.start(url.host!)
            let file = root.appendingPathComponent(UUID().uuidString)
            try Data(repeating: 0, count: Int(item.byteCount)).write(to: file)
            return file
        }
        await #expect(throws: NefinitaBuildError.self) {
            try await service.prepare(items, baseURL: "https://mirror.test", cacheRoot: cache) { _ in }
        }
        #expect(await tracker.calls == ["mirror.test"])
        #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent(item.sha256).appendingPathComponent(item.archive).path))
    }

    @Test func failurePreservesCompletedCacheAndDoesNotStagePartialSet() async throws {
        let (root, items, data) = try fixture(count: 3)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache"), downloads = root.appendingPathComponent("downloads")
        let service = NefinitaBuildMaterialCache(retryDelay: .zero) { item, _, _ in
            if item.id == items[2].id { try await Task.sleep(for: .milliseconds(50)); throw URLError(.timedOut) }
            let file = root.appendingPathComponent(UUID().uuidString)
            try data[item.id]!.write(to: file)
            return file
        }
        await #expect(throws: NefinitaBuildError.self) { try await service.prepare(items, baseURL: nil, cacheRoot: cache) { _ in } }
        for item in items.prefix(2) {
            #expect(try item.accepts(cache.appendingPathComponent(item.sha256).appendingPathComponent(item.archive)))
        }
        #expect(throws: NefinitaBuildError.self) { try NefinitaBuildMaterialCache.stage(items, files: [:], into: downloads) }
        #expect(!FileManager.default.fileExists(atPath: downloads.path))
        let tracker = Tracker()
        let retry = NefinitaBuildMaterialCache { item, _, _ in
            await tracker.start(item.id)
            let file = root.appendingPathComponent(UUID().uuidString)
            try data[item.id]!.write(to: file)
            return file
        }
        _ = try await retry.prepare(items, baseURL: nil, cacheRoot: cache) { _ in }
        #expect(await tracker.calls == [items[2].id])
    }

    @Test func cancelledTransferDoesNotPublishReadyCache() async throws {
        let (root, items, _) = try fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = NefinitaBuildMaterialCache { _, _, _ in
            try await Task.sleep(for: .seconds(10))
            throw CancellationError()
        }
        let task = Task { try await service.prepare(items, baseURL: nil, cacheRoot: root.appendingPathComponent("cache")) { _ in } }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func bundledManifestCoversAllLockedDependenciesAndPatchSnapshot() throws {
        let (root, _, _) = try fixture(count: 0)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try NefinitaBuildMaterials.load(), wine = try NefinitaWineSourceArchive.load()
        let source = root.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        var lock = ""
        for item in manifest.materials where item.id != "finewine" {
            let stem = item.id.uppercased().replacingOccurrences(of: "-", with: "_")
            lock += "\(stem)_VERSION=\"\(item.version)\"\n\(stem)_ARCHIVE=\"\(item.archive)\"\n\(stem)_URL=\"\(item.originURL.absoluteString)\"\n\(stem)_SHA256=\"\(item.sha256)\"\n"
        }
        try lock.write(to: source.appendingPathComponent("DEPENDENCIES.lock"), atomically: true, encoding: .utf8)
        try "".write(to: source.appendingPathComponent("FREETYPE_SOURCE.lock"), atomically: true, encoding: .utf8)
        let patch = try #require(manifest.materials.first { $0.id == "finewine" })
        try "FINEWINE_PATCHSET_REVISION=\"\(patch.version)\"".write(to: source.appendingPathComponent("FINEWINE_PATCHSET.lock"), atomically: true, encoding: .utf8)
        try "CROSSOVER_VERSION=\"\(wine.version)\"\nSOURCE_ARCHIVE=\"\(wine.archive)\"\nSOURCE_SHA256=\"\(wine.sha256)\"\nSOURCE_URL=\"\(wine.originURL.absoluteString)\"".write(to: source.appendingPathComponent("WINE_SOURCE.lock"), atomically: true, encoding: .utf8)
        #expect(try manifest.validatedMaterials(sourceRoot: root, wine: wine).count == 23)
        let missing = NefinitaBuildMaterials(schemaVersion: 1, revision: manifest.revision, materials: Array(manifest.materials.dropLast()))
        #expect(throws: NefinitaBuildError.self) { try missing.validatedMaterials(sourceRoot: root, wine: wine) }
        try lock.replacingOccurrences(of: "FREETYPE_VERSION=\"2.13.3\"", with: "FREETYPE_VERSION=\"0.0\"").write(to: source.appendingPathComponent("DEPENDENCIES.lock"), atomically: true, encoding: .utf8)
        #expect(throws: NefinitaBuildError.self) { try manifest.validatedMaterials(sourceRoot: root, wine: wine) }
    }

    @Test func shellExpansionAndUnsafeEndpointsAreRejected() throws {
        for line in ["FOO=\"$(curl attacker)\"", "FOO=\"`id`\"", "FOO=\"safe\"\nFOO=\"other\"", "source evil"] {
            #expect(throws: NefinitaBuildError.self) { try NefinitaBuildMaterials.assignments(line) }
        }
        let (root, items, _) = try fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        for base in ["http://mirror.test", "https://user:password@mirror.test", "https://mirror.test?secret=1"] {
            #expect(throws: NefinitaBuildError.self) { try items[0].urls(baseURL: base) }
        }
    }
}
