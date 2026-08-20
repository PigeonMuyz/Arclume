//
//  SteamMetadataLinkTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Arclume

struct SteamMetadataLinkTests {
    @Test func parserAcceptsAppIDsAndStoreURLs() {
        #expect(SteamMetadataLinkParser.appID(from: "2325290") == 2_325_290)
        #expect(
            SteamMetadataLinkParser.appID(
                from: "https://store.steampowered.com/app/2325290/Sky_Children_of_the_Light/"
            ) == 2_325_290
        )
        #expect(SteamMetadataLinkParser.appID(from: "steam://store/2325290") == 2_325_290)
        #expect(
            SteamMetadataLinkParser.appID(
                from: "https://example.com/details?appid=2325290"
            ) == 2_325_290
        )
        #expect(SteamMetadataLinkParser.appID(from: "not a Steam app") == nil)
    }

    @Test @MainActor
    func resolverKeepsNativeLaunchIdentityAndAppliesSelectedMetadata() throws {
        var base = Game.emptyGame
        base.id = "native-app:/Applications/Sky.app"
        base.name = "光遇【国服】"
        base.steamAppID = 0
        base.appExeURL = URL(fileURLWithPath: "/Applications/Sky.app")
        base.nativeAppBundleIdentifier = "com.example.sky.cn"
        base.isNative = true
        base.isInstalled = true
        base.headerImage = "local-header"
        base.detailedDescription = "本地介绍"
        base.developers = ["本地开发商"]
        base.platforms = Platforms(windows: false, mac: true, linux: false)

        let link = SteamMetadataLink(
            appID: Game.steamMock.steamAppID,
            confirmedStoreName: Game.steamMock.name
        )
        base.steamMetadataLink = link

        let resolved = SteamMetadataResolver.resolvedGame(
            base: base,
            metadata: Game.steamMock,
            link: link
        )

        #expect(resolved.id == base.id)
        #expect(resolved.name == Game.steamMock.name)
        #expect(resolved.steamAppID == 0)
        #expect(resolved.appExeURL == base.appExeURL)
        #expect(resolved.nativeAppBundleIdentifier == base.nativeAppBundleIdentifier)
        #expect(resolved.isNative)
        #expect(resolved.isInstalled)
        #expect(resolved.platforms.mac)
        #expect(!resolved.platforms.windows)
        #expect(resolved.headerImage == Game.steamMock.headerImage)
        #expect(resolved.detailedDescription == Game.steamMock.detailedDescription)
        #expect(resolved.developers == Game.steamMock.developers)
        #expect(resolved.screenshots?.count == Game.steamMock.screenshots?.count)
    }

    @Test @MainActor
    func resolverOnlyAppliesFieldsConfirmedByTheUser() {
        var base = Game.emptyGame
        base.name = "光遇【国服】"
        base.headerImage = "local-header"
        base.detailedDescription = "本地介绍"
        base.developers = ["本地开发商"]
        let link = SteamMetadataLink(
            appID: Game.steamMock.steamAppID,
            confirmedStoreName: Game.steamMock.name,
            fields: [.artwork]
        )

        let resolved = SteamMetadataResolver.resolvedGame(
            base: base,
            metadata: Game.steamMock,
            link: link
        )

        #expect(resolved.headerImage == Game.steamMock.headerImage)
        #expect(resolved.detailedDescription == "本地介绍")
        #expect(resolved.developers == ["本地开发商"])
        #expect(resolved.name == "光遇【国服】")
    }

    @Test @MainActor
    func legacyGameJSONDecodesWithoutSteamMetadataLink() throws {
        var object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(Game.emptyGame)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "steam_metadata_link")
        object.removeValue(forKey: "is_from_native_steam_library")

        let decoded = try JSONDecoder().decode(
            Game.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.steamMetadataLink == nil)
        #expect(decoded.isFromNativeSteamLibrary == nil)
    }
}
