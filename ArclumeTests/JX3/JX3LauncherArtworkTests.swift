import Foundation
import Testing
@testable import Arclume

struct JX3LauncherArtworkTests {
    private let background = "https://jx3-capi.xoyocdn.com/uploadfile/background.jpg"

    @Test func releaseBackgroundIsNotCarouselOrTestServerArtwork() throws {
        let html = #"<template>{"1":{"prod_kv":"https:\/\/jx3-capi.xoyocdn.com\/uploadfile\/background.jpg","exp_kv":"https://jx3-capi.xoyocdn.com/test.jpg","thumb":"https://jx3-capi.xoyocdn.com/thumb.png","swiper":"carousel"}}</template>"#
        let result = try #require(JX3LauncherArtwork.parse(html: html))
        #expect(result.backgroundURL.absoluteString == background)
    }

    @Test func extractsOnlyTheOfficialGameLogo() throws {
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let html = """
        <template>{"1":{"prod_kv":"\(background)"}}</template>
        <img src="https://jx3-capi.xoyocdn.com/spinner.png"/>
        <img src="data:image/png;base64,\(png.base64EncodedString())" class="index_logoImage__hash" alt="剑网3 Logo 图片"/>
        """
        let result = try #require(JX3LauncherArtwork.parse(html: html))
        #expect(result.logoData == png)
        #expect(result.logoURL == nil)
        #expect(try JSONDecoder().decode(JX3LauncherArtwork.self, from: JSONEncoder().encode(result)) == result)
    }

    @Test func missingOrUnsafeBackgroundDoesNotFallBackToCarousel() {
        for value in ["", "file:///tmp/image.jpg", "https://xoyocdn.com.evil.test/image.jpg"] {
            #expect(JX3LauncherArtwork.parse(html: "<template>{\"1\":{\"prod_kv\":\"\(value)\",\"thumb\":\"\(background)\"}}</template>") == nil)
        }
        #expect(JX3LauncherArtwork.parse(html: "<template>invalid</template>") == nil)
    }

    @Test func supportsRemoteLogoWithoutMistakingOtherImages() throws {
        let html = "<template>{\"1\":{\"prod_kv\":\"\(background)\"}}</template><img alt='剑网3 Logo 图片' src='https://jx3-capi.xoyocdn.com/logo.png'>"
        let result = try #require(JX3LauncherArtwork.parse(html: html))
        #expect(result.logoURL?.lastPathComponent == "logo.png")
        #expect(result.logoData == nil)
    }
}
