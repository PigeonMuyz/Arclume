import Foundation

nonisolated struct GameDBMetadata: Codable, Sendable {
    struct Artwork: Codable, Sendable { let id: Int; let url: String }
    struct Named: Codable, Sendable { let id: Int; let name: String }
    struct Company: Codable, Sendable { let company: Named; let developer: Bool?; let publisher: Bool? }
    let id: Int
    let name: String
    let summary: String?
    let url: String?
    let cover: Artwork?
    let screenshots: [Artwork]?
    let genres: [Named]?
    let involved_companies: [Company]?
}

nonisolated struct GameDBLink: Codable, Sendable {
    var metadata: GameDBMetadata
    var fetchedAt: Date
}

nonisolated struct GameDBSearchResult: Identifiable, Sendable {
    let id: Int
    let name: String
}

/// Public, static GameDB API used by LizardByte projects (including Sunshine).
/// No credentials or installation paths are sent; only a name-prefix bucket/ID.
actor GameDBMetadataService {
    static let shared = GameDBMetadataService()
    private var buckets: [String: [String: Name]] = [:]
    private struct Name: Decodable { let name: String }

    nonisolated static func bucket(for name: String) -> String {
        let chars = Array(name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        func ascii(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
        guard let first = chars.first, ascii(first) else { return "@" }
        guard chars.count > 1 else { return String(first) }
        if chars[1] == " " { return String(first) }
        return ascii(chars[1]) ? String(chars.prefix(2)) : "@"
    }

    nonisolated static func artworkURL(_ artwork: GameDBMetadata.Artwork?, size: String = "t_cover_big_2x") -> String? {
        guard let artwork else { return nil }
        let raw = artwork.url.hasPrefix("//") ? "https:" + artwork.url : artwork.url
        guard var components = URLComponents(string: raw), components.host == "images.igdb.com",
              components.scheme == "https" else { return nil }
        components.path = components.path.replacingOccurrences(of: "/t_thumb/", with: "/\(size)/")
        return components.url?.absoluteString
    }

    private func data(_ path: String) async throws -> Data {
        let url = URL(string: "https://app.lizardbyte.dev/GameDB/\(path)")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    func search(_ query: String) async throws -> [GameDBSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let key = Self.bucket(for: query)
        let entries: [String: Name]
        if let cached = buckets[key] { entries = cached }
        else {
            entries = try JSONDecoder().decode([String: Name].self, from: await data("buckets/\(key).json"))
            buckets[key] = entries
        }
        return entries.compactMap { id, value in
            guard let id = Int(id), value.name.localizedCaseInsensitiveContains(query) else { return nil }
            return GameDBSearchResult(id: id, name: value.name)
        }.sorted { $0.name < $1.name }.prefix(30).map { $0 }
    }

    func details(id: Int) async throws -> GameDBMetadata {
        guard id > 0 else { throw CocoaError(.fileReadInvalidFileName) }
        let result = try JSONDecoder().decode(GameDBMetadata.self, from: await data("games/\(id).json"))
        guard result.id == id else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
}

nonisolated enum GameDBMetadataResolver {
    static func resolve(_ game: Game) -> Game {
        guard let metadata = game.gameDBLink?.metadata else { return game }
        var result = game
        // Metadata is a fallback layer: local edits and confirmed Steam fields win.
        if result.headerImage.isEmpty { result.headerImage = GameDBMetadataService.artworkURL(metadata.cover) ?? "" }
        if result.shortDescription.isEmpty { result.shortDescription = metadata.summary ?? "" }
        if result.detailedDescription.isEmpty { result.detailedDescription = metadata.summary ?? "" }
        if result.aboutTheGame.isEmpty { result.aboutTheGame = metadata.summary ?? "" }
        if result.developers.isEmpty {
            result.developers = metadata.involved_companies?.filter { $0.developer == true }.map(\.company.name) ?? []
        }
        if result.publishers.isEmpty {
            result.publishers = metadata.involved_companies?.filter { $0.publisher == true }.map(\.company.name) ?? []
        }
        if result.genres?.isEmpty != false {
            result.genres = metadata.genres?.map { Genre(id: String($0.id), description: $0.name) }
        }
        if result.screenshots?.isEmpty != false {
            result.screenshots = metadata.screenshots?.compactMap {
                guard let full = GameDBMetadataService.artworkURL($0, size: "t_screenshot_big") else { return nil }
                return Screenshot(id: $0.id, pathThumbnail: full, pathFull: full)
            }
        }
        return result
    }
}
