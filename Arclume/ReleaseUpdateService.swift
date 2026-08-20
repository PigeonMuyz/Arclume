//
//  ReleaseUpdateService.swift
//  Arclume
//

import AppKit
import Combine
import CryptoKit
import Foundation

nonisolated struct ArclumeGitHubRelease: Codable, Equatable, Sendable {
    nonisolated struct Asset: Codable, Equatable, Identifiable, Sendable {
        let id: Int
        let name: String
        let digest: String?
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case digest
            case browserDownloadURL = "browser_download_url"
        }

        var sha256: String? {
            guard let digest,
                  digest.lowercased().hasPrefix("sha256:")
            else { return nil }
            return String(digest.dropFirst("sha256:".count))
        }
    }

    let tagName: String
    let name: String
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    var version: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    var diskImage: Asset? {
        assets.first { $0.name.lowercased().hasSuffix("-no-runtime.dmg") }
            ?? assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }

    func checksumAsset(for asset: Asset) -> Asset? {
        assets.first { $0.name == "\(asset.name).sha256" }
            ?? assets.first { $0.name.lowercased().hasSuffix(".dmg.sha256") }
    }

    var runtimeManifestAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".runtime.json") }
    }
}

nonisolated struct ArclumeRuntimeRelease: Sendable {
    let release: ArclumeGitHubRelease
    let manifest: ArclumeRuntimeManifest
    let archive: ArclumeGitHubRelease.Asset
}

nonisolated enum ArclumeVersionComparison {
    static func isApplicationUpdateAvailable(
        releaseTag: String,
        currentMarketingVersion: String,
        currentBuild: String
    ) -> Bool {
        let release = parseApplicationReleaseTag(releaseTag)
        let marketingComparison = release.marketingVersion.compare(
            currentMarketingVersion,
            options: [.numeric, .caseInsensitive]
        )
        if marketingComparison == .orderedDescending { return true }
        if marketingComparison != .orderedSame { return false }

        guard let releaseBuild = release.buildNumber,
              let currentBuild = Int(currentBuild)
        else { return false }
        return releaseBuild > currentBuild
    }

    static func isRuntimeUpdateAvailable(remoteVersion: String, installedVersion: String) -> Bool {
        remoteVersion.compare(
            installedVersion,
            options: [.numeric, .caseInsensitive]
        ) == .orderedDescending
    }

    private static func parseApplicationReleaseTag(_ tag: String) -> (
        marketingVersion: String,
        buildNumber: Int?
    ) {
        let normalized = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = normalized.split(separator: "-", maxSplits: 1).map(String.init)
        guard let marketingVersion = parts.first, !marketingVersion.isEmpty else {
            return (normalized, nil)
        }
        let buildNumber = parts.count == 2 ? Int(parts[1]) : nil
        return (marketingVersion, buildNumber)
    }
}

private enum ArclumeReleaseRepository {
    case application
    case runtime

    var apiPath: String {
        switch self {
        case .application: "https://api.github.com/repos/PigeonMuyz/Arclume/releases/latest"
        case .runtime: "https://api.github.com/repos/PigeonMuyz/Arclume-Runtime/releases/latest"
        }
    }

    var cacheKey: String {
        switch self {
        case .application: "arclume.update.application.release.v1"
        case .runtime: "arclume.update.runtime.release.v1"
        }
    }

    var eTagKey: String {
        switch self {
        case .application: "arclume.update.application.etag.v1"
        case .runtime: "arclume.update.runtime.etag.v1"
        }
    }
}

private enum ArclumeUpdateError: LocalizedError {
    case invalidResponse
    case httpFailure(Int)
    case rateLimited
    case missingDiskImage
    case missingRuntimeManifest
    case missingRuntimeArchive(String)
    case incompatibleRuntime
    case checksumUnavailable
    case checksumMismatch
    case invalidManifest(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "更新服务返回了无法识别的响应。"
        case .httpFailure(let code): "更新服务请求失败（HTTP \(code)）。"
        case .rateLimited: "GitHub 请求次数已用尽，请稍后重试或切换镜像。"
        case .missingDiskImage: "该应用版本没有可下载的 DMG。"
        case .missingRuntimeManifest: "该 Runtime 版本缺少 Manifest。"
        case .missingRuntimeArchive(let name): "该 Runtime 版本缺少归档 \(name)。"
        case .incompatibleRuntime: "该 Runtime 与当前 Games 容器 ABI 不兼容。"
        case .checksumUnavailable: "该版本未提供 SHA-256 校验信息。"
        case .checksumMismatch: "下载文件的 SHA-256 校验失败，已放弃更新。"
        case .invalidManifest(let message): "Runtime Manifest 无效：\(message)"
        }
    }
}

