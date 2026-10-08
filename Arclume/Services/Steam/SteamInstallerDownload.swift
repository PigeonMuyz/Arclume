import Foundation

/// Only downloads the installer. Installation remains interactive, including
/// Valve's license agreement and the user's choice of installation directory.
nonisolated final class SteamInstallerDownload: NSObject, URLSessionDownloadDelegate {
    let progress: @Sendable (Double?) -> Void
    static let maximumSize: Int64 = 100 * 1024 * 1024

    init(progress: @escaping @Sendable (Double?) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= Self.maximumSize,
              totalBytesExpectedToWrite <= Self.maximumSize else {
            downloadTask.cancel()
            return
        }
        progress(totalBytesExpectedToWrite > 0
            ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1)
            : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}

    static func download(
        status: @escaping @Sendable (String) -> Void = { _ in },
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        // Steam controls the routing behind this vendor-neutral official
        // hostname. Do not pin Fastly/Akamai or reuse GitHub update mirrors.
        let url = URL(string: "https://cdn.steamstatic.com/client/installer/SteamSetup.exe")!
        var lastError: Error = URLError(.cannotConnectToHost)
        for attempt in 1...2 {
            try Task.checkCancellation()
            if attempt > 1 {
                try await Task.sleep(for: .seconds(1))
            }
            progress(nil)
            status(attempt == 1
                ? "正在从 Steam 官方下载安装包…"
                : "正在重试 Steam 官方下载（2/2）…")
            do {
                return try await download(from: url, progress: progress)
            } catch {
                try Task.checkCancellation()
                // A local disk/permission failure should not trigger more downloads.
                guard error is URLError else { throw error }
                lastError = error
            }
        }
        throw NSError(domain: "Arclume.SteamDownload", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Steam 官方下载失败，已重试。\(failureDescription(lastError)) 可点击“安装 Steam”重试，或从更多菜单选择本地安装包。"
        ])
    }

    static func failureDescription(_ error: Error) -> String {
        guard let error = error as? URLError else { return error.localizedDescription }
        switch error.code {
        case .timedOut: return "连接或下载超时。"
        case .notConnectedToInternet: return "当前未连接互联网。"
        case .cannotFindHost, .dnsLookupFailed: return "无法解析下载服务器地址。"
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid: return "无法建立安全连接，请检查网络或代理。"
        case .cancelled: return "下载中断或安装包超过大小限制。"
        case .badServerResponse: return "下载地址未返回有效的 Windows 安装包。"
        default: return "无法连接下载服务器，请检查网络或代理。"
        }
    }

    private static func download(from url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        // Bound an unresponsive endpoint while allowing a slow transfer that
        // continues to make progress. Cancellation propagates to URLSession.
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delegate = SteamInstallerDownload(progress: progress)
        let (temporaryURL, response) = try await session.download(from: url, delegate: delegate)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.url?.scheme == "https",
              let size = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 2, size <= maximumSize else {
            throw URLError(.badServerResponse)
        }
        let handle = try FileHandle(forReadingFrom: temporaryURL)
        let magic = try handle.read(upToCount: 2)
        try handle.close()
        guard magic == Data([0x4d, 0x5a]) else {
            throw URLError(.badServerResponse)
        }
        // A dedicated directory keeps cleanup limited to this one attempt.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Arclume-SteamSetup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let destination = directory.appendingPathComponent("SteamSetup.exe")
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
