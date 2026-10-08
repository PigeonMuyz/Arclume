import Foundation
import Testing
@testable import Arclume

struct NefinitaSourceServiceTests {
    private actor Requests {
        var hosts: [String] = []
        func append(_ url: URL) { hosts.append(url.host ?? "") }
    }

    private func fixture() throws -> (URL, NefinitaBuildRecipe, Data) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nefinita-source-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data("verified build input".utf8)
        let seed = root.appendingPathComponent("seed")
        try data.write(to: seed)
        let recipe = NefinitaBuildRecipe(schemaVersion: 1, provider: "Nefinita", revision: NefinitaRuntime.revision,
            version: NefinitaRuntime.version, files: ["runtime.env": try DownloadedResourceFiles.hash(seed)])
        return (root, recipe, data)
    }

    @Test func URLsUsePinnedRevisionAndHTTPSWithoutCredentials() throws {
        let recipe = try NefinitaBuildRecipe.load()
        let urls = try NefinitaSourceService.urls(path: "runtime.env", recipe: recipe, baseURL: "https://download.example.test/arclume")
        #expect(urls.count == 2)
        #expect(urls[0].path.contains("/components/build-recipe/nefinita/dev.nefinita.build-recipe/"))
        #expect(urls[0].path.contains(recipe.files["runtime.env"]!))
        #expect(urls[1].path == "/nefinita/mac-gamestater/\(recipe.revision)/runtime/runtime.env")
        #expect(try NefinitaSourceService.urls(path: "runtime.env", recipe: recipe, baseURL: nil).count == 1)
        for base in ["http://download.example.test", "https://user:secret@download.example.test", "https://download.example.test?secret=1"] {
            #expect(throws: NefinitaBuildError.self) { try NefinitaSourceService.urls(path: "runtime.env", recipe: recipe, baseURL: base) }
        }
        #expect(throws: NefinitaBuildError.self) { try NefinitaSourceService.urls(path: "../outside", recipe: recipe, baseURL: nil) }
    }

    @Test func mirrorFailureFallsBackToGitHubAndVerifiedCacheSkipsNetwork() async throws {
        let (root, recipe, data) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let requests = Requests()
        let service = NefinitaSourceService { url in
            await requests.append(url)
            if url.host == "download.example.test" { throw NefinitaBuildError.sourceUnavailable }
            let file = root.appendingPathComponent(UUID().uuidString)
            try data.write(to: file)
            return file
        }
        let cache = root.appendingPathComponent("cache")
        let source = try await service.prepare(recipe: recipe, baseURL: "https://download.example.test", cacheRoot: cache) { _, _ in }
        #expect(try Data(contentsOf: source.appendingPathComponent("runtime.env")) == data)
        #expect(await requests.hosts == ["download.example.test", "raw.githubusercontent.com"])
        let offline = NefinitaSourceService { _ in throw NefinitaBuildError.sourceUnavailable }
        let reused = try await offline.prepare(recipe: recipe, baseURL: nil, cacheRoot: cache) { _, _ in }
        #expect(reused == source)
    }

    @Test func modifiedMirrorContentIsNotExecutedOrPublishedToCache() async throws {
        let (root, recipe, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let requests = Requests()
        let service = NefinitaSourceService { url in
            await requests.append(url)
            let file = root.appendingPathComponent(UUID().uuidString)
            try Data("modified script".utf8).write(to: file)
            return file
        }
        let cache = root.appendingPathComponent("cache")
        await #expect(throws: NefinitaBuildError.self) {
            try await service.prepare(recipe: recipe, baseURL: "https://download.example.test", cacheRoot: cache) { _, _ in }
        }
        #expect(await requests.hosts == ["download.example.test"])
        #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent(recipe.revision).path))
    }

    @Test func unavailableSourcesDoNotProduceAReadyCache() async throws {
        let (root, recipe, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let service = NefinitaSourceService { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: NefinitaBuildError.self) {
            try await service.prepare(recipe: recipe, baseURL: nil, cacheRoot: cache) { _, _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent(recipe.revision).path))
    }
}
