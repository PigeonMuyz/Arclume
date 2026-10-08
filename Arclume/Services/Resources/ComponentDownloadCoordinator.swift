import Foundation

/// Downloads independent, pinned components. Runtime activation remains the caller's responsibility.
nonisolated struct ComponentDownloadCoordinator: Sendable {
    struct Snapshot: Sendable, Equatable {
        let downloadedBytes: Int64
        let totalBytes: Int64
        let bytesPerSecond: Double
        let completedCount: Int
        let totalCount: Int
        let activeCount: Int
    }

    typealias Operation = @Sendable (
        DownloadableResourceCatalog.Component, URL, @escaping @Sendable (Int64) -> Void
    ) async throws -> Void

    private let maximumConcurrentDownloads: Int
    private let operation: Operation

    init(maximumConcurrentDownloads: Int = 3, operation: Operation? = nil) {
        self.maximumConcurrentDownloads = min(3, max(1, maximumConcurrentDownloads))
        let downloader = ComponentArchiveDownloader()
        self.operation = operation ?? { item, url, onProgress in
            try await downloader.downloadAndInstall(item: item, url: url, onProgress: onProgress)
        }
    }

    /// Progress callbacks are serialized and may execute off the main actor.
    @concurrent
    func run(
        items: [DownloadableResourceCatalog.Component],
        baseURL: String?,
        onProgress: @escaping @Sendable (Snapshot) -> Void
    ) async throws {
        try Task.checkCancellation()
        let urls = try items.map { try DownloadableResourceCatalog.downloadURL(base: baseURL, component: $0) }
        let progress = ProgressState(items: items, onProgress: onProgress)
        progress.publish()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                var nextIndex = 0
                func enqueue(_ index: Int) {
                    group.addTask {
                        try Task.checkCancellation()
                        progress.start(index)
                        do {
                            try await operation(items[index], urls[index]) { bytes in
                                progress.update(index, bytes: bytes)
                            }
                            try Task.checkCancellation()
                            progress.finish(index, succeeded: true)
                        } catch {
                            progress.finish(index, succeeded: false)
                            throw error
                        }
                    }
                }
                for _ in 0..<min(maximumConcurrentDownloads, items.count) {
                    enqueue(nextIndex)
                    nextIndex += 1
                }
                do {
                    while try await group.next() != nil {
                        try Task.checkCancellation()
                        if nextIndex < items.count {
                            enqueue(nextIndex)
                            nextIndex += 1
                        }
                    }
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            // URLSession errors can include the private component endpoint.
            throw (error as? ResourceDownloadError) ?? ResourceDownloadError.invalidDownload
        }
    }

    /// The lock protects all mutable fields and keeps callback delivery in snapshot order.
    private final class ProgressState: @unchecked Sendable {
        private let lock = NSLock()
        private let sizes: [Int64]
        private var downloaded: [Int64]
        private var active = Set<Int>()
        private var completedCount = 0
        private let started = ContinuousClock.now
        private var lastByteEvent = ContinuousClock.now
        private let onProgress: @Sendable (Snapshot) -> Void

        init(items: [DownloadableResourceCatalog.Component], onProgress: @escaping @Sendable (Snapshot) -> Void) {
            sizes = items.map(\.byteCount)
            downloaded = Array(repeating: 0, count: items.count)
            self.onProgress = onProgress
        }

        func publish() { lock.withLock { emit() } }

        func start(_ index: Int) {
            lock.withLock {
                active.insert(index)
                emit()
            }
        }

        func update(_ index: Int, bytes: Int64) {
            lock.withLock {
                guard active.contains(index) else { return }
                downloaded[index] = max(downloaded[index], min(sizes[index], max(0, bytes)))
                guard lastByteEvent.duration(to: .now) >= .milliseconds(200) else { return }
                emit()
            }
        }

        func finish(_ index: Int, succeeded: Bool) {
            lock.withLock {
                active.remove(index)
                if succeeded {
                    downloaded[index] = sizes[index]
                    completedCount += 1
                }
                emit()
            }
        }

        private func emit() {
            lastByteEvent = .now
            let elapsed = started.duration(to: .now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            let bytes = downloaded.reduce(0, +)
            onProgress(Snapshot(downloadedBytes: bytes, totalBytes: sizes.reduce(0, +),
                bytesPerSecond: seconds > 0 ? Double(bytes) / seconds : 0,
                completedCount: completedCount, totalCount: sizes.count, activeCount: active.count))
        }
    }
}
