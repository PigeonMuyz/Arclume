import Foundation

/// Presentation identity stays stable when the feed refreshes or the carousel advances.
nonisolated struct LauncherNewsItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let date: String?
    let kind: String
    let sourceURL: URL?

    init(article: JX3LauncherArticle) {
        id = "news-" + article.id
        title = article.title
        date = article.timestamp.map { Date(timeIntervalSince1970: Double($0)).formatted(date: .numeric, time: .omitted) }
        kind = "资讯"
        sourceURL = article.linkURL
    }

    init(notice: JX3LauncherNotice) {
        id = "notice-" + notice.id
        title = notice.title
        date = notice.dateText
        kind = "公告"
        sourceURL = notice.detailURL
    }

    init(id: String, title: String, date: String?, kind: String, sourceURL: URL?) {
        self.id = id
        self.title = title
        self.date = date
        self.kind = kind
        self.sourceURL = sourceURL
    }

    var safeSourceURL: URL? {
        guard let url = sourceURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
