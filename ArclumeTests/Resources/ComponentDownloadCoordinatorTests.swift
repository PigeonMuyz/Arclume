import CryptoKit
import Foundation
import Testing
@testable import Arclume

nonisolated struct ComponentDownloadCoordinatorTests {
    private func component(_ index: Int, bytes: Data = Data(repeating: 1, count: 100)) -> DownloadableResourceCatalog.Component {
        DownloadableResourceCatalog.Component(type: "test", name: "component-\(index)", id: "component-\(index)",
            version: "1", fileName: "component-\(index).bin",
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), unpack: false)
    }

    @Test func boundsParallelWorkAndAggregatesBytesInsteadOfComponentFractions() async throws {
        let items = (0..<8).map { component($0, bytes: Data(repeating: 1, count: ($0 + 1) * 100)) }
        let probe = OperationProbe()
        let snapshots = SnapshotRecorder()
        let coordinator = ComponentDownloadCoordinator(maximumConcurrentDownloads: 99) { item, _, progress in
            await probe.started()
            progress(item.byteCount / 2)
            // A later, smaller transport callback must not move aggregate progress backwards.
            progress(1)
            await probe.waitForRelease()
            progress(item.byteCount)
            await probe.finished()
        }
        let task = Task {
            try await coordinator.run(items: items, baseURL: "https://example.invalid", onProgress: snapshots.record)
        }
        await probe.waitForStarts(3)
        #expect(await probe.startedCount == 3)
        #expect(await probe.peakActive == 3)
        await probe.release()
        try await task.value

        let recorded = snapshots.values
        let last = try #require(recorded.last)
        #expect(last.downloadedBytes == 3_600)
        #expect(last.totalBytes == 3_600)
        #expect(last.completedCount == 8)
        #expect(last.totalCount == 8)
        #expect(last.activeCount == 0)
        #expect(recorded.allSatisfy { $0.activeCount <= 3 && $0.bytesPerSecond.isFinite && $0.bytesPerSecond >= 0 })
        #expect(zip(recorded, recorded.dropFirst()).allSatisfy { $0.downloadedBytes <= $1.downloadedBytes })
        #expect(await probe.peakActive == 3)
    }

    @Test func byteEventsAreThrottledButCompletionAlwaysPublishes() async throws {
        let snapshots = SnapshotRecorder()
        let coordinator = ComponentDownloadCoordinator { _, _, progress in
            for _ in 0..<1_000 { progress(50) }
            #expect(snapshots.values.count == 2) // Initial snapshot and forced start.
            try await Task.sleep(for: .milliseconds(220))
            progress(90)
            #expect(snapshots.values.last?.downloadedBytes == 90)
        }
        try await coordinator.run(items: [component(0)], baseURL: "https://example.invalid", onProgress: snapshots.record)
        #expect(snapshots.values.last?.completedCount == 1)
        #expect(snapshots.values.last?.downloadedBytes == 100)
        #expect(snapshots.values.count == 4)
    }

    @Test func cancellationStopsActiveWorkWithoutStartingQueuedComponents() async throws {
        let probe = OperationProbe()
        let snapshots = SnapshotRecorder()
        let coordinator = ComponentDownloadCoordinator { _, _, progress in
            await probe.started()
            progress(10)
            do {
                try await Task.sleep(for: .seconds(3_600))
            } catch {
                await probe.cancelled()
                throw error
            }
        }
        let task = Task {
            try await coordinator.run(items: (0..<8).map { component($0) },
                baseURL: "https://example.invalid", onProgress: snapshots.record)
        }
        await probe.waitForStarts(3)
        task.cancel()
        do {
            try await task.value
            Issue.record("Cancelled downloads unexpectedly completed")
        } catch is CancellationError {
            // Caller can distinguish cancellation from a transport failure.
        }
        #expect(await probe.startedCount == 3)
        #expect(await probe.cancelledCount == 3)
        #expect(snapshots.values.last?.activeCount == 0)
        #expect(snapshots.values.last?.completedCount == 0)
    }

    @Test func failureIsSanitizedAndRetainsAlreadyInstalledComponents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComponentDownloadCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("isolated component".utf8)
        let items = (0..<3).map { component($0, bytes: bytes) }
        let snapshots = SnapshotRecorder()
        let probe = OperationProbe()
        let coordinator = ComponentDownloadCoordinator(maximumConcurrentDownloads: 1) { item, url, progress in
            await probe.started()
            if item.id == "component-1" {
                throw NSError(domain: NSURLErrorDomain, code: -1_001,
                    userInfo: [NSLocalizedDescriptionKey: "Private endpoint: \(url.absoluteString)"])
            }
            let temporary = directory.appendingPathComponent(item.fileName)
            try bytes.write(to: temporary)
            defer { try? FileManager.default.removeItem(at: temporary) }
            progress(item.byteCount)
            try DownloadedResourceFiles.install(temporary, item: item, root: directory.appendingPathComponent("installed"))
        }
        do {
            try await coordinator.run(items: items, baseURL: "https://example.invalid", onProgress: snapshots.record)
            Issue.record("Failed download unexpectedly completed")
        } catch let error as ResourceDownloadError {
            guard case .invalidDownload = error else {
                Issue.record("Unexpected download error")
                return
            }
            #expect(!error.localizedDescription.contains("example.invalid"))
        }
        #expect(await probe.startedCount == 2)
        #expect(DownloadedResourceFiles.ready(items[0], root: directory.appendingPathComponent("installed")))
        #expect(snapshots.values.last?.completedCount == 1)
        #expect(snapshots.values.last?.activeCount == 0)
    }

    @Test func failedComponentCancelsOtherTransfersAndLeavesQueueUnstarted() async throws {
        let probe = OperationProbe()
        let snapshots = SnapshotRecorder()
        let coordinator = ComponentDownloadCoordinator { item, _, _ in
            await probe.started()
            if item.id == "component-0" {
                await probe.waitForStarts(3)
                throw ResourceDownloadError.invalidDownload
            }
            do {
                try await Task.sleep(for: .seconds(3_600))
            } catch {
                await probe.cancelled()
                throw error
            }
        }
        do {
            try await coordinator.run(items: (0..<8).map { component($0) },
                baseURL: "https://example.invalid", onProgress: snapshots.record)
            Issue.record("Failed batch unexpectedly completed")
        } catch let error as ResourceDownloadError {
            guard case .invalidDownload = error else {
                Issue.record("Unexpected download error")
                return
            }
        }
        #expect(await probe.startedCount == 3)
        #expect(await probe.cancelledCount == 2)
        #expect(snapshots.values.last?.activeCount == 0)
    }

    @Test func emptyBatchNeedsNoEndpointAndPublishesZeroSnapshot() async throws {
        let snapshots = SnapshotRecorder()
        let coordinator = ComponentDownloadCoordinator { _, _, _ in
            Issue.record("Empty batch performed a download")
        }
        try await coordinator.run(items: [], baseURL: nil, onProgress: snapshots.record)
        #expect(snapshots.values == [.init(downloadedBytes: 0, totalBytes: 0, bytesPerSecond: 0,
            completedCount: 0, totalCount: 0, activeCount: 0)])
    }

    private final class SnapshotRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var snapshots: [ComponentDownloadCoordinator.Snapshot] = []
        var values: [ComponentDownloadCoordinator.Snapshot] { lock.withLock { snapshots } }
        func record(_ snapshot: ComponentDownloadCoordinator.Snapshot) { lock.withLock { snapshots.append(snapshot) } }
    }

    private actor OperationProbe {
        private(set) var startedCount = 0
        private(set) var cancelledCount = 0
        private(set) var peakActive = 0
        private var active = 0
        private var released = false
        private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

        func started() {
            startedCount += 1
            active += 1
            peakActive = max(peakActive, active)
            let ready = startWaiters.filter { $0.0 <= startedCount }
            startWaiters.removeAll { $0.0 <= startedCount }
            for (_, waiter) in ready { waiter.resume() }
        }
        func finished() { active -= 1 }
        func cancelled() { cancelledCount += 1; active -= 1 }
        func waitForStarts(_ count: Int) async {
            if startedCount >= count { return }
            await withCheckedContinuation { startWaiters.append((count, $0)) }
        }
        func waitForRelease() async {
            if released { return }
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        func release() {
            released = true
            for waiter in releaseWaiters { waiter.resume() }
            releaseWaiters.removeAll()
        }
    }
}
