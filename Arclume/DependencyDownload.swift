//
//  DependencyDownload.swift
//  Procyon
//

import CryptoKit
import Foundation

nonisolated enum DependencyAsset: String, Codable, CaseIterable, Sendable {
    case gstreamer
    case dxmt

    var displayName: String {
        switch self {
        case .gstreamer: "GStreamer"
        case .dxmt: "DXMT"
        }
    }

    var cacheKey: String { "dependencyArchive.\(rawValue).v1" }
}

nonisolated enum DependencyInstallMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动下载"
        case .manual: "手动导入"
        }
    }
}

enum DependencyInstallError: LocalizedError {
    case missingArchive(DependencyAsset)

    var errorDescription: String? {
        switch self {
        case .missingArchive(let asset):
            return "尚未导入 \(asset.displayName) 压缩包。请选择“手动导入”并先导入所需依赖。"
        }
    }
}

nonisolated struct DependencyArchiveRecord: Codable, Equatable, Sendable {
    let fileName: String
    let sha256: String
    let importedAt: Date
}

enum DependencyArchiveStore {
    nonisolated private static var rootURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("arclume/manual-dependencies", isDirectory: true)
    }

    nonisolated private static var legacyRootURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("procyon/manual-dependencies", isDirectory: true)
    }

    static func importArchive(_ archiveURL: URL, for asset: DependencyAsset) throws -> DependencyArchiveRecord {
        try SafeArchiveExtractor.validate(archiveURL)
        let destinationDirectory = rootURL.appendingPathComponent(asset.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destinationURL = destinationDirectory.appendingPathComponent(archiveURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: archiveURL, to: destinationURL)

        let record = DependencyArchiveRecord(
            fileName: destinationURL.lastPathComponent,
            sha256: SHA256.hash(data: try Data(contentsOf: destinationURL))
                .map { String(format: "%02x", $0) }
                .joined(),
            importedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(record) else { return record }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: asset.cacheKey)
        return record
    }

    nonisolated static func importedArchive(for asset: DependencyAsset) -> URL? {
        guard
            let data = UserDefaults(suiteName: suiteName)?
                .data(forKey: asset.cacheKey),
            let record = try? JSONDecoder().decode(DependencyArchiveRecord.self, from: data)
        else { return nil }
        for root in [rootURL, legacyRootURL] {
            let url = root
                .appendingPathComponent(asset.rawValue, isDirectory: true)
                .appendingPathComponent(record.fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

enum DependencyDownloadSources {
    static func candidates(for officialURL: URL) -> [URL] {
        ArclumeUpdateSource.candidates(for: officialURL).map(\.url)
    }

    static func fetchLatestReleaseTag(repositoryAPIPath: String) async throws -> String {
        guard let officialURL = URL(string: "\(repositoryAPIPath)/releases/latest") else {
            throw URLError(.badURL)
        }
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for candidate in candidates(for: officialURL) {
            do {
                var request = URLRequest(url: candidate)
                request.timeoutInterval = 12
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let tag = json?["tag_name"] as? String, !tag.isEmpty {
                    if let source = ArclumeUpdateSource.candidates(for: officialURL)
                        .first(where: { $0.url == candidate })
                    {
                        ArclumeUpdateSource.rememberSuccessfulCandidate(source)
                    }
                    return tag
                }
                throw URLError(.cannotParseResponse)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
