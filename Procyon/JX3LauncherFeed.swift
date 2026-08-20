//
//  JX3LauncherFeed.swift
//  Procyon
//

import Foundation
import SwiftUI
import Kingfisher

struct JX3LauncherArticle: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let linkURL: URL?
    let summary: String?
    let timestamp: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case thumb
        case url
        case description
        case inputtime
        case updatetime
    }

    init(
        id: String,
        title: String,
        thumbnailURL: URL? = nil,
        linkURL: URL? = nil,
        summary: String? = nil,
        timestamp: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.linkURL = linkURL
        self.summary = summary
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyString(forKey: .id) ?? UUID().uuidString
        title = container.decodeLossyString(forKey: .title) ?? ""
        thumbnailURL = container.decodeURL(forKey: .thumb)
        linkURL = container.decodeURL(forKey: .url)
        summary = container.decodeLossyString(forKey: .description)
        timestamp = container.decodeLossyInt(forKey: .inputtime)
            ?? container.decodeLossyInt(forKey: .updatetime)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumb)
        try container.encodeIfPresent(linkURL, forKey: .url)
        try container.encodeIfPresent(summary, forKey: .description)
        try container.encodeIfPresent(timestamp, forKey: .inputtime)
    }
}

struct JX3LauncherNotice: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let detailURL: URL?
    let dateText: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case asktime
    }

    init(
        id: String,
        title: String,
        detailURL: URL? = nil,
        dateText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detailURL = detailURL
        self.dateText = dateText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyString(forKey: .id) ?? UUID().uuidString
        title = container.decodeLossyString(forKey: .title) ?? ""
        dateText = container.decodeLossyString(forKey: .asktime)

        let rawURL = container.decodeLossyString(forKey: .url)
        if let rawURL, let url = URL(string: rawURL), url.scheme != nil {
            detailURL = url
        } else if let rawURL, !rawURL.isEmpty {
            detailURL = JX3LauncherFeedStore.noticeURL(for: rawURL)
        } else {
            detailURL = JX3LauncherFeedStore.noticeURL(for: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(detailURL, forKey: .url)
        try container.encodeIfPresent(dateText, forKey: .asktime)
    }
}

struct JX3LauncherRecommendations: Codable, Equatable {
    let latestTitle: String?
    let latestURL: URL?
    let newsTitle: String?
    let newsURL: URL?
    let activityTitle: String?
    let activityURL: URL?
    let noticeTitle: String?
    let noticeURL: URL?

    private enum CodingKeys: String, CodingKey {
        case latestTitle = "tj_latest_title"
        case latestURL = "tj_latest_href"
        case newsTitle = "tj_news_title"
        case newsURL = "tj_news_href"
        case activityTitle = "tj_activity_title"
        case activityURL = "tj_activity_href"
        case noticeTitle = "tj_gonggao_title"
        case noticeURL = "tj_gonggao_href"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latestTitle = container.decodeLossyString(forKey: .latestTitle)
        latestURL = container.decodeURL(forKey: .latestURL)
        newsTitle = container.decodeLossyString(forKey: .newsTitle)
        newsURL = container.decodeURL(forKey: .newsURL)
        activityTitle = container.decodeLossyString(forKey: .activityTitle)
        activityURL = container.decodeURL(forKey: .activityURL)
        noticeTitle = container.decodeLossyString(forKey: .noticeTitle)
        noticeURL = container.decodeURL(forKey: .noticeURL)
    }
}

struct JX3LauncherFeed: Codable, Equatable {
    let carousel: [JX3LauncherArticle]
    let news: [JX3LauncherArticle]
    let activities: [JX3LauncherArticle]
    let notices: [JX3LauncherNotice]
    let recommendations: JX3LauncherRecommendations?
    let fetchedAt: Date

    var primaryArtworkURL: URL? {
        carousel.compactMap(\.thumbnailURL).first
            ?? news.compactMap(\.thumbnailURL).first
    }
}

private struct JX3LauncherArticleListResponse: Decodable {
    let data: JX3LauncherArticleListData?
}

private struct JX3LauncherArticleListData: Decodable {
    let list: [JX3LauncherArticle]
}

private struct JX3LauncherNoticeListResponse: Decodable {
    let data: JX3LauncherNoticeListData?
}

private struct JX3LauncherNoticeListData: Decodable {
    let list: [JX3LauncherNotice]
}

enum JX3LauncherFeedStore {
    private static let cacheDirectoryName = "JX3LauncherCache"
    private static let cacheFileName = "feed.json"

    private static let carouselURL = URL(
        string: "https://jx3.xoyo.com/api.php?op=search_api&action=get_article_list&catid=3584&page=1&num=10&order_by=inputtime&sort_by=desc"
    )!
    private static let newsURL = URL(
        string: "https://jx3.xoyo.com/api.php?op=search_api&action=get_article_list&catid=2458&page=1&num=5&order_by=inputtime&sort_by=desc"
    )!
    private static let activitiesURL = URL(
        string: "https://jx3.xoyo.com/api.php?op=search_api&action=get_article_list&catid=2461&page=1&num=5&order_by=inputtime&sort_by=desc"
    )!
    private static let noticesURL = URL(
        string: "https://jx3.xoyo.com/api.php?op=search_api&action=get_customer_article_list&game=jx3&num=5&page=1"
    )!
    private static let recommendationsURL = URL(
        string: "https://jx3.xoyo.com/api/config/tag/zt/jx3_index_tuijian"
    )!

    private static var cacheURL: URL {
        PROCYON_SUPPORT_FOLDER_URL
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(cacheFileName, isDirectory: false)
    }

    static func cachedFeed() -> JX3LauncherFeed? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(JX3LauncherFeed.self, from: data)
    }

    @MainActor
    static func refresh() async -> JX3LauncherFeed? {
        do {
            async let carouselRequest = fetchData(from: carouselURL)
            async let newsRequest = fetchData(from: newsURL)
            async let activitiesRequest = fetchData(from: activitiesURL)
            async let noticesRequest = fetchData(from: noticesURL)
            async let recommendationsRequest = fetchData(from: recommendationsURL)

            let carouselData = try? await carouselRequest
            let newsData = try? await newsRequest
            let activitiesData = try? await activitiesRequest
            let noticesData = try? await noticesRequest
            let recommendationsData = try? await recommendationsRequest

            guard
                carouselData != nil
                    || newsData != nil
                    || activitiesData != nil
                    || noticesData != nil
                    || recommendationsData != nil
            else {
                return nil
            }

            let feed = try makeFeed(
                carouselData: carouselData ?? emptyArticleListData,
                newsData: newsData ?? emptyArticleListData,
                activitiesData: activitiesData ?? emptyArticleListData,
                noticesData: noticesData ?? emptyNoticeListData,
                recommendationsData: recommendationsData ?? emptyRecommendationsData,
                fetchedAt: Date()
            )
            try write(feed)
            return feed
        } catch {
            return nil
        }
    }

    static func makeFeed(
        carouselData: Data,
        newsData: Data,
        activitiesData: Data,
        noticesData: Data,
        recommendationsData: Data,
        fetchedAt: Date
    ) throws -> JX3LauncherFeed {
        let decoder = JSONDecoder()
        let carousel = try decoder.decode(JX3LauncherArticleListResponse.self, from: carouselData)
            .data?.list ?? []
        let news = try decoder.decode(JX3LauncherArticleListResponse.self, from: newsData)
            .data?.list ?? []
        let activities = try decoder.decode(JX3LauncherArticleListResponse.self, from: activitiesData)
            .data?.list ?? []
        let notices = try decoder.decode(JX3LauncherNoticeListResponse.self, from: noticesData)
            .data?.list ?? []
        let recommendations = try decoder.decode(
            JX3LauncherRecommendations.self,
            from: recommendationsData
        )

        return JX3LauncherFeed(
            carousel: carousel,
            news: news,
            activities: activities,
            notices: notices,
            recommendations: recommendations,
            fetchedAt: fetchedAt
        )
    }

    static func noticeURL(for id: String) -> URL? {
        URL(string: "https://jx3.xoyo.com/announce/gg.html?id=\(id)")
    }

    private static let emptyArticleListData = Data(#"{"data":{"list":[]}}"#.utf8)
    private static let emptyNoticeListData = Data(#"{"data":{"list":[]}}"#.utf8)
    private static let emptyRecommendationsData = Data("{}".utf8)

    private static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func write(_ feed: JX3LauncherFeed) throws {
        let directoryURL = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(feed)
        try data.write(to: cacheURL, options: .atomic)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeLossyInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeURL(forKey key: Key) -> URL? {
        guard let value = decodeLossyString(forKey: key) else { return nil }
        return URL(string: value)
    }
}

private enum JX3LauncherSettingsSheet: String, Identifiable {
    case quality
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quality:
            "画质设置"
        case .advanced:
            "高级设置"
        }
    }
}

struct JX3LauncherHomeView: View {
    let game: Game
    @Binding var isPresented: Bool
    let initialFeed: JX3LauncherFeed?
    let onLaunch: () -> Void
    let isLaunching: Bool
    let isPlaying: Bool
    let runtimeActivity: JX3RuntimeActivity
    let onStop: (() -> Void)?
    let onFeedUpdated: ((JX3LauncherFeed) -> Void)?
    let showsCloseButton: Bool

    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appGlobals: AppGlobals
    @StateObject private var gameOptions = GameOptions()
    @State private var feed: JX3LauncherFeed?
    @State private var isRefreshing = false
    @State private var didLoadOptions = false
    @State private var presentedSettings: JX3LauncherSettingsSheet?
    @State private var selectedCarouselID: String?
    @State private var carouselSelectionStartedAt = Date()

    private let carouselInterval: TimeInterval = 7
    private let carouselThumbnailWidth: CGFloat = 76
    private let carouselThumbnailHeight: CGFloat = 46

    init(
        game: Game,
        isPresented: Binding<Bool>,
        initialFeed: JX3LauncherFeed? = nil,
        onLaunch: @escaping () -> Void,
        isLaunching: Bool = false,
        isPlaying: Bool = false,
        runtimeActivity: JX3RuntimeActivity = .idle,
        onStop: (() -> Void)? = nil,
        onFeedUpdated: ((JX3LauncherFeed) -> Void)? = nil,
        showsCloseButton: Bool = true
    ) {
        self.game = game
        self._isPresented = isPresented
        self.initialFeed = initialFeed
        self.onLaunch = onLaunch
        self.isLaunching = isLaunching
        self.isPlaying = isPlaying
        self.runtimeActivity = runtimeActivity
        self.onStop = onStop
        self.onFeedUpdated = onFeedUpdated
        self.showsCloseButton = showsCloseButton
        self._feed = State(initialValue: initialFeed)
    }

    private var fallbackArtworkURL: URL? {
        let value = game.headerImage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return URL(string: value)
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 28
            let verticalPadding: CGFloat = 12
            let headerHeight: CGFloat = 36
            let headerReservedHeight = showsCloseButton ? headerHeight + 14 : 0
            let heroBottomSpacing: CGFloat = 18
            let maximumContentWidth: CGFloat = 1900
            let availableContentWidth = max(
                0,
                geometry.size.width - (horizontalPadding * 2)
            )
            let contentWidth = min(availableContentWidth, maximumContentWidth)
            let heroHeight = heroHeight(for: geometry.size.height)
            let lowerContentHeight = max(
                0,
                geometry.size.height
                    - (verticalPadding * 2)
                    - headerReservedHeight
                    - heroHeight
                    - heroBottomSpacing
            )

            ZStack {
                launcherBackground

                VStack(alignment: .leading, spacing: 0) {
                    if showsCloseButton {
                        header
                            .frame(height: headerHeight)
                            .padding(.bottom, 14)
                    }
                    hero
                        .frame(width: contentWidth, height: heroHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .clipped()
                    lowerContent(for: contentWidth)
                        .frame(width: contentWidth, height: lowerContentHeight, alignment: .leading)
                        .padding(.top, heroBottomSpacing)
                }
                .frame(width: contentWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            loadJX3Options()
            if feed == nil {
                feed = JX3LauncherFeedStore.cachedFeed()
            }
            await refreshFeed()
        }
        .onDisappear {
            persistJX3Options()
        }
        .onChange(of: feed?.carousel.map(\.id)) { _, carouselIDs in
            guard let selectedCarouselID else { return }
            guard carouselIDs?.contains(selectedCarouselID) != true else { return }
            self.selectedCarouselID = nil
            carouselSelectionStartedAt = Date()
        }
    }

    private var launcherBackground: some View {
        Color.clear
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer()

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)

        }
        .foregroundStyle(.white)
    }

    private func heroHeight(for availableHeight: CGFloat) -> CGFloat {
        min(max(availableHeight * 0.56, 360), 700)
    }

    @ViewBuilder
    private var hero: some View {
        if let feed, !feed.carousel.isEmpty {
            if presentedSettings == nil {
                animatedHero(feed)
            } else {
                pausedHero(feed)
            }
        } else {
            fallbackHero
        }
    }

    private func animatedHero(_ feed: JX3LauncherFeed) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            heroContent(
                state: carouselState(at: context.date, from: feed.carousel),
                articles: feed.carousel
            )
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func pausedHero(_ feed: JX3LauncherFeed) -> some View {
        heroSlide(carouselState(at: Date(), from: feed.carousel).article)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func heroContent(
        state: CarouselState,
        articles: [JX3LauncherArticle]
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            heroSlide(state.article)
                .id(state.article.id)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.5), value: state.article.id)

            carouselThumbnailNavigation(
                articles: articles,
                activeArticle: state.article,
                progress: state.progress
            )
        }
    }

    private struct CarouselState {
        let article: JX3LauncherArticle
        let progress: Double
    }

    private func carouselState(
        at date: Date,
        from articles: [JX3LauncherArticle]
    ) -> CarouselState {
        let elapsed: TimeInterval
        let startingIndex: Int

        if let selectedCarouselID,
           let selectedIndex = articles.firstIndex(where: { $0.id == selectedCarouselID }) {
            elapsed = max(date.timeIntervalSince(carouselSelectionStartedAt), 0)
            startingIndex = selectedIndex
        } else {
            elapsed = max(date.timeIntervalSinceReferenceDate, 0)
            startingIndex = 0
        }

        let elapsedIntervals = Int(elapsed / carouselInterval)
        let progress = (elapsed.truncatingRemainder(dividingBy: carouselInterval)) / carouselInterval
        let index = (startingIndex + elapsedIntervals) % articles.count
        return CarouselState(article: articles[index], progress: progress)
    }

    private func carouselThumbnailNavigation(
        articles: [JX3LauncherArticle],
        activeArticle: JX3LauncherArticle,
        progress: Double
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(articles) { article in
                    let isActive = article.id == activeArticle.id

                    Button {
                        selectedCarouselID = article.id
                        carouselSelectionStartedAt = Date()
                    } label: {
                        ZStack(alignment: .bottom) {
                            carouselThumbnailImage(article)
                                .frame(
                                    width: carouselThumbnailWidth,
                                    height: carouselThumbnailHeight
                                )
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )

                            if isActive {
                                carouselProgressBar(progress: progress)
                                    .frame(width: carouselThumbnailWidth - 10, height: 3)
                                    .padding(.bottom, 4)
                            }
                        }
                        .frame(
                            width: carouselThumbnailWidth,
                            height: carouselThumbnailHeight
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(
                                    isActive
                                        ? .procyonSecondary
                                        : .white.opacity(0.18),
                                    lineWidth: isActive ? 2 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(article.title))
                    .accessibilityHint(Text("切换跑马灯内容"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: 560)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func carouselThumbnailImage(_ article: JX3LauncherArticle) -> some View {
        if let imageURL = article.thumbnailURL {
            KFImage(imageURL)
                .placeholder { launcherArtworkFallback }
                .resizable()
                .scaledToFill()
        } else {
            launcherArtworkFallback
        }
    }

    private func carouselProgressBar(progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.45))
                Capsule()
                    .fill(.procyonSecondary)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .clipShape(Capsule())
    }

    private func heroSlide(_ article: JX3LauncherArticle) -> some View {
        ZStack {
            if let imageURL = article.thumbnailURL {
                KFImage(imageURL)
                    .placeholder { launcherArtworkFallback }
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                launcherArtworkFallback
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let linkURL = article.linkURL {
                openURL(linkURL)
            }
        }
    }

    private var fallbackHero: some View {
        ZStack(alignment: .bottomLeading) {
            if let fallbackArtworkURL {
                KFImage(fallbackArtworkURL)
                    .placeholder { launcherArtworkFallback }
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                launcherArtworkFallback
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.88)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("官方资讯暂时不可用，但仍可直接打开。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func lowerContent(for contentWidth: CGFloat) -> some View {
        let spacing: CGFloat = 16
        let columnWidth = max(0, (contentWidth - (spacing * 2)) / 3)

        return HStack(alignment: .top, spacing: 16) {
            noticesPanel
                .frame(width: columnWidth)
            newsPanel
                .frame(width: columnWidth)
            launchSettingsColumn
                .frame(width: columnWidth)
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private var noticesPanel: some View {
        launcherPanel {
            launcherPanelTitle("公告", systemImage: "megaphone.fill")

            ScrollView(.vertical, showsIndicators: false) {
                if let feed, !feed.notices.isEmpty {
                    VStack(spacing: 1) {
                        ForEach(feed.notices) { notice in
                            feedRow(
                                title: notice.title,
                                subtitle: notice.dateText,
                                url: notice.detailURL
                            )
                        }
                    }
                } else {
                    emptyFeedMessage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var newsPanel: some View {
        launcherPanel {
            launcherPanelTitle("资讯", systemImage: "newspaper.fill")

            ScrollView(.vertical, showsIndicators: false) {
                let articles = (feed?.news ?? []) + (feed?.activities ?? [])
                if !articles.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(articles) { article in
                            articleRow(article)
                        }
                    }
                } else {
                    emptyFeedMessage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var launchPanel: some View {
        launcherPanel {
            launcherPanelTitle("启动设置", systemImage: "slider.horizontal.3")

            ScrollView(.vertical, showsIndicators: false) {
                compactRuntimeSettings
                    .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var launchSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            launchPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            launchActionArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $presentedSettings) { settings in
            Modal(
                settings.title,
                showModal: Binding(
                    get: { presentedSettings != nil },
                    set: { isPresented in
                        if !isPresented {
                            presentedSettings = nil
                        }
                    }
                ),
                scrollable: settings.id != "quality"
            ) {
                switch settings {
                case .quality:
                    if gameOptions.externalQualitySettingsEnabled {
                        JX3QualitySettingsView(
                            bottleURL: OnlineGameDiscovery.selectedBottleURL(
                                from: appGlobals.selectedBottle
                            )
                        )
                    }
                case .advanced:
                    JX3AdditionalSettingsView(
                        gameOptions: gameOptions,
                        isRuntimeActive: isPlaying || isLaunching
                    ) {
                        persistJX3Options()
                    }
                }
            }
        }
    }

    private var launchActionArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if gameOptions.externalQualitySettingsEnabled {
                    Button {
                        presentedSettings = .quality
                    } label: {
                        Label("画质设置（Beta）", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLaunching)
                }

                Button {
                    presentedSettings = .advanced
                } label: {
                    Label("高级设置", systemImage: "ellipsis.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .disabled(isLaunching)
            }

            Button {
                if hasConfirmedJX3Runtime {
                    onStop?()
                } else if !isStartingJX3Runtime {
                    persistJX3Options()
                    onLaunch()
                }
            } label: {
                Group {
                    if hasConfirmedJX3Runtime {
                        Label("停止游戏", systemImage: "stop.fill")
                    } else if isStartingJX3Runtime {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text("正在启动…")
                        }
                    } else {
                        Label("打开启动器", systemImage: "play.fill")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(.procyonSecondary)
            .disabled(isStartingJX3Runtime)

            if isPlaying {
                Label(runtimeActivity.state.title, systemImage: runtimeActivity.state.systemImage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 4)
    }

    /// `playingID` is assigned once Wine has accepted the launch request, which
    /// can precede `SeasunGame.exe` by several seconds. Keep the primary action
    /// in its launching state until the monitored process or client log proves
    /// that the launcher/game is actually alive.
    private var hasConfirmedJX3Runtime: Bool {
        isPlaying && runtimeActivity.state != .idle && runtimeActivity.state != .launching
    }

    private var isStartingJX3Runtime: Bool {
        isLaunching || (isPlaying && !hasConfirmedJX3Runtime)
    }

    private func launcherPanel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            .procyonAccent.mix(with: .black, by: 0.66).opacity(0.74),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func launcherPanelTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private var emptyFeedMessage: some View {
        Text(feed == nil ? "正在加载…" : "暂无内容")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }

    private var compactRuntimeSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Metal HUD", isOn: $gameOptions.mtlHudEnabled)
            Toggle("DLSS3 Beta", isOn: $gameOptions.dlssFrameGenerationEnabled)
        }
        .font(.subheadline)
        .controlSize(.small)
        .toggleStyle(.switch)
        .onChange(of: gameOptions.mtlHudEnabled) { _, _ in persistJX3Options() }
        .onChange(of: gameOptions.dlssFrameGenerationEnabled) { _, _ in persistJX3Options() }
    }

    private func feedRow(title: String, subtitle: String?, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right.circle")
                    .foregroundStyle(.procyonSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
                if url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    private func articleRow(_ article: JX3LauncherArticle) -> some View {
        Button {
            if let url = article.linkURL { openURL(url) }
        } label: {
            HStack(spacing: 10) {
                if let imageURL = article.thumbnailURL {
                    KFImage(imageURL)
                        .placeholder { launcherArtworkFallback }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 74, height: 46)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    launcherArtworkFallback
                        .frame(width: 74, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(article.title)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(article.linkURL == nil)
    }

    private var launcherArtworkFallback: some View {
        LinearGradient(
            colors: [
                .procyonSecondary.opacity(0.72),
                .procyonAccent.mix(with: .black, by: 0.56)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "sparkles.tv")
                .font(.title)
                .foregroundStyle(.white.opacity(0.48))
        }
    }

    @MainActor
    private func refreshFeed() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if let refreshedFeed = await JX3LauncherFeedStore.refresh() {
            feed = refreshedFeed
            onFeedUpdated?(refreshedFeed)
        }
    }

    private var gameOptionsKey: String {
        namespacedKey("GameOptions", OnlineGameMode.gameOptionsIdentifier(for: game))
    }

    private func loadJX3Options() {
        guard !didLoadOptions else { return }
        if let data: GameOptionsData = readUsrDefData(key: gameOptionsKey) {
            gameOptions.set(data: data)
        }
        OnlineGameMode.applyDefaultRuntimePreferences(to: gameOptions)
        didLoadOptions = true
    }

    private func persistJX3Options() {
        guard didLoadOptions else { return }
        persistUsrDefData(key: gameOptionsKey, data: GameOptionsData(data: gameOptions))
    }
}
