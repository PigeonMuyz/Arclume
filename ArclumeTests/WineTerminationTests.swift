import AppKit
import Foundation
import Testing
@testable import Arclume

@MainActor
@Suite(.serialized)
struct WineTerminationTests {
    @Test func exitDrainsAllOwnedProcessesAndKeepsUnrelatedProcess() async throws {
        // Native temporary executables only; never launches Wine or touches a user prefix.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WineTermination-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("wineserver-fixture")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)
        var children: [Process] = []
        defer { for child in children where child.isRunning { child.terminate() } }
        for url in [executable, executable, URL(fileURLWithPath: "/bin/sleep")] {
            let child = Process()
            child.executableURL = url
            child.arguments = ["20"]
            try child.run()
            children.append(child)
        }
        let ticket = try ArclumeWineStopService.launchTicket()
        ArclumeWineStopService.beginApplicationExit()
        defer { ArclumeWineStopService.cancelApplicationExit() }
        try await ArclumeWineStopService.stop(runtimeRoot: root)
        #expect(!children[0].isRunning)
        #expect(!children[1].isRunning)
        #expect(children[2].isRunning)
        // The gate remains shut even after stop() has finished its own drain.
        #expect(ArclumeWineStopService.isStopping)
        #expect(throws: CancellationError.self) { try ArclumeWineStopService.launchTicket() }
        #expect(throws: CancellationError.self) { try ArclumeWineStopService.withLaunchTicket(ticket) {} }
    }

    @Test func waitsForCleanupAndCoalescesRepeatedQuitRequests() async throws {
        var beginCount = 0
        var stopCount = 0
        var finish: CheckedContinuation<Void, Never>?
        var replies: [Bool] = []
        let delegate = ArclumeAppDelegate(beginExit: { beginCount += 1 }, stopWine: {
            stopCount += 1
            await withCheckedContinuation { finish = $0 }
        }, cancelExit: { Issue.record("Unexpected cancellation") }, reportFailure: { _ in
            Issue.record("Unexpected error")
        })
        #expect(delegate.requestTermination { replies.append($0) } == .terminateLater)
        #expect(delegate.requestTermination { replies.append($0) } == .terminateLater)
        #expect(beginCount == 1)
        for _ in 0..<100 where finish == nil { try await Task.sleep(for: .milliseconds(10)) }
        let continuation = try #require(finish)
        #expect(stopCount == 1)
        #expect(replies.isEmpty)
        continuation.resume()
        for _ in 0..<100 where replies.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(replies == [true])
    }

    @Test func failedCleanupCancelsQuitAndAllowsRetry() async throws {
        var attempts = 0
        var cancelled = 0
        var errors = 0
        var replies: [Bool] = []
        let delegate = ArclumeAppDelegate(beginExit: {}, stopWine: {
            attempts += 1
            if attempts == 1 { throw CocoaError(.executableRuntimeMismatch) }
        }, cancelExit: { cancelled += 1 }, reportFailure: { _ in errors += 1 })
        _ = delegate.requestTermination { replies.append($0) }
        for _ in 0..<100 where replies.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(replies == [false])
        #expect(cancelled == 1)
        #expect(errors == 1)
        _ = delegate.requestTermination { replies.append($0) }
        for _ in 0..<100 where replies.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(replies == [false, true])
        #expect(attempts == 2)
    }

    @Test func quitGateInvalidatesPendingLaunchesUntilCancelled() throws {
        let ticket = try ArclumeWineStopService.launchTicket()
        ArclumeWineStopService.beginApplicationExit()
        defer { ArclumeWineStopService.cancelApplicationExit() }
        #expect(ArclumeWineStopService.isStopping)
        #expect(throws: CancellationError.self) { try ArclumeWineStopService.launchTicket() }
        #expect(throws: CancellationError.self) { try ArclumeWineStopService.withLaunchTicket(ticket) {} }
        ArclumeWineStopService.cancelApplicationExit()
        // A cancelled quit must not resurrect queued launches from before it.
        #expect(throws: CancellationError.self) { try ArclumeWineStopService.withLaunchTicket(ticket) {} }
        let newTicket = try ArclumeWineStopService.launchTicket()
        #expect(try ArclumeWineStopService.withLaunchTicket(newTicket) { true })
    }

    @Test func runtimeScopeExcludesOtherWineInstallations() {
        let root = "/tmp/Arclume-Runtime-Fixture"
        #expect(ArclumeWineStopService.belongsToRuntime(root + "/v1/bin/wineserver", root: root))
        #expect(!ArclumeWineStopService.belongsToRuntime(root + "-other/bin/wineserver", root: root))
        #expect(!ArclumeWineStopService.belongsToRuntime("/Applications/CrossOver.app/bin/wineserver", root: root))
    }
}
