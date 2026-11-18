import Foundation

/// SeasunGame's JX3_Remote.json -> URL.BackGroundUrls -> official launcher HTML.
/// prod_kv is the release-server backdrop; swiper/thumb are not backdrop assets.
nonisolated struct JX3LauncherArtwork: Codable, Equatable {
    let backgroundURL: URL
    let logoData: Data?
    let logoURL: URL?

    static let pageURL = URL(string: "https://jx3xlauncher.xoyocdn.com/v2/uiweb/jx3.html")!

    static func parse(html: String) -> Self? {
        var background: URL?
        for template in captures(#"<template\b[^>]*>([\s\S]*?)</template>"#, in: html) {
            guard let data = template.data(using: .utf8),
                  let records = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { continue }
            background = records.values.compactMap { officialURL($0["prod_kv"] as? String) }.first
            if background != nil { break }
        }
        guard let background else { return nil }

        var logoData: Data?
        var logoURL: URL?
        for image in captures(#"(<img\b[^>]*>)"#, in: html) {
            // Match the game's mark, never a spinner, news thumbnail or collaboration logo.
            guard captures(#"\balt=["']([^"']*)["']"#, in: image).first == "剑网3 Logo 图片",
                  let source = captures(#"\bsrc=["']([^"']*)["']"#, in: image).first else { continue }
            let prefix = "data:image/png;base64,"
            if source.hasPrefix(prefix), let bytes = Data(base64Encoded: String(source.dropFirst(prefix.count))),
               bytes.count <= 512_000, bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
                logoData = bytes
            } else {
                logoURL = officialURL(source)
            }
            break
        }
        return Self(backgroundURL: background, logoData: logoData, logoURL: logoURL)
    }

    private static func officialURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https",
              let host = url.host?.lowercased(),
              host == "xoyocdn.com" || host.hasSuffix(".xoyocdn.com"),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}

@MainActor
enum JX3LauncherArtworkStore {
    private static var cacheURL: URL {
        ARCLUME_SUPPORT_FOLDER_URL.appendingPathComponent("JX3LauncherCache/official-artwork.json")
    }

    static func cached() -> JX3LauncherArtwork? {
        guard !ArclumeTestEnvironment.isTesting,
              let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(JX3LauncherArtwork.self, from: data)
    }

    static func refresh() async -> JX3LauncherArtwork? {
        guard !ArclumeTestEnvironment.isTesting else { return nil }
        do {
            let request = URLRequest(url: JX3LauncherArtwork.pageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, let response = response as? HTTPURLResponse,
                  response.statusCode == 200, data.count <= 2_000_000,
                  let html = String(data: data, encoding: .utf8),
                  let artwork = JX3LauncherArtwork.parse(html: html) else { return nil }
            // A failed refresh must leave the last valid theme intact.
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(artwork).write(to: cacheURL, options: .atomic)
            return artwork
        } catch { return nil }
    }
}
