//
//  GameCompatibilityStoreTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Arclume

struct GameCompatibilityStoreTests {
    @Test func profilesPersistBySteamAppID() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }

        let store = GameCompatibilityStore(defaults: fixture.defaults)
        store.setCrossOverStatus(.supported, for: 620)
        store.setGPTK4BetaEnabled(true, for: 620)

        let reloaded = GameCompatibilityStore(defaults: fixture.defaults)
        #expect(
            reloaded.profile(for: 620)
                == GameCompatibilityProfile(
                    crossOverStatus: .supported,
                    gptk4BetaEnabled: true
                )
        )
        #expect(reloaded.profile(for: 999) == .defaultProfile)
    }

    @Test func resettingAProfileRemovesItsStoredOverride() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }

        let store = GameCompatibilityStore(defaults: fixture.defaults)
        store.setCrossOverStatus(.unsupported, for: 620)
        store.setCrossOverStatus(.unknown, for: 620)

        #expect(store.profiles[620] == nil)
        #expect(GameCompatibilityStore(defaults: fixture.defaults).profiles[620] == nil)
    }

    @Test func playableOnMacIncludesNativeAndMarkedGames() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let store = GameCompatibilityStore(defaults: fixture.defaults)

        var game = Game.mock
        #expect(store.isPlayableOnMac(game))

        game.isNative = false
        game.platforms.mac = false
        #expect(!store.isPlayableOnMac(game))

        store.setCrossOverStatus(.supported, for: game.steamAppID)
        #expect(store.isPlayableOnMac(game))

        store.setCrossOverStatus(.unsupported, for: game.steamAppID)
        #expect(!store.isPlayableOnMac(game))
    }

    @Test func legacyProfilesDecodeWithoutCrossOverRequirements() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let legacyJSON = Data(
            #"{"620":{"crossOverStatus":"supported","gptk4BetaEnabled":true}}"#.utf8
        )
        fixture.defaults.set(legacyJSON, forKey: "gameCompatibilityProfiles.v1")

        let profile = GameCompatibilityStore(defaults: fixture.defaults).profile(for: 620)

        #expect(profile.crossOverStatus == .supported)
        #expect(profile.gptk4BetaEnabled)
        #expect(profile.crossOverMacRequirements == nil)
    }

    @Test func crossOverRequirementsPersistNormalizeAndClear() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let store = GameCompatibilityStore(defaults: fixture.defaults)
        store.setCrossOverStatus(.supported, for: 620)

        store.updateCrossOverMacRequirements(
            minimum: "  macOS 15, 8 GB RAM\n",
            recommended: "\nApple M3 or later  ",
            for: 620
        )

        let expected = CrossOverMacRequirements(
            minimum: "macOS 15, 8 GB RAM",
            recommended: "Apple M3 or later"
        )
        #expect(store.profile(for: 620).crossOverMacRequirements == expected)
        #expect(
            GameCompatibilityStore(defaults: fixture.defaults)
                .profile(for: 620)
                .crossOverMacRequirements == expected
        )

        store.setCrossOverStatus(.unsupported, for: 620)
        #expect(store.profile(for: 620).crossOverMacRequirements == expected)

        store.clearCrossOverMacRequirements(for: 620)
        #expect(store.profile(for: 620).crossOverMacRequirements == nil)
        #expect(
            GameCompatibilityStore(defaults: fixture.defaults)
                .profile(for: 620)
                .crossOverMacRequirements == nil
        )
    }

    @Test func libraryFilterUsesCompatibilityProfile() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let store = GameCompatibilityStore(defaults: fixture.defaults)
        let library = LibraryPageGlobals()
        library.customAddedGames = []
        var game = Game.mock
        game.isNative = false
        game.platforms.mac = false
        library.games = [game]
        library.libraryFilter = .playableOnMac

        #expect(library.filteredGames(isPlayableOnMac: store.isPlayableOnMac).isEmpty)

        store.setCrossOverStatus(.supported, for: game.steamAppID)
        #expect(library.filteredGames(isPlayableOnMac: store.isPlayableOnMac).map(\.id) == [game.id])
    }

    @Test func libraryDefaultsToInstalledAndSearchExpandsOwnedGames() {
        let library = LibraryPageGlobals()
        library.customAddedGames = []

        var installed = Game.mock
        installed.id = "installed"
        installed.name = "Installed Game"
        installed.isInstalled = true

        var owned = Game.mock
        owned.id = "owned"
        owned.name = "Owned Search Result"
        owned.isInstalled = false

        var steamworks = Game.mock
        steamworks.id = "steamworks"
        steamworks.name = "Steamworks Common Redistributables"
        steamworks.steamAppID = 228_980
        steamworks.type = "tool"
        steamworks.isInstalled = true

        library.games = [installed, owned, steamworks]

        #expect(library.libraryFilter == .installed)
        #expect(library.allGames.map(\.id) == [installed.id, owned.id])
        #expect(library.filteredGames.map(\.id) == [installed.id])

        library.libraryFilter = .all
        #expect(Set(library.filteredGames.map(\.id)) == Set([installed.id, owned.id]))

        library.libraryFilter = .installed
        library.filter = "Owned Search"
        #expect(library.filteredGames.map(\.id) == [owned.id])
    }

    @Test func steamInstallDestinationPrefersNativeMacThenContainerWindows() {
        var game = Game.mock
        game.platforms = Platforms(windows: true, mac: true, linux: false)

        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: true,
                containerSteamAvailable: true
            ) == .nativeSteam
        )
        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: false,
                containerSteamAvailable: true
            ) == .containerSteam
        )

        game.platforms = Platforms(windows: false, mac: true, linux: false)
        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: false,
                containerSteamAvailable: true
            ) == .unavailable
        )

        game.steamAppID = 228_980
        game.type = "tool"
        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: true,
                containerSteamAvailable: true
            ) == .unavailable
        )
    }

    @Test func steamInstallDestinationRequiresOwnershipOnTheTargetClient() {
        var game = Game.mock
        game.platforms = Platforms(windows: true, mac: true, linux: false)

        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: true,
                containerSteamAvailable: true,
                ownership: [.container]
            ) == .containerSteam
        )
        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: true,
                containerSteamAvailable: false,
                ownership: [.container]
            ) == .unavailable
        )

        game.platforms = Platforms(windows: false, mac: true, linux: false)
        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: true,
                containerSteamAvailable: true,
                ownership: [.container]
            ) == .unavailable
        )
    }

    @Test func steamInstallDestinationFallsBackToOwnedClientForUnknownPlatforms() {
        var game = Game.mock
        game.platforms = Platforms(windows: false, mac: false, linux: false)

        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: true,
                containerSteamAvailable: true,
                ownership: [.native]
            ) == .nativeSteam
        )
        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: true,
                containerSteamAvailable: true,
                ownership: [.container]
            ) == .containerSteam
        )
        #expect(
            game.steamInstallDestination(
                nativeSteamAvailable: true,
                containerSteamAvailable: true,
                ownership: []
            ) == .unavailable
        )
    }

    @Test func gptk4PreferenceConfiguresTheRuntime() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.remove() }
        let store = GameCompatibilityStore(defaults: fixture.defaults)
        let options = GameOptions(cxGraphicsBackend: "dxvk")

        store.applyRuntimePreferences(for: 620, to: options)
        #expect(options.cxGraphicsBackend == "dxvk")
        #expect(!options.d3dMtl4Enabled)

        store.setGPTK4BetaEnabled(true, for: 620)
        store.applyRuntimePreferences(for: 620, to: options)
        #expect(options.cxGraphicsBackend == "d3dmetal4")
        #expect(options.d3dMtl4Enabled)
    }
}

private struct DefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "GameCompatibilityStoreTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
