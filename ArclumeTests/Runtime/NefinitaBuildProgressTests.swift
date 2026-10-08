import Foundation
import os
import Testing
@testable import Arclume

struct NefinitaBuildProgressTests {
    @Test func watchesNewEventsAfterInitiallyEmptyLogAndStopsOnCancellation() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID().uuidString).log")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let messages = OSAllocatedUnfairLock(initialState: [String]())
        let monitor = NefinitaBuildProgress.monitor(log: file) { message in
            messages.withLock { $0.append(message) }
        }
        defer { monitor.cancel() }
        // Let the observer encounter EOF first; a growing log is not a finished stream.
        try await Task.sleep(for: .milliseconds(100))
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        try writer.write(contentsOf: Data("[12:34:56] downloading https://example.invalid/freetype.tar.xz\n".utf8))
        for _ in 0..<30 {
            if !messages.withLock({ $0.isEmpty }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        monitor.cancel()
        await monitor.value
        #expect(messages.withLock { $0 } == ["下载 FreeType…"])
    }

    @Test func showsDownloadAndBuildStagesWithoutAddresses() {
        #expect(NefinitaBuildProgress.message(for: "[12:34:56] downloading https://example.invalid/private/freetype-2.13.3.tar.xz?token=secret") == "下载 FreeType…")
        #expect(NefinitaBuildProgress.message(for: "[12:34:56] building Wine 11 with 4 jobs (this takes a while)") == "编译 Wine…")
        #expect(NefinitaBuildProgress.message(for: "[12:34:56] creating archive: /Users/private/dist/archive.tar.xz") == "打包 Nefinita 运行时…")
    }

    @Test func ignoresUnrecognizedOutputAndKeepsUnknownDependenciesGeneric() {
        #expect(NefinitaBuildProgress.message(for: "clang -I/Users/private compiling.c") == nil)
        #expect(NefinitaBuildProgress.message(for: "[12:34:56] manifest: /Users/private/runtime.json") == nil)
        #expect(NefinitaBuildProgress.message(for: "[12:34:56] downloading https://example.invalid/unknown.tar.xz") == "下载 依赖组件…")
    }
}
