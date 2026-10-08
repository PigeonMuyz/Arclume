import Foundation
import Testing

@testable import Arclume

struct JX3ArticleContentTests {
    private let announcementURL = URL(
        string: "https://jx3.xoyo.com/announce/gg.html?id=1335811"
    )!
    private let newsURL = URL(string: "https://jx3.xoyo.com/show-2458-7510-1.html")!

    @Test func mapsAnnouncementAndNewsLinksToOfficialEndpoints() throws {
        let announcementEndpoint = try JX3ArticleContentService.endpoint(for: announcementURL)
        let announcementComponents = try #require(
            URLComponents(url: announcementEndpoint, resolvingAgainstBaseURL: false)
        )
        #expect(announcementEndpoint.scheme == "https")
        #expect(announcementEndpoint.host == "jx3.xoyo.com")
        #expect(announcementEndpoint.path == "/api.php")
        #expect(Dictionary(uniqueKeysWithValues: (announcementComponents.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        }) == [
            "op": "search_api",
            "action": "get_customer_article_detail",
            "game": "jx3",
            "kid": "1335811",
        ])

        let newsEndpoint = try JX3ArticleContentService.endpoint(for: newsURL)
        let newsComponents = try #require(URLComponents(url: newsEndpoint, resolvingAgainstBaseURL: false))
        #expect(newsEndpoint.scheme == "https")
        #expect(newsEndpoint.host == "jx3.xoyo.com")
        #expect(newsEndpoint.path == "/api.php")
        #expect(Dictionary(uniqueKeysWithValues: (newsComponents.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        }) == [
            "op": "search_api",
            "action": "get_article_detail",
            "catid": "2458",
            "id": "7510",
        ])

        let legacyHTTPURL = URL(string: "http://jx3.xoyo.com/announce/gg.html?id=1335811")!
        #expect(try JX3ArticleContentService.endpoint(for: legacyHTTPURL).scheme == "https")
    }

    @Test func decodesAnnouncementObjectAndConvertsOfficialHTML() throws {
        let data = try response(code: 1, data: [
            "title": "版本更新公告",
            "content": "<p>【更新内容】</p><p>公告正文。</p>",
        ])

        let article = try JX3ArticleContentService.decode(data, sourceURL: announcementURL)

        #expect(article.markdown.contains("## 更新内容"))
        #expect(article.markdown.contains("公告正文。"))
    }

    @Test func decodesNewsArrayAndPrefersObservedContentField() throws {
        let data = try response(code: 1, data: [[
            "id": 7510,
            "content": "<p>现网 content 字段。</p>",
            "contentHTML": "<p>兼容字段。</p>",
        ]])

        let article = try JX3ArticleContentService.decode(data, sourceURL: newsURL)

        #expect(article.markdown == "现网 content 字段。")
        #expect(!article.markdown.contains("兼容字段"))
    }

    @Test func acceptsContentHTMLWhenThatIsTheOnlyBodyField() throws {
        let data = try response(code: "1", data: [
            "contentHTML": "<p>兼容 contentHTML 正文。</p>",
        ])

        let article = try JX3ArticleContentService.decode(data, sourceURL: announcementURL)

        #expect(article.markdown == "兼容 contentHTML 正文。")
    }

    @Test func rejectsUntrustedOrUnsupportedSourceURLs() {
        let urls = [
            URL(string: "https://jx3.xoyo.com.evil.example/announce/gg.html?id=1335811")!,
            URL(string: "https://user:secret@jx3.xoyo.com/announce/gg.html?id=1335811")!,
            URL(string: "https://jx3.xoyo.com:8443/announce/gg.html?id=1335811")!,
            URL(string: "https://jx3.xoyo.com/other.html?id=1335811")!,
            URL(string: "https://jx3.xoyo.com/announce/gg.html?id=1&id=2")!,
            URL(fileURLWithPath: "/tmp/gg.html"),
        ]

        for url in urls {
            #expect(throws: JX3ArticleContentError.unsupportedSource) {
                try JX3ArticleContentService.endpoint(for: url)
            }
        }
    }

    @Test func rejectsFailedServiceResponsesWithLocalizedError() throws {
        let data = try response(code: 0, data: ["content": "<p>不可用</p>"])

        #expect(throws: JX3ArticleContentError.serviceRejected) {
            try JX3ArticleContentService.decode(data, sourceURL: announcementURL)
        }
        #expect(JX3ArticleContentError.serviceRejected.errorDescription?.contains("暂不可用") == true)
    }

    @Test func reportsEmptyArticleBody() throws {
        let data = try response(code: 1, data: ["content": "<p> \n </p>"])

        #expect(throws: JX3ArticleContentError.emptyContent) {
            try JX3ArticleContentService.decode(data, sourceURL: announcementURL)
        }
    }

    @Test func enforcesResponseSizeLimit() {
        let oversizedData = Data(repeating: 0, count: 4 * 1_024 * 1_024 + 1)

        #expect(throws: JX3ArticleContentError.responseTooLarge) {
            try JX3ArticleContentService.decode(oversizedData, sourceURL: announcementURL)
        }
    }

    @Test func requiresNewsPayloadToContainTheRequestedArticle() throws {
        let data = try response(code: 1, data: [[
            "id": 9999,
            "content": "<p>另一篇新闻。</p>",
        ]])

        #expect(throws: JX3ArticleContentError.articleUnavailable) {
            try JX3ArticleContentService.decode(data, sourceURL: newsURL)
        }
    }

    private func response(code: Any, data: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": code, "data": data])
    }
}
