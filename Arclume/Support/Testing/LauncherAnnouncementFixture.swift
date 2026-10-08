#if DEBUG
import SwiftUI

/// Production news panel and reader with offline content, not a separate mock UI.
struct LauncherAnnouncementFixture: View {
    @State private var selection: LauncherNewsItem?
    private let feed = JX3LauncherFeed(
        carousel: [
            JX3LauncherArticle(id: "slide-1", title: "示例轮播一", thumbnailURL: URL(fileURLWithPath: "/Arclume-Fixture/slide-1.png")),
            JX3LauncherArticle(id: "slide-2", title: "示例轮播二", thumbnailURL: URL(fileURLWithPath: "/Arclume-Fixture/slide-2.png"))
        ],
        news: [JX3LauncherArticle(id: "sample-news", title: "全新资料片资讯", timestamp: 1_790_208_000)],
        activities: [],
        notices: [JX3LauncherNotice(id: "sample", title: "9月24日“苍生铸世”资料片第二轮武学调整", detailURL: URL(string: "https://jx3.xoyo.com/announce/gg.html?id=1335822"), dateText: "2026年9月24日")],
        recommendations: nil, fetchedAt: .distantPast
    )

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(colors: [Color.indigo.opacity(0.55), Color.black.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 14) {
                Text("游戏标志").font(.largeTitle).frame(height: 120)
                LauncherNewsPanel(feed: feed) { selection = $0 }
                Button("开始游戏") {}.buttonStyle(.glassProminent).disabled(true)
            }
            .frame(width: 304).padding(14)
        }
        .sheet(item: $selection) { item in
            LauncherAnnouncementView(item: item, previewMarkdown:
                ProcessInfo.processInfo.environment["ARCLUME_ARTICLE_LIVE_FIXTURE"] == "1" ? nil : Self.markdown)
        }
    }

    static let markdown = """
    示例正文 · 自编内容

    ## 本次更新

    为了让每次启动更从容，我们整理了准备流程与状态提示。以下内容为界面展示用的自编示例。

    - 启动准备步骤更清晰，运行状态一眼可见。
    - 常用入口更容易找到，操作路径更连贯。
    - 更新内容会保留完整原文入口。

    ## 阅读说明

    正文保持舒适行宽，段落与列表按阅读顺序排列。较长的公告内容可沿当前版面继续向下展开。

    ## 后续内容

    完整公告还可继续补充更新列表与使用说明，保持一页阅读的连贯节奏。

    """ + String(repeating: "\n\n## 更多更新\n\n用于验证滚动的示例内容。支持 **重点**、列表与引用。\n\n> 示例引用内容。\n", count: 8)
}
#endif
