import SwiftUI
import Kingfisher

/// Artwork stays behind the whole launcher; only the right column contains content.
struct LauncherGameHomeView: View {
    let game: Game
    let onLaunchJX3: () -> Void
    let onStopJX3: () -> Void
    @StateObject private var gameOptions = GameOptions()
    @State private var feed: JX3LauncherFeed?
    @State private var officialArtwork: JX3LauncherArtwork?
    @State private var newsTab = 0
    @State private var logoFailed = false
    @State private var showDetails = false

    private var isJX3: Bool { OnlineGameMode.isJX3(game) }
    private var artworkAppID: Int { game.steamMetadataLink?.appID ?? game.steamAppID }

    private var logoURL: URL? {
        if let override = OnlineGamePresentationStore.logoURL(for: game.id) { return override }
        if isJX3 { return officialArtwork?.logoURL }
        let appID = artworkAppID
        guard appID > 0 else { return nil }
        return URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/logo.png")
    }

    private var artworkURLs: [URL] {
        let custom = OnlineGamePresentationStore.presentation(for: game.id).selectedArtworkURLString
        // JX3's generic game metadata may also contain a carousel thumbnail.
        let candidates = isJX3 ? [custom, officialArtwork?.backgroundURL.absoluteString]
            : [custom, game.backgroundRaw, game.screenshots?.first?.pathFull, game.headerImage]
        var seen = Set<URL>()
        return candidates.compactMap { value -> URL? in
            guard let value, !value.isEmpty, let url = URL(string: value),
                  ["https", "http", "file"].contains(url.scheme?.lowercased() ?? ""),
                  seen.insert(url).inserted else { return nil }
            return url
        }
    }

    private var summary: String {
        game.shortDescription
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasNews: Bool {
        guard let feed else { return false }
        return !feed.news.isEmpty || !feed.notices.isEmpty || !feed.carousel.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = min(350.0, max(270.0, geometry.size.width * 0.29))
            HStack {
                Spacer(minLength: 135)
                VStack(spacing: 18) {
                    gameMark
                        .frame(height: min(130, geometry.size.height * 0.19))
                        .frame(maxWidth: .infinity)
                    informationPanel(width: columnWidth)
                        .frame(width: columnWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                    GameHeader(
                        game: .constant(game), showDetailView: .constant(false),
                        launcherStyle: true,
                        onLauncherStart: isJX3 ? onLaunchJX3 : nil,
                        onLauncherStop: isJX3 ? onStopJX3 : nil
                    )
                    .environmentObject(gameOptions)
                    .frame(width: columnWidth)
                }
                .frame(width: columnWidth)
                .padding(.trailing, 28)
                .padding(.top, 22)
                .padding(.bottom, 22)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                LauncherBackdrop(game: game, urls: artworkURLs, preservesWholeArtwork: isJX3)
                    .id(artworkURLs)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showDetails) {
            Modal("详细信息", showModal: $showDetails, subdued: true) {
                GameDetailView(game: .constant(game), embedded: true)
                    .frame(minWidth: 760, minHeight: 560)
            }
        }
        .task(id: game.id) {
            guard isJX3 else { return }
            officialArtwork = JX3LauncherArtworkStore.cached()
            if let updated = await JX3LauncherArtworkStore.refresh(), !Task.isCancelled { officialArtwork = updated }
        }
        .task(id: game.id) {
            guard isJX3 else { return }
            feed = JX3LauncherFeedStore.cachedFeed()
            if let updated = await JX3LauncherFeedStore.refresh(), !Task.isCancelled { feed = updated }
        }
        .onChange(of: logoURL) { _, _ in logoFailed = false }
    }

    @ViewBuilder private var gameMark: some View {
        if isJX3, OnlineGamePresentationStore.logoURL(for: game.id) == nil,
           let data = officialArtwork?.logoData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
                .padding(.horizontal, 20)
                .accessibilityLabel(game.name)
        } else if let logoURL, !logoFailed {
            KFImage(logoURL)
                .onFailure { _ in logoFailed = true }
                .placeholder { fallbackMark }
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 20)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 2)
                .accessibilityLabel(game.name)
        } else { fallbackMark }
    }

    private var fallbackMark: some View {
        HStack(spacing: 14) {
            LauncherApplicationIcon(game: game, size: 58)
            Text(game.name)
                .font(.system(size: 25, weight: .semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 12, y: 2)
    }

    private func informationPanel(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if hasNews, let feed {
                    if let article = feed.carousel.first, let imageURL = article.thumbnailURL {
                        Button {
                            if let url = article.linkURL { NSWorkspace.shared.open(url) }
                        } label: {
                            GeometryReader { geometry in
                                KFImage(imageURL).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: 144).clipped()
                            }
                                .frame(height: 144)
                                .overlay(alignment: .bottomLeading) {
                                    Text(article.title).font(.caption).lineLimit(2)
                                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.black.opacity(0.5))
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(article.linkURL == nil)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Picker("官方消息", selection: $newsTab) {
                        Text("资讯").tag(0)
                        Text("公告").tag(1)
                    }.pickerStyle(.segmented)
                    if newsTab == 0 {
                        ForEach(Array(feed.news.prefix(5))) { article in
                            newsRow(title: article.title, date: article.timestamp.map { Date(timeIntervalSince1970: Double($0)).formatted(date: .numeric, time: .omitted) }, url: article.linkURL)
                        }
                        if feed.news.isEmpty { overview }
                    } else {
                        ForEach(Array(feed.notices.prefix(5))) { notice in
                            newsRow(title: notice.title, date: notice.dateText, url: notice.detailURL)
                        }
                        if feed.notices.isEmpty { overview }
                    }
                } else { overview }
            }
            .frame(width: max(0, width - 36), alignment: .leading)
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("关于此游戏").font(.headline)
            if !summary.isEmpty {
                Text(summary).font(.body).foregroundStyle(.secondary).lineSpacing(5)
                    .lineLimit(9)
            }
            Divider()
            LabeledContent("平台", value: game.isNative ? "macOS" : "Windows")
            LabeledContent("状态", value: game.isInstalled ? "已安装" : "未安装")
            if !game.developers.isEmpty {
                LabeledContent("开发商", value: game.developers.joined(separator: "、"))
            }
            if let executable = game.appExeURL?.lastPathComponent {
                LabeledContent("启动程序", value: executable).lineLimit(2)
            }
            Button { showDetails = true } label: {
                Label("查看详细信息", systemImage: "info.circle")
            }.buttonStyle(.borderless)
        }
        .font(.callout)
        .textSelection(.enabled)
    }

    private func newsRow(title: String, date: String?, url: URL?) -> some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
                if let date { Text(date).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }
}

private struct LauncherBackdrop: View {
    let game: Game
    let urls: [URL]
    var preservesWholeArtwork = false
    @State private var candidate = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.11, blue: 0.29), Color(red: 0.045, green: 0.05, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if urls.indices.contains(candidate) {
                    KFImage(urls[candidate])
                        .onFailure { _ in candidate += 1 }
                        .resizable()
                        .aspectRatio(contentMode: preservesWholeArtwork ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: preservesWholeArtwork ? 0 : 10)
                        .clipped()
                        .id(candidate)
                } else if !preservesWholeArtwork {
                    // Applications without artwork still get a game-specific ambient background.
                    LauncherApplicationIcon(game: game, size: max(geometry.size.width, geometry.size.height))
                        .blur(radius: 70).opacity(0.28)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                if !preservesWholeArtwork {
                    LinearGradient(colors: [.indigo.opacity(0.2), .black.opacity(0.25), .black.opacity(0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
