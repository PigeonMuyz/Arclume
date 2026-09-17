import Foundation

enum LauncherGameCatalog {
    /// Keep sidebar order and do not inherit obsolete grid filters.
    static func filtered(_ games: [Game], query: String) -> [Game] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return games.filter { game in
            game.isInstalled
                && (search.isEmpty || game.name.localizedStandardContains(search))
        }
    }
}
