import Foundation

/// A shared network budget covers component downloads and their individual ranges.
nonisolated struct ComponentArchiveDownloader: Sendable {
    typealias Transfer = @Sendable (URLRequest, Int64, @escaping @Sendable (Int64) -> Void) async throws -> (URL, HTTPURLResponse)
    private let slots = NetworkSlots(limit: 3)
    private let transfer: Transfer
    private let rangeThreshold: Int64

    init(rangeThreshold: Int64 = 24 * 1_024 * 1_024, transfer: Transfer? = nil) {
        self.rangeThreshold = max(3, rangeThreshold)
        self.transfer = transfer ?? { request, maximum, progress in
            try await Self.transferToDisk(request: request, maximumBytes: maximum, progress: progress)
        }
    }

    @concurrent
    func downloadAndInstall(item: DownloadableResourceCatalog.Component, url: URL,
                            onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Arclume-Component-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent(item.fileName)
        try await downloadArchive(item: item, url: url, destination: archive, onProgress: onProgress)
        try Task.checkCancellation()
        try DownloadedResourceFiles.install(archive, item: item)
    }

    /// Internal seam for tests: all output must be in the caller's isolated fixture.
    @concurrent
    func downloadArchive(item: DownloadableResourceCatalog.Component, url: URL, destination: URL,
                         onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        try Task.checkCancellation()
        let workspace = destination.deletingLastPathComponent()
            .appendingPathComponent(".parts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let metadata = item.byteCount >= rangeThreshold ? try await rangeMetadata(url: url, size: item.byteCount) : nil
        if let metadata {
            let ranges = Self.ranges(size: item.byteCount)
            let progress = RangeProgress(sizes: ranges.map { $0.upperBound - $0.lowerBound + 1 }, callback: onProgress)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, range) in ranges.enumerated() {
                    group.addTask {
                        var request = Self.request(url)
                        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
                        if let validator = metadata.validator { request.setValue(validator, forHTTPHeaderField: "If-Range") }
                        let rangeRequest = request
                        let size = range.upperBound - range.lowerBound + 1
                        let (temporary, response) = try await slots.perform {
                            try await transfer(rangeRequest, size) { progress.update(index, bytes: $0) }
                        }
                        defer { try? FileManager.default.removeItem(at: temporary) }
                        try Task.checkCancellation()
                        guard response.statusCode == 206, response.url?.scheme == "https",
                              response.value(forHTTPHeaderField: "Content-Range") == "bytes \(range.lowerBound)-\(range.upperBound)/\(item.byteCount)",
                              try Self.fileSize(temporary) == size else { throw ResourceDownloadError.invalidDownload }
                        try FileManager.default.moveItem(at: temporary, to: workspace.appendingPathComponent("\(index).part"))
                        progress.update(index, bytes: size)
                    }
                }
                do { while try await group.next() != nil {} }
                catch { group.cancelAll(); throw error }
            }
            let assembled = workspace.appendingPathComponent(item.fileName)
            try Self.assemble(ranges.indices.map { workspace.appendingPathComponent("\($0).part") }, into: assembled)
            guard try Self.fileSize(assembled) == item.byteCount else { throw ResourceDownloadError.invalidDownload }
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: assembled, to: destination)
        } else {
            let (temporary, response) = try await slots.perform {
                try await transfer(Self.request(url), item.byteCount, onProgress)
            }
            defer { try? FileManager.default.removeItem(at: temporary) }
            try Task.checkCancellation()
            guard response.statusCode == 200, response.url?.scheme == "https",
                  try Self.fileSize(temporary) == item.byteCount else { throw ResourceDownloadError.invalidDownload }
            try FileManager.default.moveItem(at: temporary, to: destination)
            onProgress(item.byteCount)
        }
    }

    private struct Metadata: Sendable { let validator: String? }

    private func rangeMetadata(url: URL, size: Int64) async throws -> Metadata? {
        var request = Self.request(url)
        request.httpMethod = "HEAD"
        let headRequest = request
        do {
            let (temporary, response) = try await slots.perform { try await transfer(headRequest, size) { _ in } }
            defer { try? FileManager.default.removeItem(at: temporary) }
            try Task.checkCancellation()
            guard response.statusCode == 200, response.url?.scheme == "https",
                  response.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes",
                  response.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init) == size else { return nil }
            let etag = response.value(forHTTPHeaderField: "ETag")
            let validator = etag.flatMap { $0.hasPrefix("W/") ? nil : $0 }
                ?? response.value(forHTTPHeaderField: "Last-Modified")
            return Metadata(validator: validator)
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            return nil // HEAD is optional; a regular GET still verifies the pinned payload.
        }
    }

    private static func ranges(size: Int64) -> [ClosedRange<Int64>] {
        (0..<3).map { index in
            let lower = size * Int64(index) / 3
            let upper = size * Int64(index + 1) / 3 - 1
            return lower...upper
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        guard let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw ResourceDownloadError.invalidDownload }
        return Int64(bytes)
    }

    private static func assemble(_ parts: [URL], into destination: URL) throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw ResourceDownloadError.invalidDownload }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        for part in parts {
            let input = try FileHandle(forReadingFrom: part)
            defer { try? input.close() }
            while true {
                try Task.checkCancellation()
                guard let data = try input.read(upToCount: 1_024 * 1_024), !data.isEmpty else { break }
                try output.write(contentsOf: data)
            }
        }
    }

    @concurrent
    static func transferToDisk(request: URLRequest, maximumBytes: Int64,
                               progress: @escaping @Sendable (Int64) -> Void,
                               configuration: URLSessionConfiguration = .ephemeral) async throws -> (URL, HTTPURLResponse) {
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3_600
        let delegate = DownloadDelegate(maximumBytes: maximumBytes, progress: progress)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // Foundation's async download wrapper does not deliver didWriteData on the
        // supported macOS runtime. A delegate-owned task keeps byte progress live.
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>) in
                delegate.start(session: session, request: request, continuation: continuation)
            }
        } onCancel: {
            delegate.cancel()
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        typealias Output = (URL, HTTPURLResponse)
        let maximumBytes: Int64
        let progress: @Sendable (Int64) -> Void
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Output, Error>?
        private var task: URLSessionDownloadTask?
        private var cancelled = false
        private var completed = false
        private var ownedFile: URL?
        private var downloadResult: Result<Output, Error>?

        init(maximumBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) {
            self.maximumBytes = maximumBytes; self.progress = progress
        }

        func start(session: URLSession, request: URLRequest, continuation: CheckedContinuation<Output, Error>) {
            lock.withLock {
                guard !cancelled else {
                    completed = true
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let task = session.downloadTask(with: request)
                self.task = task
                task.resume()
            }
        }

        func cancel() {
            let task = lock.withLock {
                cancelled = true
                return self.task
            }
            task?.cancel()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesWritten <= maximumBytes, totalBytesExpectedToWrite <= maximumBytes else {
                downloadTask.cancel(); return
            }
            progress(totalBytesWritten)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            lock.withLock {
                guard !completed, !cancelled else { return }
                guard let response = downloadTask.response as? HTTPURLResponse else {
                    downloadResult = .failure(ResourceDownloadError.invalidDownload)
                    return
                }
                // URLSession removes its temporary URL when this callback returns.
                // Only the receiving operation owns this random file after success.
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Arclume-Transfer-\(UUID().uuidString).tmp")
                ownedFile = destination
                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                    downloadResult = .success((destination, response))
                } catch {
                    downloadResult = .failure(error)
                }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.withLock {
                guard !completed, let continuation else { return }
                completed = true
                let result: Result<Output, Error>
                if cancelled { result = .failure(CancellationError()) }
                else if let error { result = .failure(error) }
                else { result = downloadResult ?? .failure(ResourceDownloadError.invalidDownload) }
                if case .failure = result, let ownedFile { try? FileManager.default.removeItem(at: ownedFile) }
                ownedFile = nil
                downloadResult = nil
                self.continuation = nil
                self.task = nil
                continuation.resume(with: result)
            }
        }
    }

    private final class RangeProgress: @unchecked Sendable {
        private let lock = NSLock()
        private let sizes: [Int64]
        private var received: [Int64]
        private let callback: @Sendable (Int64) -> Void
        init(sizes: [Int64], callback: @escaping @Sendable (Int64) -> Void) {
            self.sizes = sizes; received = Array(repeating: 0, count: sizes.count); self.callback = callback
        }
        func update(_ index: Int, bytes: Int64) {
            lock.withLock {
                received[index] = max(received[index], min(sizes[index], max(0, bytes)))
                callback(received.reduce(0, +))
            }
        }
    }

    private actor NetworkSlots {
        private let limit: Int
        private var active = 0
        private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
        init(limit: Int) { self.limit = limit }

        func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
            try await acquire()
            defer { release() }
            try Task.checkCancellation()
            return try await operation()
        }
        private func acquire() async throws {
            try Task.checkCancellation()
            if active < limit { active += 1; return }
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                    else { waiters.append((id, continuation)) }
                }
            } onCancel: {
                Task { await self.cancel(id) }
            }
        }
        private func cancel(_ id: UUID) {
            guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
            waiters.remove(at: index).1.resume(throwing: CancellationError())
        }
        private func release() {
            if waiters.isEmpty { active -= 1 }
            else { waiters.removeFirst().1.resume() }
        }
    }
}
