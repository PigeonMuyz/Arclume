import Foundation
import Testing
@testable import Arclume

struct WineMonoSupportTests {
    @Test func monoPackageMatchesTheWine11SourceLock() throws {
        #expect(WineMonoSupport.package.version == "10.4.1")
        #expect(WineMonoSupport.package.byteCount == 85_504_000)
        #expect(WineMonoSupport.package.originURL.host == "github.com")
    }

    @Test func addonCacheDoesNotDisableDotNetOrChangeGlobalCache() {
        var environment = ["XDG_CACHE_HOME": "/user/cache", "WINEDLLOVERRIDES": "d3d11=n,b"]
        WineMonoSupport.applyEnvironment(to: &environment, root: URL(fileURLWithPath: "/isolated/addons"))
        #expect(environment["WINE_HOST_XDG_CACHE_HOME"] == "/isolated/addons")
        #expect(environment["XDG_CACHE_HOME"] == "/user/cache")
        #expect(environment["WINEDLLOVERRIDES"] == "d3d11=n,b")
    }

    @Test func verifiedPackageIsStagedIdempotentlyAndCorruptionIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mono-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.msi")
        let data = Data("tiny installer fixture".utf8)
        try data.write(to: source)
        let material = WineMonoSupport.Package(version: "1", archive: "mono.msi",
            originURL: URL(string: "https://fixture.test/mono.msi")!,
            sha256: try DownloadedResourceFiles.hash(source), byteCount: Int64(data.count))
        let cache = root.appendingPathComponent("cache")
        try WineMonoSupport.stage(source: source, root: cache, material: material)
        try WineMonoSupport.stage(source: source, root: cache, material: material)
        #expect(try Data(contentsOf: cache.appendingPathComponent("wine/mono.msi")) == data)
        try Data("bad".utf8).write(to: source)
        #expect(throws: (any Error).self) {
            try WineMonoSupport.stage(source: source, root: cache, material: material)
        }
        #expect(try Data(contentsOf: cache.appendingPathComponent("wine/mono.msi")) == data)
    }
}
