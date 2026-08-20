//
//  SteamTextFormatterTests.swift
//  ProcyonTests
//

import Testing

@testable import Procyon

struct SteamTextFormatterTests {
    @Test
    func descriptionKeepsStructureAndDiscardsEmbeddedMedia() {
        let html = """
        <strong>或者团结起来消灭对手</strong><br><br>
        <span class="bb_img_ctn"><video autoplay poster="https://example.com/poster.jpg">
        <source src="https://example.com/movie.webm" type="video/webm">
        <source src="https://example.com/movie.mp4" type="video/mp4">
        </video></span><br>
        <p>尤其是要争抢小熊软糖的时候&amp;别松手。</p>
        """

        let text = SteamTextFormatter.plainText(fromHTML: html)

        #expect(text == "或者团结起来消灭对手\n尤其是要争抢小熊软糖的时候&别松手。")
        #expect(!text.contains("video"))
        #expect(!text.contains("https://"))
    }

    @Test
    func requirementRemovesRepeatedHeadingAndFormatsList() {
        let html = """
        <strong>最低配置:</strong><br><ul class="bb_ul">
        <li>需要 64 位处理器和操作系统</li>
        <li><strong>内存:</strong> 8 GB RAM</li></ul>
        """

        let text = SteamTextFormatter.requirementText(fromHTML: html)

        #expect(text == "• 需要 64 位处理器和操作系统\n• 内存: 8 GB RAM")
    }

    @Test
    func supportedLanguagesExcludesAudioFootnoteAndMarkers() {
        let html = """
        英语<strong>*</strong>, 简体中文<strong>*</strong>, 繁体中文,
        法语<br><strong>*</strong>提供完全音频支持的语言
        """

        #expect(
            SteamTextFormatter.supportedLanguages(fromHTML: html)
                == ["英语", "简体中文", "繁体中文", "法语"]
        )
    }

    @Test
    func decodesNamedDecimalAndHexEntities() {
        let html = "Tom &amp; Jerry &#8226; &#x4E2D;&#x6587; &unknown;"

        #expect(
            SteamTextFormatter.plainText(fromHTML: html)
                == "Tom & Jerry • 中文 &unknown;"
        )
    }
}
