import SwiftUI
import Kingfisher
import Flow
import AVKit

/// The standard library's detail sheet. Presentation is independent of launch routing.
struct GameDetailView: View {
    @Binding var game: Game?
    var embedded = false
    @EnvironmentObject private var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject private var compatibilityStore: GameCompatibilityStore
    @StateObject private var gameOptions = GameOptions()
    @State private var selectedMovieURL: URL?
    @State private var player = AVPlayer()
    @State private var posterFailed = false
    @State private var showFullPoster = false
    @State private var expandedDescription = false

    private var hasPoster: Bool {
        guard let value = game?.headerImage.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, URL(string: value) != nil else { return false }
        return !posterFailed
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let game {
                ScrollView {
                    VStack(spacing: 0) {
                            ZStack(alignment: .bottomLeading) {
                                LinearGradient(colors: [Color(red: 0.15, green: 0.12, blue: 0.36), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                                if hasPoster {
                                Button { showFullPoster = true } label: {
                                    GameDetailPoster(urlString: game.headerImage, failed: $posterFailed)
                                }
                                .buttonStyle(.plain)
                                .help("查看完整海报")
                                } else {
                                    GameDetailArtwork(game: game, size: 100)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .frame(height: 300)
                                GameHeader(
                                    game: $game,
                                    showDetailView: $libraryPageGlobals.showDetailView,
                                    overlaysPoster: true
                                )
                                .padding(.horizontal, 30)
                                .padding(.vertical, 22)
                                .background(.white.opacity(0.055))
                                .environment(\.colorScheme, .dark)
                        Divider().opacity(0.35)
                        HStack(alignment: .top, spacing: 36) {
                        VStack(alignment: .leading, spacing: 20) {
                            overview(for: game)
                            media(for: game)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 24) {
                            information(for: game)
                        }
                        .frame(width: 230, alignment: .leading)
                        }
                        .padding(30)
                        .frame(minHeight: 150, alignment: .top)
                        .textSelection(.enabled)
                    }
                }
            }
            if !embedded { Button {
                libraryPageGlobals.showDetailView = false
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title2)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))
            .background(.black.opacity(0.4), in: Circle())
            .keyboardShortcut(.cancelAction)
            .help("关闭详情")
            .accessibilityLabel("关闭详情")
            .accessibilityIdentifier("gameDetail.close")
            .padding(14)
            }
        }
        .frame(width: embedded ? nil : 920, height: embedded ? nil : (hasExtendedContent ? 680 : 560))
        .background(Color(red: 0.09, green: 0.075, blue: 0.22))
        .environment(\.colorScheme, .dark)
        .onChange(of: game?.headerImage) { _, _ in posterFailed = false }
        .environmentObject(gameOptions)
        .sheet(isPresented: $showFullPoster) {
            VStack(spacing: 16) {
                HStack {
                    Text("完整海报").font(.headline)
                    Spacer()
                    Button("完成") { showFullPoster = false }
                        .keyboardShortcut(.cancelAction)
                }
                KFImage(game.flatMap { URL(string: $0.headerImage) })
                    .resizable().scaledToFit()
                    .frame(width: 740, height: 480)
            }
            .padding(20)
        }
        .sheet(isPresented: Binding(
            get: { selectedMovieURL != nil },
            set: { if !$0 { selectedMovieURL = nil; player.pause() } }
        )) {
            VStack(spacing: 12) {
                HStack {
                    Text("视频预览").font(.headline)
                    Spacer()
                    Button("完成") { player.pause(); selectedMovieURL = nil }
                        .keyboardShortcut(.cancelAction)
                }
                VideoPlayer(player: player).frame(width: 720, height: 405)
            }
            .padding(20)
            .onAppear {
                guard let url = selectedMovieURL else { return }
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
            }
            .onDisappear { player.pause() }
        }
        .onDisappear { player.pause() }
        .accessibilityIdentifier("gameDetail.sheet")
    }

    private var hasExtendedContent: Bool {
        guard let game else { return false }
        return !SteamTextFormatter.plainText(fromHTML: game.detailedDescription).isEmpty
            || !(game.screenshots ?? []).isEmpty || !(game.movies ?? []).isEmpty
            || game.pcRequirements != nil || game.macRequirements != nil
            || game.linuxRequirements != nil || crossOverRequirements(for: game) != nil
    }

    private func overview(for game: Game) -> some View {
        Group {
            let description = SteamTextFormatter.plainText(fromHTML: game.detailedDescription)
            if !description.isEmpty || !(game.contentDescriptors?.notes ?? "").isEmpty {
                detailSection("简介", icon: "text.alignleft") {
                    if !description.isEmpty {
                        Text(description).font(.callout).lineSpacing(5)
                            .lineLimit(expandedDescription ? nil : 6)
                        if description.count > 220 {
                            Button(expandedDescription ? "收起简介" : "展开简介") {
                                expandedDescription.toggle()
                            }
                            .buttonStyle(.link)
                        }
                    }
                    if let notes = game.contentDescriptors?.notes, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if game.pcRequirements != nil || game.macRequirements != nil
                || game.linuxRequirements != nil || crossOverRequirements(for: game) != nil {
                detailSection("系统要求", icon: "desktopcomputer") {
                    if let requirements = game.pcRequirements {
                        requirement("Windows", requirements)
                    }
                    if let requirements = game.macRequirements {
                        requirement("macOS", requirements)
                    }
                    if let requirements = crossOverRequirements(for: game) {
                        requirement("Wine · macOS", requirements)
                    }
                    if let requirements = game.linuxRequirements {
                        requirement("Linux", requirements)
                    }
                }
            }
        }
    }

    private func information(for game: Game) -> some View {
        Group {
            detailSection("Mac 兼容性", icon: "desktopcomputer") {
                if let bottle = game.installedBottleURL {
                    LabeledContent("容器", value: bottle.lastPathComponent)
                        .help(bottle.path)
                }
                if game.isDirectNativeApplication {
                    NativeAppLaunchSettingsView(game: $game)
                } else if game.supportsCrossOverCompatibility {
                    Picker("Wine 兼容性", selection: Binding(
                        get: { compatibilityStore.profile(for: game).crossOverStatus },
                        set: { compatibilityStore.setCrossOverStatus($0, for: game) }
                    )) {
                        ForEach(CrossOverCompatibility.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    if compatibilityStore.profile(for: game).crossOverStatus == .supported {
                        DisclosureGroup("兼容性与系统要求") {
                            GameCompatibilityEditor(game: game)
                        }
                    }
                    if BundledRuntimePolicy.needsReconfiguration(game) {
                        Text(BundledRuntimePolicy.retiredMessage)
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            if !game.releaseDate.date.isEmpty || !(game.genres ?? []).isEmpty
                || !game.categories.isEmpty || game.isFree == true {
                detailSection("项目信息", icon: "info.circle") {
                    if !game.releaseDate.date.isEmpty {
                        Text(L10n.format("Release date: %@", game.releaseDate.date))
                    }
                    if game.isFree == true { Text(L10n.string("Free to Play")) }
                    if !game.requiredAge.isEmpty && game.requiredAge != "0" {
                        Text(L10n.format("Age: %@+", game.requiredAge))
                    }
                    HFlow {
                        ForEach(game.genres ?? [], id: \.id) { Tag($0.description) }
                        ForEach(game.categories, id: \.id) { Tag($0.description) }
                    }
                }
            }
            let languages = SteamTextFormatter.supportedLanguages(fromHTML: game.supportedLanguages ?? "")
            if !languages.isEmpty {
                detailSection("支持语言", icon: "globe") {
                    Text(languages.joined(separator: "、")).foregroundStyle(.secondary)
                }
            }
            if let support = game.supportInfo {
                detailSection("支持", icon: "questionmark.circle") {
                    if let value = support.url, let url = URL(string: value),
                       ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        Link("访问官方网站", destination: url)
                    }
                    if let email = support.email, !email.isEmpty {
                        Text(email).font(.caption).textSelection(.enabled)
                    }
                }
            }
            if let notice = game.legalNotice, !notice.isEmpty {
                Text(SteamTextFormatter.plainText(fromHTML: notice))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func media(for game: Game) -> some View {
        if let screenshots = game.screenshots, !screenshots.isEmpty {
            detailSection("游戏截图", icon: "photo.on.rectangle") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230))], spacing: 12) {
                    ForEach(screenshots, id: \.id) { screenshot in
                        KFImage(URL(string: screenshot.pathThumbnail))
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        if let movies = game.movies, !movies.isEmpty {
            detailSection("视频", icon: "play.rectangle") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230))], spacing: 12) {
                    ForEach(movies, id: \.id) { movie in
                        Button {
                            selectedMovieURL = movie.hlsH264.flatMap(URL.init(string:))
                        } label: {
                            KFImage(URL(string: movie.thumbnail))
                                .resizable().scaledToFit()
                                .overlay {
                                    Image(systemName: "play.circle.fill")
                                        .font(.largeTitle)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(movie.hlsH264.flatMap(URL.init(string:)) == nil)
                        .accessibilityLabel("播放视频")
                    }
                }
            }
        }
    }

    private func detailSection<Content: View>(
        _ title: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func requirement(_ title: String, _ requirements: Requirements) -> some View {
        DisclosureGroup(title) {
            RequirementsWidget(requirements: requirements)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
    }

    private func crossOverRequirements(for game: Game) -> Requirements? {
        guard game.supportsCrossOverCompatibility,
              compatibilityStore.profile(for: game).crossOverStatus == .supported,
              let value = compatibilityStore.profile(for: game).crossOverMacRequirements
        else { return nil }
        return Requirements(
            minimum: value.minimum.isEmpty ? nil : value.minimum,
            recommended: value.recommended.isEmpty ? nil : value.recommended
        )
    }
}

/// A failed or missing cover uses the application's icon, never a large broken-image placeholder.
struct GameDetailArtwork: View {
    let game: Game
    var size: CGFloat = 64
    @State private var icon: NSImage?
    @State private var failed = false

    private var coverURL: URL? {
        let value = game.headerImage.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : URL(string: value)
    }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else if let coverURL, !failed {
                KFImage(coverURL)
                    .placeholder { fallback }
                    .onFailure { _ in failed = true }
                    .resizable().scaledToFit()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: game.appExeURL) {
            icon = nil
            if game.isNative, let url = game.appExeURL {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            } else if let executable = GameRemovalService.target(for: game) {
                let data = await WindowsExecutableIconCache.shared.load(executable)
                guard !Task.isCancelled else { return }
                icon = data.flatMap(NSImage.init(data:))
            }
        }
        .onChange(of: game.headerImage) { _, _ in failed = false }
    }

    private var fallback: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: game.isNative ? "app.dashed" : "app")
                    .resizable().scaledToFit().padding(12)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
    }
}
    

private struct GameDetailPoster: View {
    let urlString: String
    @Binding var failed: Bool

    var body: some View {
        if let url = URL(string: urlString), !failed {
            GeometryReader { geometry in
                KFImage(url)
                        .placeholder { ProgressView() }
                        .onFailure { _ in failed = true }
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                        .clipped()
            }
            .frame(height: 300)
            .accessibilityLabel("项目海报")
        }
    }
}
    
