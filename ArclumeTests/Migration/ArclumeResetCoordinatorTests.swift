import Foundation
import Testing
@testable import Arclume

@MainActor
@Suite(.serialized)
struct ArclumeResetCoordinatorTests {
    private func waitUntilSettled(_ coordinator: ArclumeResetCoordinator) async throws {
        for _ in 0..<100 where coordinator.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!coordinator.isRunning)
    }

    @Test func resetWaitsForTrashNoticeAcknowledgementBeforeQuit() async throws {
        var events: [String] = []
        let trash = URL(fileURLWithPath: "/tmp/reset-fixture-trash/Arclume")
        let coordinator = ArclumeResetCoordinator(check: { events.append("check") },
            beginExit: { events.append("gate") }, stop: { events.append("stop") }, reset: { progress in
                events.append("move")
                progress(.moving, nil)
                progress(.clearing, trash)
                events.append("clear")
                return trash
            }, finish: { events.append("acknowledge") })
        coordinator.start()
        #expect(coordinator.blocksQuit)
        #expect(!coordinator.acknowledgeExit())
        try await waitUntilSettled(coordinator)
        #expect(coordinator.phase == .completed)
        #expect(coordinator.trashURL == trash)
        #expect(events == ["check", "gate", "stop", "check", "move", "clear"])
        #expect(coordinator.blocksQuit)
        #expect(coordinator.acknowledgeExit())
        #expect(events.last == "acknowledge")
        #expect(!coordinator.blocksQuit)
    }

    @Test func preflightFailureNeverStopsOrMovesData() async throws {
        let coordinator = ArclumeResetCoordinator(check: { throw CocoaError(.fileWriteNoPermission) },
            beginExit: { Issue.record("Gate must not close") }, stop: { Issue.record("Wine must not stop") },
            reset: { _ in Issue.record("Data must not move"); return nil })
        coordinator.start()
        try await waitUntilSettled(coordinator)
        #expect(coordinator.phase == .failed)
        #expect(coordinator.error != nil)
        #expect(coordinator.trashURL == nil)
    }

    @Test func repeatedRequestsCoalesceAndStopFailureCanRetry() async throws {
        var attempts = 0
        var resets = 0
        let coordinator = ArclumeResetCoordinator(check: {}, beginExit: {}, stop: {
            attempts += 1
            if attempts == 1 { throw CocoaError(.executableRuntimeMismatch) }
        }, reset: { _ in resets += 1; return nil })
        coordinator.start()
        coordinator.start()
        try await waitUntilSettled(coordinator)
        #expect(attempts == 1)
        #expect(resets == 0)
        #expect(coordinator.phase == .failed)
        coordinator.start()
        try await waitUntilSettled(coordinator)
        #expect(coordinator.phase == .completed)
        #expect(resets == 1)
    }

    @Test func activityStartingDuringDrainPreventsMove() async throws {
        var checks = 0
        let coordinator = ArclumeResetCoordinator(check: {
            checks += 1
            if checks == 2 { throw CocoaError(.fileWriteUnknown) }
        }, beginExit: {}, stop: {}, reset: { _ in Issue.record("Writer is active"); return nil })
        coordinator.start()
        try await waitUntilSettled(coordinator)
        #expect(coordinator.phase == .failed)
        #expect(coordinator.trashURL == nil)
    }

    @Test func partialFailureAndRetryKeepActualTrashDestination() async throws {
        var attempts = 0
        let trash = URL(fileURLWithPath: "/tmp/reset-fixture-trash/Arclume")
        let coordinator = ArclumeResetCoordinator(check: {}, beginExit: {}, stop: {}, reset: { progress in
            attempts += 1
            if attempts == 1 {
                progress(.clearing, trash)
                throw CocoaError(.fileWriteUnknown)
            }
            return nil
        })
        coordinator.start()
        try await waitUntilSettled(coordinator)
        #expect(coordinator.phase == .failed)
        #expect(coordinator.trashURL == trash)
        coordinator.start()
        try await waitUntilSettled(coordinator)
        #expect(coordinator.phase == .completed)
        #expect(coordinator.trashURL == trash)
    }

    @Test func acknowledgementFailureDoesNotAllowQuit() async throws {
        let coordinator = ArclumeResetCoordinator(check: {}, beginExit: {}, stop: {}, reset: { _ in nil },
            finish: { throw CocoaError(.fileWriteUnknown) })
        coordinator.start()
        try await waitUntilSettled(coordinator)
        #expect(!coordinator.acknowledgeExit())
        #expect(coordinator.blocksQuit)
        #expect(coordinator.phase == .failed)
    }

    @Test func unrelatedWinePrefixDoesNotBlockManagedData() {
        let root = "/tmp/reset-fixture/Arclume"
        #expect(ArclumeWineStopService.usesManagedData(prefix: root + "/ALBottles", root: root))
        #expect(ArclumeWineStopService.usesManagedData(prefix: root + "/Containers/test", root: root))
        #expect(!ArclumeWineStopService.usesManagedData(prefix: root + "-other/Bottle", root: root))
        #expect(!ArclumeWineStopService.usesManagedData(prefix: "/tmp/CrossOver/Bottle", root: root))
    }

    @Test func viewLocalInstallerActivityBlocksResetUntilBothPhasesFinish() {
        let installer = WindowsInstallerStore()
        installer.busy = true
        installer.preparing = true
        #expect(ArclumeResetCoordinator.hasActiveActivities)
        installer.busy = false
        #expect(ArclumeResetCoordinator.hasActiveActivities)
        installer.preparing = false
        #expect(!ArclumeResetCoordinator.hasActiveActivities)
    }

    @Test func independentBackgroundActivitiesMustAllFinish() {
        let first = ArclumeResetCoordinator.beginActivity()
        let second = ArclumeResetCoordinator.beginActivity()
        ArclumeResetCoordinator.endActivity(first)
        #expect(ArclumeResetCoordinator.hasActiveActivities)
        ArclumeResetCoordinator.endActivity(second)
        #expect(!ArclumeResetCoordinator.hasActiveActivities)
    }
}