@MainActor
final class ArclumeUpdateService: ObservableObject {
    @Published private(set) var latestApplicationRelease: ArclumeGitHubRelease?
    @Published private(set) var latestRuntimeRelease: ArclumeRuntimeRelease?
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloadingApplication = false
    @Published private(set) var isUpdatingRuntime = false
    @Published private(set) var applicationError: String?
    @Published private(set) var runtimeError: String?
    @Published private(set) var applicationDownloadMessage: String?
    @Published private(set) var runtimeProgress: Double?
    @Published private(set) var runtimeProgressLabel: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        let resolvedDefaults = defaults ?? UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults = resolvedDefaults
        ArclumeUpdatePreferences.prepareDefaults(in: resolvedDefaults)
        self.latestApplicationRelease = Self.cachedRelease(
            for: .application,
            in: resolvedDefaults
        )
    }

    var currentApplicationVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return build == version ? version : "\(version) (\(build))"
    }

    var isApplicationUpdateAvailable: Bool {
        guard let latestApplicationRelease else { return false }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return ArclumeVersionComparison.isApplicationUpdateAvailable(
            releaseTag: latestApplicationRelease.tagName,
            currentMarketingVersion: version,
            currentBuild: build
        )
    }

    var currentRuntimeVersion: String {
        BundledWineRuntime.installedRuntimeVersion(at: BundledWineRuntime.installationURL)
            ?? BundledWineRuntime.runtimeVersion
    }

    var isRuntimeUpdateAvailable: Bool {
        guard let latestRuntimeRelease else { return false }
        return ArclumeVersionComparison.isRuntimeUpdateAvailable(
            remoteVersion: latestRuntimeRelease.manifest.version,
            installedVersion: currentRuntimeVersion
        )
    }

    func checkForUpdatesAtLaunch() async {
        guard defaults.bool(forKey: ArclumeUpdatePreferences.automaticallyCheck) else { return }
        if defaults.bool(forKey: ArclumeUpdatePreferences.checkAtEveryLaunch) {
            await checkForUpdates()
            return
        }
        let cutoff: TimeInterval = 12 * 60 * 60
        let applicationLastCheckedAt = defaults.object(
            forKey: ArclumeUpdatePreferences.applicationLastCheckedAt
        ) as? Date
        let runtimeLastCheckedAt = defaults.object(
            forKey: ArclumeUpdatePreferences.runtimeLastCheckedAt
        ) as? Date
        guard let applicationLastCheckedAt,
              let runtimeLastCheckedAt,
              Date().timeIntervalSince(applicationLastCheckedAt) < cutoff,
              Date().timeIntervalSince(runtimeLastCheckedAt) < cutoff
        else {
            await checkForUpdates()
            return
        }
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        applicationError = nil
        runtimeError = nil
        defer { isChecking = false }

        do {
            latestApplicationRelease = try await fetchLatestRelease(for: .application)
            defaults.set(
                Date(),
                forKey: ArclumeUpdatePreferences.applicationLastCheckedAt
            )
        } catch {
            applicationError = localizedError(error)
        }

        do {
            let release = try await fetchLatestRelease(for: .runtime)
            latestRuntimeRelease = try await decodeRuntimeRelease(release)
            defaults.set(
                Date(),
                forKey: ArclumeUpdatePreferences.runtimeLastCheckedAt
            )
        } catch {
            runtimeError = localizedError(error)
        }
    }

    func downloadApplicationUpdate() async {
        guard !isDownloadingApplication,
              let release = latestApplicationRelease,
              let diskImage = release.diskImage
        else {
            applicationError = ArclumeUpdateError.missingDiskImage.localizedDescription
            return
        }

        isDownloadingApplication = true
        applicationError = nil
        applicationDownloadMessage = nil
        defer { isDownloadingApplication = false }

        do {
            applicationDownloadMessage = "正在下载 Arclume 更新…"
            let temporaryURL = try await downloadVerifiedAsset(
                diskImage,
                in: release
            )
            let destination = try uniqueDownloadsURL(named: diskImage.name)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            applicationDownloadMessage = "已下载到“下载”文件夹。"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            applicationError = localizedError(error)
        }
    }

    func updateRuntime() async {
        guard !isUpdatingRuntime else { return }
        guard let latestRuntimeRelease else {
            runtimeError = "请先检查 Runtime 更新。"
            return
        }
        guard isRuntimeUpdateAvailable else { return }

        isUpdatingRuntime = true
        runtimeError = nil
        runtimeProgress = 0.02
        runtimeProgressLabel = "正在下载 Arclume Wine \(latestRuntimeRelease.manifest.version)…"
        defer {
            isUpdatingRuntime = false
            runtimeProgress = nil
        }

        do {
            let archiveURL = try await downloadVerifiedAsset(
                latestRuntimeRelease.archive,
                in: latestRuntimeRelease.release
            )
            defer { try? FileManager.default.removeItem(at: archiveURL) }

            let reportProgress: BundledWineRuntime.ProgressHandler = { [weak self] value, label in
                Task { @MainActor [weak self] in
                    self?.runtimeProgress = min(max(value, 0), 1)
                    self?.runtimeProgressLabel = label
                }
            }
            let manifest = latestRuntimeRelease.manifest
            _ = try await Task.detached(priority: .userInitiated) {
                try BundledWineRuntime.installDownloadedRuntimeArchive(
                    archiveURL,
                    manifest: manifest,
                    progress: reportProgress
                )
            }.value
            runtimeProgress = 1
            runtimeProgressLabel = "Arclume Wine 已更新至 \(latestRuntimeRelease.manifest.version)"
        } catch {
            runtimeError = localizedError(error)
        }
    }

    func openApplicationReleasePage() {
        guard let url = latestApplicationRelease?.htmlURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openRuntimeReleasePage() {
        guard let url = latestRuntimeRelease?.release.htmlURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func fetchLatestRelease(
        for repository: ArclumeReleaseRepository
    ) async throws -> ArclumeGitHubRelease {
        guard let officialURL = URL(string: repository.apiPath) else {
            throw URLError(.badURL)
        }

        let cached = Self.cachedRelease(for: repository, in: defaults)
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for source in ArclumeUpdateSource.candidates(for: officialURL, in: defaults) {
            do {
                var request = URLRequest(url: source.url)
                request.timeoutInterval = 8
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                request.setValue("Arclume/\(currentApplicationVersion)", forHTTPHeaderField: "User-Agent")
                if let eTag = defaults.string(forKey: repository.eTagKey), cached != nil {
                    request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
                }

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw ArclumeUpdateError.invalidResponse
                }
                if response.statusCode == 304, let cached {
                    ArclumeUpdateSource.rememberSuccessfulCandidate(source, in: defaults)
                    return cached
                }
                try validate(response)

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let release = try decoder.decode(ArclumeGitHubRelease.self, from: data)
                Self.cache(release, for: repository, in: defaults)
                if let eTag = response.value(forHTTPHeaderField: "ETag") {
                    defaults.set(eTag, forKey: repository.eTagKey)
                }
                ArclumeUpdateSource.rememberSuccessfulCandidate(source, in: defaults)
                return release
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func decodeRuntimeRelease(
        _ release: ArclumeGitHubRelease
    ) async throws -> ArclumeRuntimeRelease {
        guard let manifestAsset = release.runtimeManifestAsset else {
            throw ArclumeUpdateError.missingRuntimeManifest
        }
        let data = try await downloadData(for: manifestAsset)
        if let expected = manifestAsset.sha256,
           Self.sha256(of: data).caseInsensitiveCompare(expected) != .orderedSame
        {
            throw ArclumeUpdateError.checksumMismatch
        }

        let manifest: ArclumeRuntimeManifest
        do {
            manifest = try JSONDecoder().decode(ArclumeRuntimeManifest.self, from: data)
            try manifest.validate()
        } catch let error as ArclumeRuntimeManifestError {
            throw ArclumeUpdateError.invalidManifest(error.localizedDescription)
        } catch {
            throw ArclumeUpdateError.invalidManifest(error.localizedDescription)
        }
        guard BundledWineRuntime.supportsDownloadedRuntimeManifest(manifest) else {
            throw ArclumeUpdateError.incompatibleRuntime
        }
        guard let archive = release.assets.first(where: { $0.name == manifest.archive.name }) else {
            throw ArclumeUpdateError.missingRuntimeArchive(manifest.archive.name)
        }
        if let releaseDigest = archive.sha256,
           releaseDigest.caseInsensitiveCompare(manifest.archive.sha256) != .orderedSame
        {
            throw ArclumeUpdateError.checksumMismatch
        }
        return ArclumeRuntimeRelease(release: release, manifest: manifest, archive: archive)
    }

    private func downloadVerifiedAsset(
        _ asset: ArclumeGitHubRelease.Asset,
        in release: ArclumeGitHubRelease
    ) async throws -> URL {
        let expectedChecksum = try await expectedChecksum(for: asset, in: release)
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for source in ArclumeUpdateSource.candidates(for: asset.browserDownloadURL, in: defaults) {
            do {
                var request = URLRequest(url: source.url)
                request.timeoutInterval = 90
                request.setValue("Arclume/\(currentApplicationVersion)", forHTTPHeaderField: "User-Agent")
                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                try validate(response)
                guard Self.sha256(of: temporaryURL)
                    .caseInsensitiveCompare(expectedChecksum) == .orderedSame
                else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    throw ArclumeUpdateError.checksumMismatch
                }
                ArclumeUpdateSource.rememberSuccessfulCandidate(source, in: defaults)
                return temporaryURL
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func expectedChecksum(
        for asset: ArclumeGitHubRelease.Asset,
        in release: ArclumeGitHubRelease
    ) async throws -> String {
        if let digest = asset.sha256 { return digest }
        guard let checksumAsset = release.checksumAsset(for: asset) else {
            throw ArclumeUpdateError.checksumUnavailable
        }
        let data = try await downloadData(for: checksumAsset)
        guard let text = String(data: data, encoding: .utf8),
              let checksum = text.split(whereSeparator: \.isWhitespace).first,
              checksum.count == 64
        else {
            throw ArclumeUpdateError.checksumUnavailable
        }
        return String(checksum)
    }

    private func downloadData(for asset: ArclumeGitHubRelease.Asset) async throws -> Data {
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for source in ArclumeUpdateSource.candidates(for: asset.browserDownloadURL, in: defaults) {
            do {
                var request = URLRequest(url: source.url)
                request.timeoutInterval = 12
                request.setValue("Arclume/\(currentApplicationVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                try validate(response)
                ArclumeUpdateSource.rememberSuccessfulCandidate(source, in: defaults)
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func uniqueDownloadsURL(named name: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let source = URL(fileURLWithPath: name)
        let stem = source.deletingPathExtension().lastPathComponent
        let suffix = source.pathExtension
        var index = 1
        var candidate = directory.appendingPathComponent(name)
        while FileManager.default.fileExists(atPath: candidate.path) {
            index += 1
            candidate = directory.appendingPathComponent(
                "\(stem) (\(index)).\(suffix)"
            )
        }
        return candidate
    }

    private static func cachedRelease(
        for repository: ArclumeReleaseRepository,
        in defaults: UserDefaults
    ) -> ArclumeGitHubRelease? {
        guard let data = defaults.data(forKey: repository.cacheKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ArclumeGitHubRelease.self, from: data)
    }

    private static func cache(
        _ release: ArclumeGitHubRelease,
        for repository: ArclumeReleaseRepository,
        in defaults: UserDefaults
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(release) {
            defaults.set(data, forKey: repository.cacheKey)
        }
    }

    private static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(of fileURL: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let data = try? handle.read(upToCount: 1024 * 1024),
                  !data.isEmpty
            else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw ArclumeUpdateError.invalidResponse
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            if response.statusCode == 429 || (response.statusCode == 403 && remaining == "0") {
                throw ArclumeUpdateError.rateLimited
            }
            throw ArclumeUpdateError.httpFailure(response.statusCode)
        }
    }

    private func localizedError(_ error: Error) -> String {
        if let error = error as? LocalizedError,
           let description = error.errorDescription
        {
            return description
        }
        return error.localizedDescription
    }
}
