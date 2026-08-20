//
//  LocalizationTests.swift
//  ProcyonTests
//

import Foundation
import Testing
@testable import Arclume

struct LocalizationTests {
    @Test func simplifiedChineseCoreStringsAreBundled() throws {
        let appBundle = Bundle(for: ContainerSteamStore.self)
        let localizationURL = try #require(
            appBundle.url(forResource: "zh-Hans", withExtension: "lproj")
        )
        let localizedBundle = try #require(Bundle(url: localizationURL))

        #expect(
            localizedBundle.localizedString(
                forKey: "All Games",
                value: nil,
                table: "Localizable"
            ) == "全部游戏"
        )
        #expect(
            localizedBundle.localizedString(
                forKey: "Install",
                value: nil,
                table: "Localizable"
            ) == "安装"
        )
        #expect(
            localizedBundle.localizedString(
                forKey: "Mac Compatibility",
                value: nil,
                table: "Localizable"
            ) == "Mac 兼容性"
        )
    }
}
