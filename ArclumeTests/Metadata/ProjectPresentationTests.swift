import AppKit
import SwiftUI
import Testing
@testable import Arclume

@MainActor
struct ProjectPresentationTests {
    @Test func presentationNeverChangesLaunchIdentity() {
        var original = Game.mock
        original.appExeURL = URL(fileURLWithPath: "/fixture/Game.exe")
        original.installedBottleURL = URL(fileURLWithPath: "/fixture/prefix")
        original.installedRuntimeKind = "fixture-runtime"
        let presentation = ProjectPresentation(name: "本地名称", summary: "简介", background: "https://example.com/bg.png", logo: nil)
        let result = presentation.apply(to: original)
        #expect(result.name == "本地名称")
        #expect(result.shortDescription == "简介")
        #expect(result.id == original.id)
        #expect(result.steamAppID == original.steamAppID)
        #expect(result.appExeURL == original.appExeURL)
        #expect(result.installedBottleURL == original.installedBottleURL)
        #expect(result.installedRuntimeKind == original.installedRuntimeKind)
        #expect(result.isNative == original.isNative)
        #expect(result.appNames == original.appNames)
    }

    @Test func profileMatchesAndPreservesUserTitle() throws {
        let json = #"{"schemaVersion":1,"profiles":[{"id":"demo","gameIDs":["known"],"executableNames":["Demo.exe"],"localized":{"zh-Hans":{"name":"示例","summary":"中文简介"},"en":{"name":"Demo"}}}]}"#
        let catalog = try JSONDecoder().decode(GamePresentationProfiles.Catalog.self, from: Data(json.utf8))
        let profile = try #require(catalog.profiles.first)
        var game = Game.emptyGame
        game.id = "known"; game.name = "Demo"; game.shortDescription = ""
        #expect(profile.matches(game))
        #expect(profile.apply(to: game, language: "zh-Hans").name == "示例")
        #expect(profile.apply(to: game, language: "zh-Hans").shortDescription == "中文简介")
        #expect(profile.text(language: "fr")?.name == "Demo")
        game.name = "我的自定义名称"
        #expect(profile.apply(to: game, language: "zh-Hans").name == game.name)
        game.id = "other"; game.appExeURL = URL(fileURLWithPath: "/fixture/DEMO.EXE")
        #expect(profile.matches(game))
        game.appExeURL = URL(fileURLWithPath: "/fixture/Other.exe")
        #expect(!profile.matches(game))
    }

    @Test func legacyPresentationAndSourceRoundTrip() throws {
        let data = Data(#"{"name":"Legacy"}"#.utf8)
        var value = try JSONDecoder().decode(ProjectPresentation.self, from: data)
        #expect(value.metadataSource == nil)
        value.metadataSource = .init(provider: "gamedb", id: "17000", language: "schinese")
        #expect(try JSONDecoder().decode(ProjectPresentation.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func localizedMetadataAndLegacyFallback() throws {
        let data = Data(#"{"id":17000,"name":"Stardew Valley","summary":"English summary","external_games":[{"external_game_source":{"name":"Steam"},"uid":"413150"},{"external_game_source":{"name":"Other"}}]}"#.utf8)
        var metadata = try JSONDecoder().decode(GameDBMetadata.self, from: data)
        #expect(metadata.preferredName == "Stardew Valley")
        metadata.localizedName = "星露谷物语"; metadata.localizedSummary = "中文简介"
        #expect(metadata.preferredName == "星露谷物语")
        var game = Game.emptyGame
        game.shortDescription = ""
        game.gameDBLink = GameDBLink(metadata: metadata, fetchedAt: .distantPast)
        #expect(GameDBMetadataResolver.resolve(game).shortDescription == "中文简介")
        game.shortDescription = "我编辑的介绍"
        #expect(GameDBMetadataResolver.resolve(game).shortDescription == "我编辑的介绍")
    }

    @Test func iconAccentUsesHueAndCapsBrightness() throws {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let color = try #require(NSColor(LauncherAccent.color(from: image)).usingColorSpace(.sRGB))
        #expect(color.redComponent > color.greenComponent)
        #expect(color.redComponent > color.blueComponent)
        #expect(color.brightnessComponent <= 0.7)
    }
}
