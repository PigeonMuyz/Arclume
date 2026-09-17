import SwiftUI
import Kingfisher
import Combine
import UniformTypeIdentifiers

/// Edits presentation only for installed projects. Launch identity is deliberately
/// absent from the draft, so metadata cannot move an application to another prefix.
struct ProjectEditorView: View {
    @Binding var isPresented: Bool
    let initialGame: Game?
    @EnvironmentObject private var library: LibraryPageGlobals
    @State private var showMetadata = false
    @State private var name = ""
    @State private var summary = ""
    @State private var background = ""
    @State private var logo = ""
    @State private var newExecutable: URL?
    @State private var provider = 0
    @State private var query = ""
    @State private var results: [GameDBSearchResult] = []
    @State private var preview: GameDBMetadata?
    @State private var steamPreview: SteamGame?
    @State private var previewSourceID: String?
    @State private var busy = false
    @State private var message: String?
    @State private var adoptedSource: ProjectPresentation.MetadataSource?

    var body: some View {
        Modal(initialGame == nil ? "添加项目" : "编辑项目信息", showModal: $isPresented, scrollable: false, subdued: true) {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 22) {
                        ProjectArtworkPreview(title: "背景", value: $background, fallback: automaticBackground)
                        ProjectArtworkPreview(title: "游戏标志", value: $logo, fallback: automaticLogo,
                                              fallbackImage: automaticLogoImage, logo: true)
                        Text("图片仅用于启动器外观。")
                            .font(.caption).foregroundStyle(.tertiary)
                    }.frame(width: 284)
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 14) {
                            if let game = initialGame { LauncherApplicationIcon(game: game, size: 52) }
                            else { Image(systemName: "app.dashed").font(.largeTitle).foregroundStyle(.secondary) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name.isEmpty ? "新项目" : name).font(.title2.weight(.semibold)).lineLimit(2)
                                Text(initialGame?.isNative == true ? "macOS 应用" : "Windows 应用")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.bottom, 4)
                        basics
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("游戏资料").font(.subheadline.weight(.medium))
                                Text(initialGame.flatMap { GamePresentationProfiles.profile(for: $0) } != nil ? "已使用官方适配" : "从资料库补全名称与简介")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("匹配资料…") { showMetadata = true }
                                .popover(isPresented: $showMetadata) {
                                    ScrollView { metadata.padding(22) }
                                        .frame(width: 410, height: initialGame.flatMap { GamePresentationProfiles.profile(for: $0) } != nil ? 140 : 410)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: .infinity, alignment: .top)
                Divider()
                HStack(spacing: 10) {
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer()
                    Button("取消") { isPresented = false }.buttonStyle(.glass)
                    Button("保存", action: save).buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (initialGame == nil && newExecutable == nil))
                }.controlSize(.large)
            }.padding(6).frame(width: 740, height: 464)
        }
        .onAppear {
            guard let game = initialGame else { return }
            name = game.name; summary = game.shortDescription
            let edited = ProjectPresentationStore.read()[game.id]
            background = edited?.background ?? OnlineGamePresentationStore.presentation(for: game.id).selectedArtworkURLString ?? ""
            logo = edited?.logo ?? OnlineGamePresentationStore.presentation(for: game.id).logoURLString ?? ""
            query = game.name
        }
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("名称").font(.subheadline.weight(.medium))
            TextField("项目名称", text: $name).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("project-editor.name")
            Text("简介").font(.subheadline.weight(.medium)).padding(.top, 4)
            TextField("添加简短介绍", text: $summary, axis: .vertical)
                .lineLimit(4...5).textFieldStyle(.roundedBorder)
            if initialGame == nil {
                Button(newExecutable?.lastPathComponent ?? "选择应用或 Windows 程序…") {
                    if let url = openFolderSelectorPanel(type: .executable) {
                        newExecutable = url
                        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                    }
                }.buttonStyle(.glass)
            } else if let path = initialGame?.appExeURL?.path {
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).help(path)
            }
        }
    }

    private var automaticBackground: URL? {
        guard let game = initialGame else { return nil }
        if OnlineGameMode.isJX3(game) { return JX3LauncherArtworkStore.cached()?.backgroundURL }
        let unedited = library.games.first { $0.id == game.id }
            ?? library.customAddedGames.first { $0.id == game.id } ?? game
        return [unedited.backgroundRaw, unedited.screenshots?.first?.pathFull, unedited.headerImage]
            .compactMap { $0 }.first(where: { !$0.isEmpty }).flatMap(URL.init(string:))
    }
    private var automaticLogo: URL? {
        guard let game = initialGame else { return nil }
        if OnlineGameMode.isJX3(game) { return JX3LauncherArtworkStore.cached()?.logoURL }
        if let logo = GamePresentationProfiles.profile(for: game)?.logoURL { return URL(string: logo) }
        let id = game.steamMetadataLink?.appID ?? game.steamAppID
        return id > 0 ? URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(id)/logo.png") : nil
    }

    private var automaticLogoImage: NSImage? {
        guard let game = initialGame, OnlineGameMode.isJX3(game),
              let data = JX3LauncherArtworkStore.cached()?.logoData else { return nil }
        return NSImage(data: data)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let game = initialGame, GamePresentationProfiles.profile(for: game) != nil {
                Label("内置适配 · 官方启动器资料", systemImage: "checkmark.seal")
                Text("背景与资讯由适配配置提供。你仍可自定义名称和图片。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("来源", selection: $provider) {
                    Text("GameDB / IGDB").tag(0)
                    Text("Steam 商店").tag(1)
                }.disabled(busy).onChange(of: provider) { _, _ in preview = nil; steamPreview = nil; results = []; query = "" }
                HStack {
                    TextField(provider == 0 ? "游戏名称（支持英文原名）" : "Steam App ID 或商店链接", text: $query)
                        .textFieldStyle(.roundedBorder).onSubmit(search)
                    Button("查询", action: search).disabled(busy || query.isEmpty)
                }
                Text("优先获取当前应用语言的资料。先预览再采用，不改变本地运行配置。")
                    .font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView().controlSize(.small) }
                ForEach(results) { result in
                    Button(result.name) { loadDetails(result.id) }.buttonStyle(.borderless).disabled(busy)
                }
                if preview != nil || steamPreview != nil {
                    Divider()
                    Text(steamPreview?.name ?? preview?.preferredName ?? "").font(.headline)
                    Text(steamPreview?.shortDescription ?? preview?.preferredSummary ?? "暂无简介")
                        .font(.callout).lineLimit(5)
                    Button("采用这份资料") {
                        name = steamPreview?.name ?? preview?.preferredName ?? name
                        summary = steamPreview?.shortDescription ?? preview?.preferredSummary ?? summary
                        background = steamPreview?.screenshots?.first?.pathFull
                            ?? preview?.screenshots?.first.flatMap { GameDBMetadataService.artworkURL($0, size: "t_screenshot_big") } ?? background
                        message = "已填入草稿，点击保存后生效。"
                        if let previewSourceID { adoptedSource = ProjectPresentation.MetadataSource(
                            provider: provider == 0 ? "gamedb" : "steam",
                            id: previewSourceID,
                            language: GameMetadataLanguage.current.steamStoreLanguage) }
                        showMetadata = false
                    }.buttonStyle(.glass).disabled(busy)
                }
                Link("资料来源：GameDB / IGDB", destination: URL(string: "https://github.com/LizardByte/GameDB")!)
                    .font(.caption)
            }
        }
    }

    private func search() {
        guard !busy, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; message = nil; results = []; preview = nil; steamPreview = nil
        let input = query; let source = provider
        Task {
            defer { busy = false }
            do {
                if source == 0 {
                    results = try await GameDBMetadataService.shared.search(input)
                    if results.isEmpty { message = "没有找到结果，可尝试英文原名或 Steam 商店链接。" }
                } else {
                    guard let id = SteamMetadataLinkParser.appID(from: input) else { message = "请输入有效的 Steam App ID 或商店链接。"; return }
                    steamPreview = try await api.fetchGameInfo(appID: String(id), forceRefresh: true, source: .steamStore)
                    previewSourceID = String(id)
                    if steamPreview == nil { message = "没有找到对应资料。" }
                }
            } catch { message = error.localizedDescription }
        }
    }

    private func loadDetails(_ id: Int) {
        busy = true; message = nil
        Task {
            defer { busy = false }
            do { preview = try await GameDBMetadataService.shared.details(id: id); previewSourceID = String(id) }
            catch { message = error.localizedDescription }
        }
    }

    private func save() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for value in [background, logo] where !value.isEmpty {
            guard let url = URL(string: value), ["https", "http", "file"].contains(url.scheme?.lowercased() ?? "") else {
                message = "图片地址必须为 http、https 或本地文件。"; return
            }
        }
        var game = initialGame ?? .emptyGame
        if initialGame == nil, let url = newExecutable {
            game.id = UUID().uuidString; game.appExeURL = url; game.name = title; game.isCustom = true
            let native = NativeApplicationBundleDetector.application(at: url)
            game.isNative = native != nil; game.nativeAppBundleIdentifier = native?.bundleIdentifier
            game.appNames = native?.processNames ?? [url.lastPathComponent]
            game.isInstalled = true; game.downloadProgress = 100
            if !game.isNative {
                game.installedBottleURL = BundledWineRuntime.standardSteamPrefixURL
                game.installedRuntimeKind = StandardGameRuntimeKind.bundledWine.rawValue
                do { try GameAdaptationRules.validate(url, bottle: BundledWineRuntime.standardSteamPrefixURL) }
                catch { message = error.localizedDescription; return }
            }
            library.customAddedGames.append(game); library.saveCustomAddedGames()
        }
        let prior = ProjectPresentationStore.read()[game.id]
        ProjectPresentationStore.save(ProjectPresentation(
            name: title == initialGame?.name ? prior?.name : title,
            summary: summary == initialGame?.shortDescription ? prior?.summary : summary,
            background: background,
            logo: logo,
            metadataSource: adoptedSource ?? prior?.metadataSource), for: game.id)
        library.objectWillChange.send()
        isPresented = false
    }
}
