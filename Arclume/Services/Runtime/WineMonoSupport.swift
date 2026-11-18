import Foundation

/// Wine 11 / CrossOver 26.3 expects this exact MSI (dlls/appwiz.cpl/addons.c).
/// Wine installs its cached addon without showing the download confirmation.
/// Do not disable mscoree: that would break .NET programs instead of preparing it.
nonisolated enum WineMonoSupport {
    struct Package: Sendable {
        let version: String
        let archive: String
        let originURL: URL
        let sha256: String
        let byteCount: Int64

        func accepts(_ file: URL) throws -> Bool {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize == Int(byteCount) else { return false }
            return try DownloadedResourceFiles.hash(file) == sha256
        }
    }

    static let package = Package(
        version: "10.4.1", archive: "wine-mono-10.4.1-x86.msi",
        originURL: URL(string: "https://github.com/wine-mono/wine-mono/releases/download/wine-mono-10.4.1/wine-mono-10.4.1-x86.msi")!,
        sha256: "071f4b2887e1c97a11d791ff3d65be9429eed6dec4c2708888bfd546ba358e23",
        byteCount: 85_504_000)

    static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arclume/WineAddons", isDirectory: true)
    }

    static func applyEnvironment(to environment: inout [String: String], root: URL = cacheRoot) {
        // Scoped to our Wine child processes; never change the user's XDG cache.
        environment["WINE_HOST_XDG_CACHE_HOME"] = root.path
    }

    /// Initialization must fail in Arclume, not fall through to Wine's installer UI.
    /// Bundled packages can be staged offline; a missing package is prepared via setup.
    static func ensureAvailable(runtimeURL: URL) throws {
        if try package.accepts(cacheRoot.appendingPathComponent("wine/\(package.archive)")) { return }
        let bundled = runtimeURL.appendingPathComponent("share/wine/mono/\(package.archive)")
        guard try package.accepts(bundled) else { throw PreparationError.missingPackage }
        try stage(source: bundled, root: cacheRoot)
    }

    enum PreparationError: LocalizedError {
        case missingPackage
        var errorDescription: String? { "Wine Mono 尚未准备完成，请在运行环境设置中重新准备。" }
    }

    /// Only explicit setup/runtime-selection actions download. Game launch stays offline.
    @concurrent static func prepare(runtimeURL: URL,
                                   progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let fm = FileManager.default
        let target = cacheRoot.appendingPathComponent("wine/\(package.archive)")
        if try package.accepts(target) { return }
        progress(0, "正在准备 Wine Mono…")
        let bundled = runtimeURL.appendingPathComponent("share/wine/mono/\(package.archive)")
        let source: URL
        var temporaryDownload: URL?
        defer { if let temporaryDownload { try? fm.removeItem(at: temporaryDownload) } }
        if try package.accepts(bundled) {
            source = bundled
        } else {
            // No OSS object has been published for Mono yet. Use its pinned official release.
            var request = URLRequest(url: package.originURL)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            let (file, response) = try await ComponentArchiveDownloader.transferToDisk(request: request,
                maximumBytes: package.byteCount, progress: { bytes in
                    progress(Double(bytes) / Double(package.byteCount), "正在下载 Wine Mono…")
                }, configuration: configuration)
            temporaryDownload = file
            guard response.statusCode == 200, response.url?.scheme == "https" else {
                throw ResourceDownloadError.invalidDownload
            }
            source = file
        }
        try Task.checkCancellation()
        try stage(source: source, root: cacheRoot)
        progress(1, "Wine Mono 已准备完成")
    }

    /// Tests use a tiny package and isolated cache; production always uses the pinned MSI.
    static func stage(source: URL, root: URL, material: Package = package) throws {
        guard try material.accepts(source) else { throw ResourceDownloadError.invalidDownload }
        let fm = FileManager.default
        let directory = root.appendingPathComponent("wine", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(material.archive)
        if try material.accepts(target) { return }
        let staging = directory.appendingPathComponent(".mono-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: source, to: staging)
        guard try material.accepts(staging) else { throw ResourceDownloadError.invalidDownload }
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: target)
        }
    }
}
