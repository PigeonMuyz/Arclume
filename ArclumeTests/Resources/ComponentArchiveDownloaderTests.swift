import CryptoKit
import Foundation
import Network
import Testing
@testable import Arclume

nonisolated struct ComponentArchiveDownloaderTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ComponentArchiveDownloaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func component(_ bytes: Data) -> DownloadableResourceCatalog.Component {
        .init(type: "test", name: "test", id: "test", version: "1", fileName: "test.bin",
              sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(bytes.count), unpack: false)
    }

    @Test func rangesReassembleExactlyAndUseSharedThreeRequestLimit() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data((0..<97).map(UInt8.init))
        let fake = Transport(root: root, bytes: bytes)
        let downloader = ComponentArchiveDownloader(rangeThreshold: 3, transfer: fake.transfer)
        let item = component(bytes)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<3 {
                group.addTask {
                    try await downloader.downloadArchive(item: item, url: URL(string: "https://example.invalid/\(index)")!,
                        destination: root.appendingPathComponent("\(index).bin"), onProgress: { _ in })
                }
            }
            try await group.waitForAll()
        }
        for index in 0..<3 { #expect(try Data(contentsOf: root.appendingPathComponent("\(index).bin")) == bytes) }
        #expect(await fake.peakActive == 3)
        let requests = await fake.requests
        #expect(requests.filter { $0.httpMethod == "HEAD" }.count == 3)
        #expect(requests.filter { $0.value(forHTTPHeaderField: "Range") != nil }.count == 9)
        #expect(requests.filter { $0.httpMethod != "HEAD" }.allSatisfy { $0.value(forHTTPHeaderField: "If-Range") == "\"fixture-v1\"" })
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 3)
    }

    @Test(arguments: [Transport.Mode.unsupported, .wrongHeadLength])
    func headMustExplicitlyConfirmRangeSupportAndExactLength(mode: Transport.Mode) async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 8, count: 97)
        let fake = Transport(root: root, bytes: bytes, mode: mode)
        let downloader = ComponentArchiveDownloader(rangeThreshold: 3, transfer: fake.transfer)
        let destination = root.appendingPathComponent("archive.bin")
        try await downloader.downloadArchive(item: component(bytes), url: URL(string: "https://example.invalid/archive")!,
            destination: destination, onProgress: { _ in })
        #expect(try Data(contentsOf: destination) == bytes)
        #expect(await fake.requests.count == 2)
        #expect(await fake.requests.allSatisfy { $0.value(forHTTPHeaderField: "Range") == nil })
    }

    @Test(arguments: [Transport.Mode.ignoredRange, .wrongRange, .truncated])
    func invalidRangeResponsesAreNeverAssembledAndAllPartialFilesAreRemoved(mode: Transport.Mode) async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 8, count: 97)
        let fake = Transport(root: root, bytes: bytes, mode: mode)
        let downloader = ComponentArchiveDownloader(rangeThreshold: 3, transfer: fake.transfer)
        do {
            try await downloader.downloadArchive(item: component(bytes), url: URL(string: "https://example.invalid/archive")!,
                destination: root.appendingPathComponent("archive.bin"), onProgress: { _ in })
            Issue.record("Invalid range response unexpectedly assembled")
        } catch let error as ResourceDownloadError {
            guard case .invalidDownload = error else { Issue.record("Unexpected download error"); return }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func smallFilesSkipHeadAndUseOneStreamingRequest() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 8, count: 97)
        let fake = Transport(root: root, bytes: bytes)
        let downloader = ComponentArchiveDownloader(transfer: fake.transfer)
        try await downloader.downloadArchive(item: component(bytes), url: URL(string: "https://example.invalid/archive")!,
            destination: root.appendingPathComponent("archive.bin"), onProgress: { _ in })
        #expect(await fake.requests.count == 1)
        #expect(await fake.requests.first?.httpMethod == "GET")
    }

    @Test func cancellationDrainsActiveAndQueuedRangeRequestsAndRemovesParts() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 8, count: 97)
        let fake = Transport(root: root, bytes: bytes, mode: .slowRanges)
        let downloader = ComponentArchiveDownloader(rangeThreshold: 3, transfer: fake.transfer)
        let item = component(bytes)
        let task = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<3 {
                    group.addTask {
                        try await downloader.downloadArchive(item: item, url: URL(string: "https://example.invalid/\(index)")!,
                            destination: root.appendingPathComponent("\(index).bin"), onProgress: { _ in })
                    }
                }
                try await group.waitForAll()
            }
        }
        await fake.waitForRequests(6) // Three HEAD requests followed by three active ranges.
        task.cancel()
        do { try await task.value; Issue.record("Cancelled ranges unexpectedly completed") }
        catch is CancellationError {}
        #expect(await fake.requests.count == 6)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func urlSessionDownloadActuallyDeliversByteProgress() async throws {
        let server = try LoopbackDownloadServer()
        let url = try await server.start()
        defer { server.stop() }
        let progress = ByteRecorder()
        let (file, response) = try await ComponentArchiveDownloader.transferToDisk(
            request: URLRequest(url: url), maximumBytes: 1_048_576, progress: progress.record)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(response.statusCode == 200)
        #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == 1_048_576)
        #expect(progress.maximum > 0)
    }

    @Test func urlSessionHeadReadsHeadersWithoutDownloadingPayload() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingFixtureProtocol.self]
        var request = URLRequest(url: URL(string: "https://component-stream.example.invalid/archive")!)
        request.httpMethod = "HEAD"
        let (file, response) = try await ComponentArchiveDownloader.transferToDisk(
            request: request, maximumBytes: 262_144, progress: { _ in }, configuration: configuration)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(response.value(forHTTPHeaderField: "Content-Length") == "262144")
        #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == 0)
    }

    @Test func realDownloadCancellationCancelsTheDelegateTask() async throws {
        let server = try LoopbackDownloadServer()
        let url = try await server.start()
        defer { server.stop() }
        let (events, continuation) = AsyncStream<Int64>.makeStream()
        let task = Task {
            defer { continuation.finish() }
            let result = try await ComponentArchiveDownloader.transferToDisk(
                request: URLRequest(url: url), maximumBytes: 1_048_576,
                progress: { continuation.yield($0) })
            try? FileManager.default.removeItem(at: result.0)
        }
        for await bytes in events where bytes > 0 { task.cancel(); break }
        do { try await task.value; Issue.record("Cancelled transport unexpectedly completed") }
        catch is CancellationError {}
    }

    @Test func cancellationBeforeTaskCreationDoesNotLoseTheContinuation() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let result = try await ComponentArchiveDownloader.transferToDisk(
                request: URLRequest(url: URL(string: "https://never-requested.example.invalid/archive")!),
                maximumBytes: 100, progress: { _ in })
            try? FileManager.default.removeItem(at: result.0)
        }
        do { try await task.value; Issue.record("Pre-cancelled transport unexpectedly completed") }
        catch is CancellationError {}
    }

    private final class ByteRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var received: Int64 = 0
        var maximum: Int64 { lock.withLock { received } }
        func record(_ bytes: Int64) { lock.withLock { received = max(received, bytes) } }
    }

    /// Real URLSession transport, isolated to IPv4 loopback and an OS-assigned port.
    private final class LoopbackDownloadServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "ArclumeTests.component-download-loopback")
        private let lock = NSLock()
        private var connections: [NWConnection] = []

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }

        func start() async throws -> URL {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.listener.stateUpdateHandler = nil
                        guard let port = self.listener.port,
                              let url = URL(string: "http://127.0.0.1:\(port.rawValue)/component") else {
                            continuation.resume(throwing: URLError(.badURL)); return
                        }
                        continuation.resume(returning: url)
                    case .failed(let error):
                        self.listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    self.lock.withLock { self.connections.append(connection) }
                    connection.start(queue: self.queue)
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] _, _, _, error in
                        guard let self, error == nil else { connection.cancel(); return }
                        let header = Data("HTTP/1.1 200 OK\r\nContent-Length: 1048576\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n".utf8)
                        connection.send(content: header, completion: .contentProcessed { [weak self] error in
                            guard error == nil else { connection.cancel(); return }
                            self?.sendChunk(0, connection: connection)
                        })
                    }
                }
                listener.start(queue: queue)
            }
        }

        private func sendChunk(_ index: Int, connection: NWConnection) {
            guard index < 16 else { connection.cancel(); return }
            queue.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in
                connection.send(content: Data(repeating: 42, count: 65_536), completion: .contentProcessed { [weak self] error in
                    guard error == nil else { connection.cancel(); return }
                    self?.sendChunk(index + 1, connection: connection)
                })
            }
        }

        func stop() {
            listener.cancel()
            lock.withLock {
                for connection in connections { connection.cancel() }
                connections.removeAll()
            }
        }
    }

    private final class StreamingFixtureProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "component-stream.example.invalid" }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "262144", "Content-Type": "application/octet-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if request.httpMethod != "HEAD" {
                for _ in 0..<4 { client?.urlProtocol(self, didLoad: Data(repeating: 42, count: 65_536)) }
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    actor Transport {
        enum Mode: Sendable { case supported, unsupported, wrongHeadLength, ignoredRange, wrongRange, truncated, slowRanges }
        let root: URL
        let bytes: Data
        let mode: Mode
        private var active = 0
        private(set) var peakActive = 0
        private(set) var requests: [URLRequest] = []
        private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
        init(root: URL, bytes: Data, mode: Mode = .supported) { self.root = root; self.bytes = bytes; self.mode = mode }

        func transfer(_ request: URLRequest, _ maximum: Int64,
                      _ progress: @escaping @Sendable (Int64) -> Void) async throws -> (URL, HTTPURLResponse) {
            active += 1
            peakActive = max(peakActive, active)
            requests.append(request)
            let ready = waiters.filter { $0.0 <= requests.count }
            waiters.removeAll { $0.0 <= requests.count }
            for (_, waiter) in ready { waiter.resume() }
            defer { active -= 1 }
            try await Task.sleep(for: mode == .slowRanges && request.httpMethod != "HEAD" ? .seconds(3_600) : .milliseconds(20))
            var status = 200
            var headers = ["Content-Length": String(bytes.count), "Accept-Ranges": "bytes", "ETag": "\"fixture-v1\""]
            var body = bytes
            if request.httpMethod == "HEAD" {
                body = Data()
                if mode == .unsupported { headers["Accept-Ranges"] = "none" }
                if mode == .wrongHeadLength { headers["Content-Length"] = "98" }
            } else if let range = request.value(forHTTPHeaderField: "Range") {
                let pair = range.dropFirst("bytes=".count).split(separator: "-").compactMap { Int($0) }
                let lower = pair[0], upper = pair[1]
                status = mode == .ignoredRange ? 200 : 206
                headers["Content-Range"] = mode == .wrongRange ? "bytes 0-0/97" : "bytes \(lower)-\(upper)/\(bytes.count)"
                body = bytes.subdata(in: lower..<(upper + 1))
                if mode == .truncated { body.removeLast() }
            }
            let file = root.appendingPathComponent("transfer-\(UUID().uuidString)")
            try body.write(to: file)
            if request.httpMethod != "HEAD" { progress(Int64(body.count)) }
            return (file, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        }

        func waitForRequests(_ count: Int) async {
            if requests.count >= count { return }
            await withCheckedContinuation { waiters.append((count, $0)) }
        }
    }
}
