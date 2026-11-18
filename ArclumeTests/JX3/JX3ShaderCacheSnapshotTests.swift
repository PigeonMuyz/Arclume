import Foundation
import Testing
@testable import Arclume

struct JX3ShaderCacheSnapshotTests {
    @Test func reportsPersistedCacheAndGameListSeparately() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("JX3ShaderSnapshot-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let cache = root.appendingPathComponent("cache")
        let subdirectory = cache.appendingPathComponent("mesa_shader_cache/19")
        try fm.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 64).write(to: subdirectory.appendingPathComponent("entry"))
        let external = root.appendingPathComponent("external")
        try Data(repeating: 9, count: 128).write(to: external)
        try fm.createSymbolicLink(at: cache.appendingPathComponent("external-link"), withDestinationURL: external)

        let list = root.appendingPathComponent("_PreDrawShaderCodeContentList.txt")
        try Data("{00149d68-e85c-0d55-0000-000000000000}\r\n{f07e3940-2bc6-b15a-0000-000000000000}\r\n".utf8).write(to: list)
        let snapshot = await JX3ShaderCacheSnapshot.inspect(cacheDirectory: cache, prewarmList: list)

        #expect(snapshot.cache?.byteCount == 64)
        #expect(snapshot.cache?.isPartial == false)
        #expect(snapshot.prewarmList?.entryCount == 2)
        #expect(snapshot.prewarmList?.modifiedAt != nil)
    }

    @Test func missingPathsDoNotGetCreated() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JX3ShaderSnapshot-\(UUID().uuidString)")
        let snapshot = await JX3ShaderCacheSnapshot.inspect(
            cacheDirectory: root.appendingPathComponent("cache"), prewarmList: root.appendingPathComponent("list.txt")
        )
        #expect(snapshot.cache == nil)
        #expect(snapshot.prewarmList == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
