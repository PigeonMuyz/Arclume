import CryptoKit
import Foundation
import Testing
@testable import Arclume

struct DownloadableResourceTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("DownloadableResourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func component(
        bytes: Data,
        type: String = "runtime",
        name: String = "arclume-wine",
        fileName: String = "arclume-wine-1.2.3-x86_64.tar.xz",
        unpack: Bool = false
    ) throws -> DownloadableResourceCatalog.Component {
        let object: [String: Any] = [
            "type": type,
            "name": name,
            "id": "io.arclume.runtime.wine",
            "version": "1.2.3",
            "fileName": fileName,
            "sha256": digest(bytes),
            "byteCount": bytes.count,
            "unpack": unpack
        ]
        return try JSONDecoder().decode(
            DownloadableResourceCatalog.Component.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func rejectsUnavailable(_ operation: () throws -> URL) -> Bool {
        do {
            _ = try operation()
            return false
        } catch let error as ResourceDownloadError {
            if case .unavailable = error { return true }
            return false
        } catch {
            return false
        }
    }

    private func rejectsInvalidDownload(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return false
        } catch let error as ResourceDownloadError {
            if case .invalidDownload = error { return true }
            return false
        } catch {
            return false
        }
    }

    @Test func bundledCatalogLoadsAndRetainsItsPrecompiledRuntimeOption() throws {
        let catalog = try DownloadableResourceCatalog.load()

        #expect(catalog.schemaVersion == 1)
        #expect(catalog.runtimes.count == 1)
        #expect(catalog.runtimeOptions.count == 1)
        let option = try #require(catalog.runtimeOptions.first)
        #expect(option.id == "io.arclume.runtime.wine")
        #expect(option.provider == "Arclume")
        #expect(option.strategies.count == 1)
        let strategy = try #require(option.strategies.first)
        #expect(strategy.delivery == .precompiled)
        #expect(strategy.componentID == "io.arclume.runtime.wine")
        #expect(strategy.recipeID == nil)
    }

    @Test func resourceURLRequiresAnHTTPSBaseAndUsesTheComponentObjectKey() throws {
        let bytes = Data("runtime payload".utf8)
        let item = try component(bytes: bytes)

        #expect(item.objectKey == "components/runtime/arclume-wine/io.arclume.runtime.wine/1.2.3/\(digest(bytes))/arclume-wine-1.2.3-x86_64.tar.xz")

        let url = try DownloadableResourceCatalog.downloadURL(
            base: "https://resources.example.invalid/oss/",
            component: item
        )
        #expect(url.scheme == "https")
        #expect(url.host == "resources.example.invalid")
        #expect(url.path.hasSuffix(item.objectKey))

        #expect(rejectsUnavailable {
            try DownloadableResourceCatalog.downloadURL(base: nil, component: item)
        })
        #expect(rejectsUnavailable {
            try DownloadableResourceCatalog.downloadURL(base: "", component: item)
        })
        #expect(rejectsUnavailable {
            try DownloadableResourceCatalog.downloadURL(base: "http://resources.example.invalid/oss", component: item)
        })
    }

    @Test func resourcePathValidationRejectsTraversalAndAbsolutePaths() {
        for unsafePath in [
            "../outside",
            "Libs/../../outside",
            "/tmp/payload",
            "Libs\\wine\\wine",
            "Libs//wine"
        ] {
            #expect(!DownloadableResourceCatalog.safePath(unsafePath))
        }

        #expect(DownloadableResourceCatalog.safePath("Libs/wine/x86_64-unix/wine"))
    }

    @Test func resourceHashStreamsFilesLargerThanOneChunk() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let bytes = Data(repeating: 0xA7, count: 2 * 1024 * 1024 + 37)
        let archive = root.appendingPathComponent("large-resource.tar.xz")
        try bytes.write(to: archive)

        #expect(try DownloadedResourceFiles.hash(archive) == digest(bytes))
    }

    @Test func installRejectsWrongSizeWithoutWritingCompletionMarker() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let expected = Data("right".utf8)
        let archive = root.appendingPathComponent("wrong-size.tar.xz")
        try Data("tiny".utf8).write(to: archive)
        let item = try component(bytes: expected)
        let installationRoot = root.appendingPathComponent("installed", isDirectory: true)
        let marker = DownloadedResourceFiles.directory(item, root: installationRoot)
            .appendingPathComponent(".complete")

        #expect(rejectsInvalidDownload {
            try DownloadedResourceFiles.install(archive, item: item, root: installationRoot)
        })
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(!FileManager.default.fileExists(atPath: installationRoot.path))
    }

    @Test func installRejectsHashMismatchWithoutWritingCompletionMarker() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let expected = Data("right".utf8)
        let archive = root.appendingPathComponent("wrong-hash.tar.xz")
        try Data("wrong".utf8).write(to: archive)
        let item = try component(bytes: expected)
        let installationRoot = root.appendingPathComponent("installed", isDirectory: true)
        let marker = DownloadedResourceFiles.directory(item, root: installationRoot)
            .appendingPathComponent(".complete")

        #expect(rejectsInvalidDownload {
            try DownloadedResourceFiles.install(archive, item: item, root: installationRoot)
        })
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(!FileManager.default.fileExists(atPath: installationRoot.path))
    }

    @Test func validResourceCanBeReusedWithoutReplacingItsCompletedDirectory() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let bytes = Data("verified resource".utf8)
        let archive = root.appendingPathComponent("resource.tar.xz")
        try bytes.write(to: archive)
        let item = try component(bytes: bytes)
        let installationRoot = root.appendingPathComponent("installed", isDirectory: true)

        try DownloadedResourceFiles.install(archive, item: item, root: installationRoot)
        let directory = DownloadedResourceFiles.directory(item, root: installationRoot)
        let installedFile = directory.appendingPathComponent(item.fileName)
        let marker = directory.appendingPathComponent(".complete")
        let sentinel = directory.appendingPathComponent("retain-on-reuse.txt")
        try Data("keep this completed installation".utf8).write(to: sentinel)

        #expect(DownloadedResourceFiles.ready(item, root: installationRoot))
        #expect(try Data(contentsOf: installedFile) == bytes)

        try DownloadedResourceFiles.install(archive, item: item, root: installationRoot)

        #expect(DownloadedResourceFiles.ready(item, root: installationRoot))
        #expect(try String(contentsOf: marker, encoding: .utf8) == item.sha256)
        #expect(try Data(contentsOf: installedFile) == bytes)
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep this completed installation")
    }
}
