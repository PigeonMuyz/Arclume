import Foundation
import Testing

@testable import Arclume

struct HTMLToMarkdownTests {
    @Test func headingsInlineFormattingAndEntities() throws {
        let output = try HTMLToMarkdown.convert("<h2>更新 &amp; 说明</h2><p>保留 <strong>加粗</strong> 与 <em>强调</em>。&nbsp;&#x4E2D;文</p>")
        #expect(output.contains("## 更新 & 说明"))
        #expect(output.contains("保留 **加粗** 与 *强调*。 中文"))
        #expect(!output.contains("<p>"))
    }

    @Test func repairsUnclosedHTMLAndKeepsLineBreaks() throws {
        let output = try HTMLToMarkdown.convert("<p>第一段<p>第二段<br>下一行")
        #expect(output.contains("第一段"))
        #expect(output.contains("第二段  \n下一行"))
    }

    @Test func resolvesRelativeImagesAndLinks() throws {
        let output = try HTMLToMarkdown.convert(
            "<a href='../news?id=1&amp;page=2'>原文</a><img src='/image/a.jpg' alt='示意图'><img src='//cdn.example.com/b.png'>",
            baseURL: URL(string: "https://example.com/articles/42")!
        )
        #expect(output.contains("[原文](<https://example.com/news?id=1&page=2>)"))
        #expect(output.contains("![示意图](<https://example.com/image/a.jpg>)"))
        #expect(output.contains("![](<https://cdn.example.com/b.png>)"))
    }

    @Test func doesNotUseUntrustedBaseOrEventAttributes() throws {
        let output = try HTMLToMarkdown.convert(
            "<html><head><base href='https://evil.example/'></head><body><img src='/safe.png' onerror='steal()'><p hidden>secret</p></body></html>",
            baseURL: URL(string: "https://example.com")!
        )
        #expect(output.contains("https://example.com/safe.png"))
        #expect(!output.contains("evil"))
        #expect(!output.contains("steal"))
        #expect(!output.contains("secret"))
    }

    @Test func discardsActiveContentAndUnsafeURLs() throws {
        let output = try HTMLToMarkdown.convert("""
        <script>alert(1)</script><style>bad{}</style><iframe src='https://evil.example'>frame</iframe>
        <p><a href='java&#x73;cript:alert(1)'>保留文字</a><img src='data:image/svg+xml,bad'>
        <a href='file:///etc/passwd'>文件</a><a href='https://user:pass@example.com'>账户</a></p>
        """)
        #expect(output.contains("保留文字"))
        #expect(!output.contains("alert"))
        #expect(!output.contains("bad"))
        #expect(!output.contains("passwd"))
        #expect(!output.contains("user:pass"))
        #expect(!output.contains("frame"))
    }

    @Test func rejectsEntityDeclarations() {
        #expect(throws: HTMLToMarkdown.ConversionError.entityDeclarationsNotAllowed) {
            try HTMLToMarkdown.convert("<!DOCTYPE x [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><p>&x;</p>")
        }
    }

    @Test func preservesCodeWithoutTreatingItAsHTMLOrMarkdown() throws {
        let output = try HTMLToMarkdown.convert("<p><code>a`b</code></p><pre><code>  a &lt; b\n\n\n```\n</code></pre>")
        #expect(output.contains("``a`b``"))
        #expect(output.contains("````\n  a < b\n\n\n```\n````"))
    }

    @Test func handlesNestedAndOrderedLists() throws {
        let output = try HTMLToMarkdown.convert("<ol start='3'><li>第三项<ul><li>子项</li></ul></li><li>第四项</li></ol>")
        #expect(output.contains("3. 第三项"))
        #expect(output.contains("   - 子项"))
        #expect(output.contains("4. 第四项"))
    }

    @Test func rendersQuoteAndLiteralMarkdownSafely() throws {
        let output = try HTMLToMarkdown.convert("<blockquote><p>引用</p></blockquote><p>[不是链接](javascript:bad) *原样* &lt;script&gt;</p>")
        #expect(output.contains("> 引用"))
        #expect(output.contains("\\[不是链接\\]"))
        #expect(output.contains("\\*原样\\*"))
        #expect(output.contains("\\<script\\>"))
    }

    @Test func convertsSimpleTable() throws {
        let output = try HTMLToMarkdown.convert("<table><tr><th>类型</th><th>内容</th></tr><tr><td>A|B</td><td>第一行<br>第二行</td></tr></table>")
        #expect(output.contains("| 类型 | 内容 |\n| --- | --- |"))
        #expect(output.contains("| A\\|B | 第一行   第二行 |"))
    }

    @Test func spanningTableDoesNotDiscardCellContents() throws {
        let output = try HTMLToMarkdown.convert("<table><caption>表格说明</caption><tr><td colspan='2'><p>跨列信息</p></td></tr><tr><td>左</td><td>右</td></tr></table>")
        #expect(output.contains("表格说明"))
        #expect(output.contains("跨列信息"))
        #expect(output.contains("左"))
        #expect(output.contains("右"))
    }

    @Test func mediaBecomesSafeLinkNotEmbed() throws {
        let output = try HTMLToMarkdown.convert("<video><source src='https://example.com/movie.mp4'></video>")
        #expect(output.contains("[视频](<https://example.com/movie.mp4>)"))
        #expect(!output.contains("<video"))
    }

    @Test func html5EntitiesAndWhitespaceOnlyFormatting() throws {
        let output = try HTMLToMarkdown.convert("<article><p>a<strong> </strong>b &NotEqualTilde;</p><picture><source srcset='bad'><img src='https://example.com/a.png'></picture></article>")
        #expect(output.contains("a b ≂̸"))
        #expect(output.contains("https://example.com/a.png"))
    }

    @Test func preservesWhitespaceAroundLinkLabels() throws {
        let output = try HTMLToMarkdown.convert("<p>foo<a href='https://example.com'> bar </a>baz<a href='javascript:bad'> safe </a>end</p>")
        #expect(output == "foo [bar](<https://example.com>) baz safe end")
    }

    @Test func tableEscapesPipesInsideCodeAndLinks() throws {
        let output = try HTMLToMarkdown.convert("<table><tr><th>内容</th></tr><tr><td><code>A|B</code> C|D <a href='https://example.com/?q=a%7Cb'>链接</a></td></tr></table>")
        #expect(output.contains("`A\\|B` C\\|D"))
        #expect(!output.contains("C\\\\|D"))
    }

    @Test func enforcesInputAndTreeLimits() {
        #expect(throws: HTMLToMarkdown.ConversionError.inputTooLarge) {
            try HTMLToMarkdown.convert("<p>hello</p>", limits: .init(maximumInputBytes: 4))
        }
        #expect(throws: HTMLToMarkdown.ConversionError.documentTooComplex) {
            try HTMLToMarkdown.convert("<p>hello</p>", limits: .init(maximumNodes: 2))
        }
        #expect(throws: HTMLToMarkdown.ConversionError.documentTooComplex) {
            try HTMLToMarkdown.convert("<div><div><div><p>text</p></div></div></div>", limits: .init(maximumDepth: 3))
        }
    }

    @Test func emptyAndLargeArticle() throws {
        #expect(try HTMLToMarkdown.convert("") == "")
        let article = String(repeating: "<p>公告段落与<strong>重点</strong>。</p>", count: 4_000)
        let output = try HTMLToMarkdown.convert(article)
        #expect(output.components(separatedBy: "公告段落").count == 4_001)
        #expect(output.contains("**重点**"))
    }
}
