import Foundation

/// Display-only overrides. Never stores or changes executable/container identity.
nonisolated struct ProjectPresentation: Codable, Equatable {
    struct MetadataSource: Codable, Equatable {
        var provider: String
        var id: String
        var language: String
    }
    var name: String?
    var summary: String?
    var background: String?
    var logo: String?
    var metadataSource: MetadataSource? = nil

    func apply(to game: Game) -> Game {
        var result = game
        if let name, !name.isEmpty { result.name = name }
        if let summary { result.shortDescription = summary }
        if let background, !background.isEmpty { result.backgroundRaw = background }
        return result
    }
}

enum ProjectPresentationStore {
    static let key = "projectPresentations.v1"
    static func read() -> [String: ProjectPresentation] {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key),
              let values = try? JSONDecoder().decode([String: ProjectPresentation].self, from: data) else { return [:] }
        return values
    }
    static func save(_ value: ProjectPresentation, for id: String) {
        var values = read()
        values[id] = value
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults(suiteName: suiteName)?.set(data, forKey: key)
        }
    }
}

nonisolated struct GamePresentationProfile: Codable {
    struct Localized: Codable { var name: String; var summary: String? }
    var id: String
    var gameIDs: [String]
    var executableNames: [String]
    var localized: [String: Localized]
    var backgroundURL: String?
    var logoURL: String?
    var artworkProvider: String?

    func matches(_ game: Game) -> Bool {
        gameIDs.contains(game.id) || game.appExeURL.map {
            executableNames.map { $0.lowercased() }.contains($0.lastPathComponent.lowercased())
        } == true
    }
    func text(language: String) -> Localized? { localized[language] ?? localized["en"] ?? localized["zh-Hans"] }
    func apply(to game: Game, language: String) -> Game {
        var result = game
        if let text = text(language: language) {
            if result.name.isEmpty || localized.values.contains(where: { $0.name == result.name }) || result.name == "剑网3旗舰版" {
                result.name = text.name
            }
            if result.shortDescription.isEmpty { result.shortDescription = text.summary ?? "" }
        }
        if let backgroundURL { result.backgroundRaw = backgroundURL }
        return result
    }
}

enum GamePresentationProfiles {
    struct Catalog: Decodable { let schemaVersion: Int; let profiles: [GamePresentationProfile] }
    static let bundled: [GamePresentationProfile] = {
        guard let url = Bundle.main.url(forResource: "game-profiles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data), catalog.schemaVersion == 1 else { return [] }
        return catalog.profiles
    }()
    static func profile(for game: Game) -> GamePresentationProfile? { bundled.first { $0.matches(game) } }
    static func resolve(_ game: Game) -> Game {
        profile(for: game)?.apply(to: game, language: GameMetadataLanguage.current == .simplifiedChinese ? "zh-Hans" : "en") ?? game
    }
}
