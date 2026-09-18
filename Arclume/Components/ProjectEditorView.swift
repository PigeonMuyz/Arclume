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
    private enum Pane: String, CaseIterable { case information = "项目信息", artwork = "外观图片", metadata = "匹配资料" }
    @State private var pane: Pane = .information
    @State private var selection = ProjectMetadataSelection()
    @State private var original: ProjectPresentation?
    @State private var showDiscardConfirmation = false
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
    @State private var appStoreResults: [AppStoreCatalogItem] = []
    @State private var appStorePreview: AppStoreCatalogItem?
    @State private var appStoreMacOnly = true
    @State private var storefront = GameMetadataLanguage.current.appleStorefront
    @State private var previewLogo: String?
    @State private var previewBackground: String?
    @State private var previewSourceID: String?
    @State private var busy = false
    @State private var message: String?
    @State private var adoptedSource: ProjectPresentation.MetadataSource?

    var body: some View {
        Modal(initialGame == nil ? "添加项目" : "编辑项目信息", showModal: $isPresented, scrollable: false,
              subdued: true, onClose: requestDismiss) {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 28) {
                    ProjectEditorPreview(game: initialGame, name: displayed.name ?? name,
                                         summary: displayed.summary ?? summary,
                                         backgroundURL: imageURL(displayed.background) ?? automaticBackground,
                                         logoURL: imageURL(displayed.logo) ?? automaticLogo,
                                         logoImage: imageURL(displayed.logo) == nil ? automaticLogoImage : nil)
                        .frame(width: 400)
                    VStack(alignment: .leading, spacing: 18) {
                        Picker("编辑内容", selection: $pane) {
                            ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                switch pane {
                                case .information:
                                    basics
                                    Divider()
                                    Label(sourceLabel, systemImage: "checkmark.seal")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Button("匹配游戏资料…") { message = nil; pane = .metadata }
                                        .buttonStyle(.glass)
                                case .artwork:
                                    ProjectArtworkPreview(title: "背景图片", value: $background, fallback: automaticBackground)
                                    ProjectArtworkPreview(title: "游戏标志", value: $logo, fallback: automaticLogo,
                                                          fallbackImage: automaticLogoImage, logo: true)
                                    Text("背景与标志独立设置；恢复自动后使用游戏原有资料。")
                                        .font(.caption).foregroundStyle(.secondary)
                                case .metadata: metadata
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
                        }
                    }.frame(width: 310, height: 448)
                }
                Divider()
                HStack(spacing: 10) {
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer()
                    if pane == .metadata {
                        Button("返回") { pane = .information }.buttonStyle(.glass)
                        Button("采用所选资料", action: adoptMetadata).buttonStyle(.glassProminent)
                            .disabled(busy || !hasCandidate || !(selection.text || selection.background || selection.logo))
                    } else {
                        Button("取消", action: requestDismiss).buttonStyle(.glass)
                        Button("保存", action: save).buttonStyle(.glassProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (initialGame == nil && newExecutable == nil))
                    }
                }.controlSize(.large)
            }.padding(6).frame(width: 738, height: 510)
        }
        .interactiveDismissDisabled(hasChanges || busy)
        .alert("放弃未保存的修改？", isPresented: $showDiscardConfirmation) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive) { isPresented = false }
        } message: { Text("已采用的资料和外观修改尚未保存。") }
        .onAppear {
            guard original == nil else { return }
            if let game = initialGame {
                name = game.name; summary = game.shortDescription
                let edited = ProjectPresentationStore.read()[game.id]
                background = edited?.background ?? OnlineGamePresentationStore.presentation(for: game.id).selectedArtworkURLString ?? ""
                logo = edited?.logo ?? OnlineGamePresentationStore.presentation(for: game.id).logoURLString ?? ""
                adoptedSource = edited?.metadataSource
                query = game.name
            }
            original = draft
        }
    }

    private var draft: ProjectPresentation {
        ProjectPresentation(name: name, summary: summary, background: background, logo: logo, metadataSource: adoptedSource)
    }
    private var hasChanges: Bool { original.map { $0 != draft } == true || newExecutable != nil }
    private var hasCandidate: Bool { preview != nil || steamPreview != nil || appStorePreview != nil }
    private var sourceLabel: String {
        if let game = initialGame, GamePresentationProfiles.profile(for: game) != nil { return "官方启动器适配" }
        switch adoptedSource?.provider {
        case "steam": return "Steam 商店资料"
        case "appstore": return "Apple App Store 资料"
        case "gamedb": return "GameDB / IGDB 资料"
        default: return "本地项目信息"
        }
    }
    private var candidate: ProjectPresentation {
        ProjectPresentation(
            name: appStorePreview?.trackName ?? steamPreview?.name ?? preview?.preferredName,
            summary: appStorePreview?.description ?? steamPreview?.shortDescription ?? preview?.preferredSummary,
            background: appStorePreview?.background ?? previewBackground ?? steamPreview?.screenshots?.first?.pathFull
                ?? preview?.screenshots?.first.flatMap { GameDBMetadataService.artworkURL($0, size: "t_screenshot_big") },
            logo: previewLogo,
            metadataSource: previewSourceID.map { .init(provider: provider == 0 ? "gamedb" : provider == 1 ? "steam" : "appstore",
                                                       id: $0, language: provider == 2 ? storefront : GameMetadataLanguage.current.steamStoreLanguage) })
    }
    private var displayed: ProjectPresentation {
        pane == .metadata && hasCandidate ? selection.applying(candidate, to: draft) : draft
    }
    private func imageURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        return URL(string: value)
    }
    private func requestDismiss() {
        if hasChanges { showDiscardConfirmation = true } else { isPresented = false }
    }
    private func adoptMetadata() {
        let adopted = selection.applying(candidate, to: draft)
        name = adopted.name ?? name; summary = adopted.summary ?? summary
        background = adopted.background ?? background; logo = adopted.logo ?? logo
        adoptedSource = adopted.metadataSource
        message = "已填入草稿，保存后生效。"; pane = .information
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
                    Text("App Store").tag(2)
                }.disabled(busy).onChange(of: provider) { _, _ in clearPreview(); results = []; appStoreResults = []; query = "" }
                if provider == 2 {
                    Picker("平台", selection: $appStoreMacOnly) {
                        Text("Mac").tag(true)
                        Text("iPhone / iPad").tag(false)
                    }.pickerStyle(.segmented).disabled(busy)
                        .onChange(of: appStoreMacOnly) { _, _ in clearPreview(); appStoreResults = [] }
                    Picker("商店地区", selection: $storefront) {
                        Text("中国大陆").tag("cn")
                        Text("美国").tag("us")
                    }.disabled(busy).onChange(of: storefront) { _, _ in clearPreview(); appStoreResults = [] }
                }
                HStack {
                    TextField(provider == 0 ? "游戏名称（支持英文原名）" : provider == 1 ? "Steam App ID 或商店链接" : "应用名称、App ID 或 App Store 链接", text: $query)
                        .textFieldStyle(.roundedBorder).onSubmit(search)
                    Button("查询", action: search).disabled(busy || query.isEmpty)
                }
                Text("优先获取当前应用语言的资料。先预览再采用，不改变本地运行配置。")
                    .font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView().controlSize(.small) }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                ForEach(results) { result in
                    Button(result.name) { loadDetails(result.id) }.buttonStyle(.borderless).disabled(busy)
                }
                ForEach(appStoreResults) { result in
                    Button {
                        appStorePreview = result; previewSourceID = String(result.id)
                    } label: {
                        HStack(spacing: 10) {
                            KFImage(result.iconURL).resizable().scaledToFit().frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.trackName).lineLimit(2)
                                Text("\(result.platformLabel) · \(result.artistName ?? "App Store")")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if appStorePreview?.id == result.id { Image(systemName: "checkmark") }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(busy)
                }
                if preview != nil || steamPreview != nil || appStorePreview != nil {
                    Divider()
                    Text(appStorePreview?.trackName ?? steamPreview?.name ?? preview?.preferredName ?? "").font(.headline)
                    if let previewLogo, let url = URL(string: previewLogo) {
                        KFImage(url).resizable().scaledToFit().frame(height: 64)
                    }
                    Text(appStorePreview?.description ?? steamPreview?.shortDescription ?? preview?.preferredSummary ?? "暂无简介")
                        .font(.callout).lineLimit(5)
                    if let item = appStorePreview {
                        Text("\(item.platformLabel) · \(storefront.uppercased()) 商店。仅采用展示资料，不更改运行平台。App Store 不提供透明游戏标志。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !busy && previewLogo == nil {
                        Text("未获取到游戏标志，将保留当前标志。").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("名称与简介", isOn: $selection.text)
                    Toggle("背景图片", isOn: $selection.background).disabled(candidate.background == nil)
                    Toggle("游戏标志", isOn: $selection.logo).disabled(candidate.logo == nil)
                    Text("未提供的图片会保留当前设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Link(provider == 0 ? "资料来源：GameDB / IGDB" : provider == 1 ? "资料来源：Steam" : "资料来源：Apple App Store",
                     destination: URL(string: provider == 0 ? "https://github.com/LizardByte/GameDB" : provider == 1 ? "https://store.steampowered.com" : "https://apps.apple.com")!)
                    .font(.caption)
            }
        }
    }

    private func search() {
        guard !busy, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; message = nil; results = []; appStoreResults = []; clearPreview()
        let input = query; let source = provider
        Task {
            defer { busy = false }
            do {
                if source == 0 {
                    results = try await GameDBMetadataService.shared.search(input)
                    if results.isEmpty { message = "没有找到结果，可尝试英文原名或 Steam 商店链接。" }
                } else if source == 1 {
                    guard let id = SteamMetadataLinkParser.appID(from: input) else { message = "请输入有效的 Steam App ID 或商店链接。"; return }
                    steamPreview = try await api.fetchGameInfo(appID: String(id), forceRefresh: true, source: .steamStore)
                    previewSourceID = String(id)
                    if steamPreview == nil { message = "没有找到对应资料。" }
                    else { await loadSteamArtwork(id) }
                } else {
                    appStoreResults = try await AppStoreCatalogService.shared.search(input, country: storefront, macOnly: appStoreMacOnly)
                    if appStoreResults.isEmpty { message = "当前地区没有结果，可切换商店地区或尝试 App Store 链接。" }
                }
            } catch { message = error.localizedDescription }
        }
    }

    private func loadDetails(_ id: Int) {
        busy = true; message = nil; clearPreview()
        Task {
            defer { busy = false }
            do {
                preview = try await GameDBMetadataService.shared.details(id: id); previewSourceID = String(id)
                if let raw = preview?.external_games?.first(where: { $0.external_game_source?.name == "Steam" })?.uid,
                   let steamID = Int(raw), steamID > 0 { await loadSteamArtwork(steamID) }
            }
            catch { message = error.localizedDescription }
        }
    }

    private func clearPreview() {
        preview = nil; steamPreview = nil; appStorePreview = nil
        previewSourceID = nil; previewLogo = nil; previewBackground = nil
    }

    private func loadSteamArtwork(_ id: Int) async {
        let artwork = await SteamProjectArtworkService.shared.artwork(appID: id)
        previewLogo = artwork.logo; previewBackground = artwork.background
    }

    private func save() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for value in [background, logo] {
            guard ProjectEditorValidation.imageAddress(value) else {
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
