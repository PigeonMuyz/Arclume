import Foundation
import Testing

@testable import Arclume

struct ArticleReaderRenderingTests {
    @Test func convertsOnlyForegroundColorsToSafeSpans() throws {
        let output = try HTMLToMarkdown.convert(
            "<p><span style='color: red'>红色</span> <font color='#0000ff'>蓝色</font></p>",
            preserveTextColors: true
        )

        #expect(output.contains("#ff0000"))
        #expect(output.contains("#0000ff"))
        #expect(output.contains("红色"))
        #expect(output.contains("蓝色"))
        #expect(output.contains("<span"))
    }

    @Test func normalizesSafeHexAndRGBColors() throws {
        let output = try HTMLToMarkdown.convert(
            "<span style='color:#AbC'>短十六进制</span><span style='color:rgb(0, 0, 255)'>RGB蓝色</span>",
            preserveTextColors: true
        )

        #expect(output.contains("color:#aabbcc"))
        #expect(output.contains("color:#0000ff"))
    }

    @Test func rejectsInvalidRGBAndCSSColors() throws {
        let output = try HTMLToMarkdown.convert(
            "<span style='color:rgb(0,0,256)'>越界RGB</span><span style='color:rgba(0,0,255,0.5)'>透明RGB</span><span style='color:#12xz34'>错误十六进制</span><span style='color:expression(alert(1))'>表达式颜色</span>",
            preserveTextColors: true
        )

        #expect(output.contains("越界RGB"))
        #expect(output.contains("透明RGB"))
        #expect(output.contains("错误十六进制"))
        #expect(output.contains("表达式颜色"))
        #expect(!output.contains("<span"))
        #expect(!output.localizedCaseInsensitiveContains("rgb("))
        #expect(!output.localizedCaseInsensitiveContains("expression"))
    }

    @Test func retainsInheritedColorsInNestedInlineContent() throws {
        let output = try HTMLToMarkdown.convert(
            "<span style='color:#ff0000'>外层<strong>粗体继承</strong><span>普通继承</span></span>",
            preserveTextColors: true
        )

        #expect(output.contains("color:#ff0000"))
        #expect(output.contains("外层"))
        #expect(output.contains("粗体继承"))
        #expect(output.contains("普通继承"))
        #expect(output.components(separatedBy: "color:#ff0000").count - 1 >= 3)
    }

    @Test func doesNotTreatBackgroundColorAsTextColor() throws {
        let output = try HTMLToMarkdown.convert(
            "<span style='background-color:#ff0000'>只有背景色</span>",
            preserveTextColors: true
        )

        #expect(output.contains("只有背景色"))
        #expect(!output.contains("#ff0000"))
        #expect(!output.contains("<span"))
    }

    @Test func dropsUnsafeStylesAndActiveHTML() throws {
        let output = try HTMLToMarkdown.convert(
            "<span style='color:expression(alert(1));background-image:url(javascript:alert(2))'>正文</span><script>alert(3)</script>",
            preserveTextColors: true
        )

        #expect(output.contains("正文"))
        #expect(!output.localizedCaseInsensitiveContains("expression"))
        #expect(!output.localizedCaseInsensitiveContains("javascript:"))
        #expect(!output.localizedCaseInsensitiveContains("alert"))
        #expect(!output.localizedCaseInsensitiveContains("<script"))
    }

    @Test func defaultConversionRemainsPlainMarkdown() throws {
        let output = try HTMLToMarkdown.convert("<span style='color:red'>仍保留正文</span>")

        #expect(output.contains("仍保留正文"))
        #expect(!output.contains("<span"))
        #expect(!output.contains("#ff0000"))
    }

    @Test func adjacentColoredStrongTextDoesNotLeaveEmptyMarkdownEmphasis() throws {
        let output = try HTMLToMarkdown.convert(
            "<span style='color:red'><strong>第一段</strong></span><span style='color:blue'><strong>第二段</strong></span>",
            preserveTextColors: true
        )

        #expect(output.contains("第一段"))
        #expect(output.contains("第二段"))
        #expect(!output.contains("****"))
    }

    @Test func rendersColoredMarkdownAndKeepsSafeHTTPSLinks() throws {
        let document = try ArticleReaderDocument.make(
            markdown: #"<span style="color:#ff0000">公告重点</span> [查看官网](https://jx3.xoyo.com/announce/42)"#
        )

        #expect(document.contains("公告重点"))
        #expect(document.localizedCaseInsensitiveContains("<span"))
        #expect(document.localizedCaseInsensitiveContains("color:"))
        #expect(document.contains("https://jx3.xoyo.com/announce/42"))
        #expect(document.localizedCaseInsensitiveContains("script-src 'none'"))
        #expect(document.localizedCaseInsensitiveContains("<style"))
    }

    @Test func sanitizesActiveContentEventsAndUnsafeResourceURLs() throws {
        let document = try ArticleReaderDocument.make(markdown: """
        <script>alert('script')</script>
        <iframe src="https://evil.example/frame">嵌入内容</iframe>
        <img src="javascript:alert(1)" onerror="steal()">
        <a href="javascript:alert(2)" onclick="steal()">危险链接</a>
        <a href="https://safe.example/article">安全链接</a>
        """)

        #expect(!document.localizedCaseInsensitiveContains("<script"))
        #expect(!document.localizedCaseInsensitiveContains("<iframe"))
        #expect(!document.localizedCaseInsensitiveContains("onerror="))
        #expect(!document.localizedCaseInsensitiveContains("onclick="))
        #expect(!document.localizedCaseInsensitiveContains("javascript:"))
        #expect(!document.localizedCaseInsensitiveContains("evil.example"))
        #expect(document.contains("https://safe.example/article"))
        #expect(document.contains("安全链接"))
    }

    @Test func adaptsDarkBlueForDarkAppearanceAndRetainsSourceColor() throws {
        let document = try ArticleReaderDocument.make(
            markdown: #"<span style="color:#00008b">深蓝重点</span>"#
        )

        #expect(document.contains("深蓝重点"))
        #expect(document.contains("--source-color:#00008b"))
        #expect(document.contains("--text-light:#00008b"))
        #expect(!document.contains("--text-dark:#00008b"))
    }

    @Test func decodesOptInOfficialArticleFixture() throws {
        guard let path = ProcessInfo.processInfo.environment["ARCLUME_ARTICLE_TEST_JSON"], !path.isEmpty else {
            return
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let sourceURL = URL(string: "https://jx3.xoyo.com/announce/gg.html?id=1335822")!
        let startedAt = ContinuousClock.now
        let article = try JX3ArticleContentService.decode(data, sourceURL: sourceURL)
        let elapsed = startedAt.duration(to: .now)

        print(
            "[ArticleReaderRenderingTests] input=\(data.count) bytes, markdown=\(article.markdown.utf8.count) bytes, readerHTML=\(article.readerHTML.utf8.count) bytes, decode=\(elapsed)"
        )
        #expect(article.readerHTML.contains("#0000ff"))
        #expect(article.readerHTML.contains("#ff0000"))
        #expect(!article.readerHTML.contains("****"))
        #expect(!article.readerHTML.localizedCaseInsensitiveContains("<script"))
    }
}
