//
//  AppleAppStoreMetadataService.swift
//  Procyon
//

import Foundation

struct AppleAppStoreImageAsset: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case icon
        case screenshot
    }

    let url: String
    let kind: Kind

    var id: String { url }
}

struct AppleAppStoreMetadata: Codable, Sendable {
    let description: String
    let shortDescription: String
    let developer: String?
    let publisher: String?
    let primaryGenre: String?
    let genres: [String]
    let imageAssets: [AppleAppStoreImageAsset]
}

@MainActor
final class AppleAppStoreMetadataService {
    static let shared = AppleAppStoreMetadataService()

    private struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    private struct LookupResult: Decodable {
        let bundleId: String?
        let description: String?
        let artistName: String?
        let sellerName: String?
        let primaryGenreName: String?
        let genres: [String]?
        let artworkUrl512: String?
        let artworkUrl100: String?
        let screenshotUrls: [String]?
        let ipadScreenshotUrls: [String]?
        let trackViewUrl: String?
    }

    private let cacheURL: URL
    private var cache: [String: AppleAppStoreMetadata] = [:]

    private init() {
        let directory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        cacheURL = directory.appendingPathComponent("ArclumeAppleAppStoreMetadataCache.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: AppleAppStoreMetadata].self, from: data) {
            cache = decoded
        }
    }

    func metadata(
        bundleIdentifier: String,
        language: GameMetadataLanguage,
        includeProductPageMedia: Bool = false
    ) async -> AppleAppStoreMetadata? {
        let mediaScope = includeProductPageMedia ? "product-media" : "basic"
        let cacheKey = "v2:\(language.cacheKey):\(bundleIdentifier.lowercased()):\(mediaScope)"
        if let cached = cache[cacheKey] {
            return cached
        }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        var queryItems = [
            URLQueryItem(name: "bundleId", value: bundleIdentifier),
            URLQueryItem(name: "country", value: language.appleStorefront),
            URLQueryItem(name: "entity", value: "software"),
        ]
        if language == .english {
            queryItems.append(URLQueryItem(name: "lang", value: "en_us"))
        }
        components.queryItems = queryItems

        do {
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return nil
            }

            let payload = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let match = payload.results.first(where: {
                $0.bundleId?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
            }) else {
                return nil
            }

            let description = match.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !description.isEmpty else { return nil }

            var imageAssets = makeImageAssets(from: match)
            if includeProductPageMedia,
               let pageURL = match.trackViewUrl.flatMap(URL.init(string:)) {
                imageAssets += await productPageScreenshotAssets(from: pageURL)
            }
            imageAssets = deduplicated(imageAssets)

            let metadata = AppleAppStoreMetadata(
                description: description,
                shortDescription: String(description.prefix(240)),
                developer: match.artistName?.trimmingCharacters(in: .whitespacesAndNewlines),
                publisher: match.sellerName?.trimmingCharacters(in: .whitespacesAndNewlines),
                primaryGenre: match.primaryGenreName?.trimmingCharacters(in: .whitespacesAndNewlines),
                genres: match.genres ?? [],
                imageAssets: imageAssets
            )
            cache[cacheKey] = metadata
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: cacheURL, options: .atomic)
            }
            return metadata
        } catch {
            console.warn("Apple App Store metadata request failed for \(bundleIdentifier)")
            console.error(String(reflecting: error))
            return nil
        }
    }

    private func makeImageAssets(from result: LookupResult) -> [AppleAppStoreImageAsset] {
        var assets: [AppleAppStoreImageAsset] = []

        if let iconURL = result.artworkUrl512 ?? result.artworkUrl100 {
            assets.append(AppleAppStoreImageAsset(url: iconURL, kind: .icon))
        }
        assets += (result.ipadScreenshotUrls ?? []).map {
            AppleAppStoreImageAsset(url: $0, kind: .screenshot)
        }
        assets += (result.screenshotUrls ?? []).map {
            AppleAppStoreImageAsset(url: $0, kind: .screenshot)
        }

        return assets
    }

    private func productPageScreenshotAssets(from pageURL: URL) async -> [AppleAppStoreImageAsset] {
        do {
            let (data, response) = try await URLSession.shared.data(from: pageURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8),
                  let firstMediaSection = html.range(of: #"<section id="product_media_"#)
            else {
                return []
            }

            let descriptionSection = html.range(
                of: #"<section id="description""#,
                range: firstMediaSection.upperBound..<html.endIndex
            )
            let mediaHTML = String(html[
                firstMediaSection.lowerBound..<(descriptionSection?.lowerBound ?? html.endIndex)
            ])
            let urlPattern = #"https://[^\"\s,]+\.mzstatic\.com/image/[^\"\s,]+"#
            let expression = try NSRegularExpression(pattern: urlPattern)
            let range = NSRange(mediaHTML.startIndex..<mediaHTML.endIndex, in: mediaHTML)

            var bestAssetBySource = [String: (url: String, area: Int)]()
            for match in expression.matches(in: mediaHTML, range: range) {
                guard let urlRange = Range(match.range, in: mediaHTML) else { continue }
                let url = String(mediaHTML[urlRange])
                guard url.contains("PurpleSource"),
                      !url.contains("Placeholder.mill"),
                      let dimensions = imageDimensions(in: url),
                      dimensions.width >= dimensions.height
                else {
                    continue
                }

                guard let lastSlash = url.lastIndex(of: "/") else { continue }
                let sourceKey = String(url[..<lastSlash])
                let area = dimensions.width * dimensions.height
                if bestAssetBySource[sourceKey]?.area ?? 0 < area {
                    bestAssetBySource[sourceKey] = (url, area)
                }
            }

            return bestAssetBySource.values
                .sorted { $0.url < $1.url }
                .map { AppleAppStoreImageAsset(url: $0.url, kind: .screenshot) }
        } catch {
            console.warn("Apple App Store product page media request failed for \(pageURL.absoluteString)")
            return []
        }
    }

    private func imageDimensions(in url: String) -> (width: Int, height: Int)? {
        let pattern = #"/(\d{3,4})x(\d{3,4})bb"#
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: url, range: range),
              let widthRange = Range(match.range(at: 1), in: url),
              let heightRange = Range(match.range(at: 2), in: url),
              let width = Int(url[widthRange]),
              let height = Int(url[heightRange])
        else {
            return nil
        }
        return (width, height)
    }

    private func deduplicated(_ assets: [AppleAppStoreImageAsset]) -> [AppleAppStoreImageAsset] {
        var seen = Set<String>()
        return assets.filter { seen.insert($0.url).inserted }
    }
}
