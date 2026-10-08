import Foundation
import ImageIO

/// Store artwork is separate from appdetails. Only adopt assets that actually exist.
actor SteamProjectArtworkService {
    static let shared = SteamProjectArtworkService()
    struct Artwork: Sendable { var logo: String?; var background: String? }
    private let session: URLSession
    private var cache: [Int: Artwork] = [:]

    init(session: URLSession = .shared) { self.session = session }

    func artwork(appID: Int) async -> Artwork {
        guard appID > 0 else { return Artwork() }
        if let cached = cache[appID] { return cached }
        let root = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/"
        async let logo = validatedImage(root + "logo.png")
        async let background = validatedImage(root + "library_hero.jpg")
        let result = await Artwork(logo: logo, background: background)
        // A transient network error must not permanently cache an absent asset.
        if result.logo != nil && result.background != nil { cache[appID] = result }
        return result
    }

    private func validatedImage(_ value: String) async -> String? {
        guard let url = URL(string: value),
              let (data, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: 12)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true,
              data.count < 12_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return nil }
        return value
    }
}

nonisolated struct AppStoreCatalogItem: Decodable, Identifiable, Sendable {
    let trackId: Int
    let trackName: String
    let description: String?
    let artistName: String?
    let kind: String?
    let artworkUrl512: String?
    let artworkUrl100: String?
    let screenshotUrls: [String]?
    let ipadScreenshotUrls: [String]?
    let trackViewUrl: String?
    var id: Int { trackId }
    var iconURL: URL? { (artworkUrl512 ?? artworkUrl100).flatMap(URL.init(string:)) }
    var platformLabel: String { kind == "mac-software" ? "Mac" : "iPhone / iPad" }
    // App Store icons are not game wordmarks. They are used in search results only.
    var background: String? { screenshotUrls?.first ?? ipadScreenshotUrls?.first }
}

actor AppStoreCatalogService {
    static let shared = AppStoreCatalogService()
    private let session: URLSession
    private var cache: [URL: (Date, [AppStoreCatalogItem])] = [:]
    private var nextRequest = Date.distantPast
    private struct Response: Decodable { let results: [AppStoreCatalogItem] }

    init(session: URLSession = .shared) { self.session = session }

    nonisolated static func requestURL(query: String, country: String, macOnly: Bool) throws -> URL {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.count <= 200,
              country.count == 2, country.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw URLError(.badURL)
        }
        var id = Int(input).flatMap { $0 > 0 ? $0 : nil }
        if input.contains("://") {
            guard let link = URL(string: input), link.scheme == "https", link.host == "apps.apple.com",
                  let component = link.pathComponents.last, component.hasPrefix("id"),
                  let parsed = Int(component.dropFirst(2)), parsed > 0 else {
                throw URLError(.badURL)
            }
            id = parsed
        }
        var components = URLComponents(string: "https://itunes.apple.com/\(id == nil ? "search" : "lookup")")!
        components.queryItems = [
            URLQueryItem(name: id == nil ? "term" : "id", value: id.map(String.init) ?? input),
            URLQueryItem(name: "country", value: country.lowercased()),
            URLQueryItem(name: "entity", value: macOnly ? "macSoftware" : "software"),
            URLQueryItem(name: "limit", value: "20")
        ]
        return components.url!
    }

    nonisolated static func decode(_ data: Data) throws -> [AppStoreCatalogItem] {
        try JSONDecoder().decode(Response.self, from: data).results.filter { $0.trackId > 0 }
    }

    func search(_ query: String, country: String, macOnly: Bool) async throws -> [AppStoreCatalogItem] {
        let url = try Self.requestURL(query: query, country: country, macOnly: macOnly)
        if let (date, items) = cache[url], Date().timeIntervalSince(date) < 300 { return items }
        // Apple's public Search API is rate limited. Reserve the slot before suspension.
        let delay = max(0, nextRequest.timeIntervalSinceNow)
        nextRequest = Date().addingTimeInterval(delay + 3)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let items = try Self.decode(data).filter {
            macOnly ? $0.kind == "mac-software" : $0.kind == "software"
        }
        cache[url] = (Date(), items)
        return items
    }
}

/// Pure draft merge: missing assets must never erase an existing user image.
nonisolated enum ProjectMetadataAdoption {
    static func image(_ incoming: String?, keeping current: String) -> String {
        guard let incoming, let url = URL(string: incoming), url.scheme == "https", url.host != nil else { return current }
        return incoming
    }
}
