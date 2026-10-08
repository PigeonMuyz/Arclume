import Foundation
import Testing

@testable import Arclume

struct JX3HTMLToMarkdownTests {
    private let source = URL(string: "https://jx3.xoyo.com/announce/gg.html?id=123")!

    @Test func mapsOfficialAnnouncementConventions() throws {
        let html = """
        <p><span style="color:#B22222">【更新内容】</span></p>
        <p><span style="color:#0000FF">◎ 表现</span></p>
        <p><span style="font-family:微软雅黑;color: rgb(0, 0, 255);">1、综合</span></p>
        <p>·优化示例内容，保留<strong>重点</strong>。</p>
        """
        let output = try JX3HTMLToMarkdown.convert(html, articleURL: source)
        #expect(output.contains("## 更新内容"))
        #expect(output.contains("### 表现"))
        #expect(output.contains("#### 1、综合"))
        #expect(output.contains("- 优化示例内容，保留**重点**。"))
        #expect(!output.contains("font-family"))
    }

    @Test func genericRendererDoesNotApplyGameRules() throws {
        let output = try HTMLToMarkdown.convert("<p>【更新内容】</p><p>◎ 表现</p><p>·说明</p>")
        #expect(!output.contains("##"))
        #expect(output.contains("◎ 表现"))
    }

    @Test func ordinaryProseAndImagesAreNotPromoted() throws {
        let output = try JX3HTMLToMarkdown.convert("<p>1、普通编号</p><p>【说明】这是一段正文。</p><p>◎ 示意<img src='/image.jpg'></p>", articleURL: source)
        #expect(!output.contains("####"))
        #expect(!output.contains("## 说明"))
        #expect(output.contains("![](<https://jx3.xoyo.com/image.jpg>)"))
    }

    @Test func styleAloneDoesNotTurnBodyIntoHeading() throws {
        let output = try JX3HTMLToMarkdown.convert("<p style='color:blue'>正常蓝色正文。</p><p style='background-color:blue'>1、不是蓝色标题</p>", articleURL: source)
        #expect(!output.contains("#"))
    }
}
