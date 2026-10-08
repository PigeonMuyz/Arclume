import Testing
@testable import Arclume

@MainActor
struct LauncherGameCatalogTests {
    private var games: [Game] {
        var first = Game.mock
        first.id = "yy"; first.name = "YY语音"; first.isInstalled = true
        var second = Game.mock
        second.id = "jx3"; second.name = "剑网3"; second.isInstalled = false
        return [first, second]
    }

    @Test func installedScopeIsStrictEvenWhileSearching() {
        #expect(LauncherGameCatalog.filtered(games, query: "").map(\.id) == ["yy"])
        #expect(LauncherGameCatalog.filtered(games, query: "剑网").isEmpty)
    }

    @Test func installedItemsPreserveOrderWithoutUsingSelection() {
        var installedGames = games
        installedGames[1].isInstalled = true
        #expect(LauncherGameCatalog.filtered(installedGames, query: "").map(\.id) == ["yy", "jx3"])
        #expect(LauncherGameCatalog.filtered(installedGames.reversed(), query: "").map(\.id) == ["jx3", "yy"])
    }

    @Test func searchTrimsWhitespaceAndIgnoresCase() {
        #expect(LauncherGameCatalog.filtered(games, query: " yy ").map(\.id) == ["yy"])
        #expect(LauncherGameCatalog.filtered(games, query: "missing").isEmpty)
        #expect(LauncherGameCatalog.filtered([], query: "").isEmpty)
    }
}
