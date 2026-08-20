//
//  AddEditCustomGameView.swift
//  Procyon
//
//  Created by Italo Mandara on 18/03/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import Kingfisher

struct CustomGameView: View {
    @State private var text: String = ""
    @State private var game: Game = .emptyGame
    @State private var id: String = ""
    @State private var isAutofilling: Bool = false
    @State private var isRefreshingAppStoreMetadata = false
    @State private var metadataRefreshMessage: String?
    @State private var metadataImageAssets: [AppleAppStoreImageAsset] = []
    @State private var steamMetadataInput = ""
    @State private var steamMetadataFields = SteamMetadataField.defaultSelection
    @State private var steamMetadataPreview: SteamGame?
    @State private var isRefreshingSteamMetadata = false
    @State private var steamMetadataMessage: String?
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @Binding var isPresented: Bool

    init(isPresented: Binding<Bool>, initialGameID: String? = nil) {
        self._isPresented = isPresented
        self._id = State(initialValue: initialGameID ?? "")
    }
    
    var customGames: [Game] {
        libraryPageGlobals.customAddedGames.filter { $0.isCustom == true }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 20) {
//                VStack{
                    GameThumbnail(item: editorPreviewGame, isResizable: false)
//                }.frame(minWidth: 450)
                VStack(alignment: .leading, spacing: 15) {
                    Picker(L10n.string("Select a Game"), selection: $id) {
                        Text(L10n.string("New Game")).tag("")
                        ForEach(customGames, id: \.id) { game in
                            Text(game.name).tag(game.id)
                        }
                    }.onChange(of: id) { loadSelectedGame() }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("Game Title"))
                        TextField(L10n.string("Game Title"), text: $game.name)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("Header Image URL"))
                        TextField(L10n.string("Header Image URL"), text: $game.headerImage)
                    }
                    // Executable path
                    Button(game.appExeURL?.lastPathComponent ?? L10n.string("Select a Game App...")) {
                        if let url = openFolderSelectorPanel(type: .executable) {
                            configureGameApplication(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    HStack(spacing: 8) {
                        Button {
                            Task { await refreshAppStoreMetadata() }
                        } label: {
                            Label(
                                L10n.string("Refresh App Store Metadata"),
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .disabled(resolvedNativeBundleIdentifier == nil || isRefreshingAppStoreMetadata)

                        if isRefreshingAppStoreMetadata {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .help(L10n.string("Fills the editable fields with App Store metadata. Save the game to keep the changes."))
                    if let metadataRefreshMessage {
                        Text(metadataRefreshMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !metadataImageAssets.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.string("Metadata Image URLs"))
                            Text(L10n.string("Select a metadata image to fill the header image URL."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {
                                    ForEach(metadataImageAssets) { asset in
                                        Button {
                                            game.headerImage = asset.url
                                        } label: {
                                            VStack(spacing: 4) {
                                                KFImage(URL(string: asset.url))
                                                    .placeholder {
                                                        ProgressView()
                                                    }
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 84, height: 52)
                                                    .clipped()
                                                    .cornerRadius(6)
                                                Text(imageAssetLabel(asset))
                                                    .font(.caption2)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 84)
                                            .padding(4)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        game.headerImage == asset.url
                                                            ? Color.arclumeSecondary
                                                            : Color.secondary.opacity(0.35),
                                                        lineWidth: game.headerImage == asset.url ? 2 : 1
                                                    )
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .help(asset.url)
                                    }
                                }
                            }
                            .frame(height: 96)
                        }
                    }
                    if (AUTOFILL_CUSTOM_GAME_ENABLED && game.appExeURL != nil) {
                        HStack {
                            ProminentButton(L10n.string("Autofill data"), systemImage: "wand.and.sparkles") {
                                if let url = game.appExeURL {
                                    isAutofilling = true
                                    Task {
                                        let customGame = CustomGameAPI()
                                        let hint = url.path(percentEncoded: false)
                                        do {
                                            let fetchedGame = try await customGame.fetch(hints: hint)
                                            if fetchedGame != nil {
                                                game = fetchedGame!
                                            }
                                        } catch {
                                            print(error)
                                        }
                                        game.headerImage = "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(game.steamAppID)/header.jpg"
                                        configureGameApplication(url)
                                        isAutofilling = false
                                    }
                                }
                            }
                            if(isAutofilling){
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    Toggle(L10n.string("Is a Native Game"), isOn: $game.isNative)
                    VStack(alignment: .leading){
                        Text(L10n.string("Supported Platforms"))
                        HStack(spacing: 20) {
                            Toggle(isOn: $game.platforms.windows) {
                                Image("os-win")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 15)
                            }
                            Toggle(isOn: $game.platforms.mac) {
                                Image("os-apple")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 15)
                            }
                            Toggle(isOn: $game.platforms.linux) {
                                Image("os-linux")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 15)
                            }
                        }
                    }
                }
            }.frame(alignment: .top)
            if game.isDirectNativeApplication {
                SteamMetadataLinkEditor(
                    input: $steamMetadataInput,
                    selectedFields: $steamMetadataFields,
                    currentLink: game.steamMetadataLink,
                    preview: steamMetadataPreview,
                    isLoading: isRefreshingSteamMetadata,
                    message: steamMetadataMessage,
                    previewAction: {
                        Task { await refreshSteamMetadataPreview(forceRefresh: true) }
                    },
                    applyAction: applySteamMetadataLink,
                    unlinkAction: unlinkSteamMetadata
                )
                .onChange(of: steamMetadataInput) { _, newValue in
                    guard let preview = steamMetadataPreview,
                          SteamMetadataLinkParser.appID(from: newValue) != preview.steamAppID
                    else {
                        return
                    }
                    steamMetadataPreview = nil
                    steamMetadataMessage = L10n.string(
                        "Preview the new Steam App ID before updating the link."
                    )
                }
            }
            // Descriptions
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Detailed Description"))
                    TextField(L10n.string("Detailed Description"), text: $game.detailedDescription, axis: .vertical)
                        .lineLimit(9...11)
                }
                VStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("About The Game"))
                        TextField(L10n.string("About The Game"), text: $game.aboutTheGame, axis: .vertical)
                            .lineLimit(4...6)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("Short Description"))
                        TextField(L10n.string("Short Description"), text: $game.shortDescription, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
            }
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Developers"))
                    TextField(
                        L10n.string("Developers (comma-separated)"),
                        text: Binding(
                            get: { game.developers.joined(separator: ", ") },
                            set: { newValue in
                                game.developers = newValue
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            }
                        )
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Publishers"))
                    TextField(
                        L10n.string("Publishers (comma-separated)"),
                        text: Binding(
                            get: { game.publishers.joined(separator: ", ") },
                            set: { newValue in
                                game.publishers = newValue
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            }
                        )
                    )
                }
            }
            // Categories as comma-separated by description
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Categories"))
                    TextField(
                        L10n.string("Categories (comma-separated descriptions)"),
                        text: Binding(
                            get: { game.categories.map { $0.description }.joined(separator: ", ") },
                            set: { newValue in
                                let parts = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                var newCats: [Category] = []
                                for (idx, desc) in parts.enumerated() {
                                    if idx < game.categories.count {
                                        newCats.append(Category(id: game.categories[idx].id, description: desc))
                                    } else {
                                        newCats.append(Category(id: idx + 1, description: desc))
                                    }
                                }
                                game.categories = newCats
                            }
                        )
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Genres"))
                    TextField(
                        L10n.string("Genres (comma-separated descriptions)"),
                        text: Binding(
                            get: { game.genres?.map { $0.description }.joined(separator: ", ") ?? "" },
                            set: { newValue in
                                let parts = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                var newGenre: [Genre] = []
                                for (idx, desc) in parts.enumerated() {
                                    if game.genres != nil && idx < game.genres?.count ?? 0 {
                                        newGenre.append(Genre(id: game.genres![idx].id, description: desc))
                                    } else {
                                        newGenre.append(Genre(id: String(idx + 1), description: desc))
                                    }
                                }
                                game.genres = newGenre
                            }
                        )
                    )
                }
            }
            Group {
                if id != "" {
                    ProminentButton(L10n.string("Update game"), systemImage: "arrow.2.circlepath") {
                        libraryPageGlobals.updateCustomAddedGames(gameData: game)
                        Task { await refreshNativeMetadataSources() }
                        isPresented = false
                    }
                } else {
                    ProminentButton(L10n.string("Add game"), systemImage: "plus.circle") {
                        game.isCustom = true
                        libraryPageGlobals.customAddedGames.append(game)
                        libraryPageGlobals.saveCustomAddedGames()
                        Task { await refreshNativeMetadataSources() }
                        isPresented = false
                    }
                }
            }
        }
        .padding(.vertical)
        .frame(width: 700)
        .onAppear {
            loadSelectedGame()
        }
    }

    private func loadSelectedGame() {
        metadataImageAssets = []
        metadataRefreshMessage = nil
        if id != "", let currentGame = libraryPageGlobals.getCustomAddedGame(id: id) {
            game = currentGame
        } else if id.isEmpty {
            game = .emptyGame
        }
        loadSteamMetadataLinkState()
    }

    private func configureGameApplication(_ url: URL) {
        metadataImageAssets = []
        metadataRefreshMessage = nil
        game.appExeURL = url
        let nativeApplication = NativeApplicationBundleDetector.application(at: url)
        game.isNative = nativeApplication != nil
            || url.pathExtension.caseInsensitiveCompare("exe") != .orderedSame
        game.appNames = nativeApplication?.processNames ?? [url.lastPathComponent]
        game.nativeAppBundleIdentifier = nativeApplication?.bundleIdentifier

        guard id.isEmpty else { return }

        game.id = url.path(percentEncoded: false)
        if game.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            game.name = url.deletingPathExtension().lastPathComponent
        }
    }

    private var resolvedNativeBundleIdentifier: String? {
        guard game.isDirectNativeApplication else { return nil }
        return game.nativeAppBundleIdentifier
            ?? game.appExeURL.flatMap {
                NativeApplicationBundleDetector.application(at: $0)?.bundleIdentifier
            }
    }

    private var editorPreviewGame: Game {
        guard let preview = steamMetadataPreview else { return game }
        let previewLink = SteamMetadataLink(
            appID: preview.steamAppID,
            confirmedStoreName: preview.name,
            fields: steamMetadataFields,
            linkedAt: game.steamMetadataLink?.linkedAt ?? Date()
        )
        return SteamMetadataResolver.resolvedGame(
            base: game,
            metadata: preview,
            link: previewLink
        )
    }

    private func loadSteamMetadataLinkState() {
        steamMetadataPreview = nil
        steamMetadataMessage = nil
        guard let link = game.steamMetadataLink else {
            steamMetadataInput = ""
            steamMetadataFields = SteamMetadataField.defaultSelection
            return
        }

        steamMetadataInput = String(link.appID)
        steamMetadataFields = link.fields
        Task { await refreshSteamMetadataPreview(forceRefresh: false) }
    }

    @MainActor
    private func refreshSteamMetadataPreview(forceRefresh: Bool) async {
        guard let appID = SteamMetadataLinkParser.appID(from: steamMetadataInput) else {
            steamMetadataMessage = L10n.string("Enter a valid Steam App ID or Store URL.")
            steamMetadataPreview = nil
            return
        }

        isRefreshingSteamMetadata = true
        defer { isRefreshingSteamMetadata = false }
        do {
            guard let metadata = try await api.fetchGameInfo(
                appID: String(appID),
                forceRefresh: forceRefresh,
                source: .steamStore
            ) else {
                steamMetadataPreview = nil
                steamMetadataMessage = L10n.string("Steam did not return metadata for this app.")
                return
            }
            steamMetadataPreview = metadata
            steamMetadataInput = String(appID)
            steamMetadataMessage = L10n.format(
                "Previewing Steam metadata for %@. Confirm the link to keep it.",
                metadata.name
            )
        } catch {
            steamMetadataPreview = nil
            steamMetadataMessage = error.localizedDescription
        }
    }

    private func applySteamMetadataLink() {
        guard let preview = steamMetadataPreview, !steamMetadataFields.isEmpty else { return }
        game.steamMetadataLink = SteamMetadataLink(
            appID: preview.steamAppID,
            confirmedStoreName: preview.name,
            fields: steamMetadataFields,
            linkedAt: game.steamMetadataLink?.linkedAt ?? Date()
        )
        steamMetadataMessage = L10n.format(
            "Steam metadata link to %@ is ready. Save the game to apply it.",
            preview.name
        )
    }

    private func unlinkSteamMetadata() {
        game.steamMetadataLink = nil
        steamMetadataPreview = nil
        steamMetadataInput = ""
        steamMetadataFields = SteamMetadataField.defaultSelection
        steamMetadataMessage = L10n.string(
            "Steam metadata is unlinked. Save the game to restore local and App Store metadata."
        )
    }

    @MainActor
    private func refreshNativeMetadataSources() async {
        await libraryPageGlobals.refreshNativeAppStoreMetadata()
        await libraryPageGlobals.refreshNativeSteamMetadata()
    }

    @MainActor
    private func refreshAppStoreMetadata() async {
        guard let bundleIdentifier = resolvedNativeBundleIdentifier else {
            metadataRefreshMessage = L10n.string("Select a macOS app before fetching metadata.")
            return
        }

        isRefreshingAppStoreMetadata = true
        defer { isRefreshingAppStoreMetadata = false }

        guard let metadata = await AppleAppStoreMetadataService.shared.metadata(
            bundleIdentifier: bundleIdentifier,
            language: GameMetadataLanguage.current,
            includeProductPageMedia: true
        ) else {
            metadataRefreshMessage = L10n.string("No App Store metadata was found for this app.")
            return
        }

        game.nativeAppBundleIdentifier = bundleIdentifier
        game.detailedDescription = metadata.description
        game.aboutTheGame = metadata.description
        game.shortDescription = metadata.shortDescription
        if let developer = metadata.developer, !developer.isEmpty {
            game.developers = [developer]
        }
        if let publisher = metadata.publisher, !publisher.isEmpty {
            game.publishers = [publisher]
        }
        if let primaryGenre = metadata.primaryGenre, !primaryGenre.isEmpty {
            game.categories = [Category(id: 1, description: primaryGenre)]
        }
        if !metadata.genres.isEmpty {
            game.genres = metadata.genres.enumerated().map {
                Genre(id: String($0.offset + 1), description: $0.element)
            }
        }
        metadataImageAssets = metadata.imageAssets
        game.appStoreMetadataLanguage = GameMetadataLanguage.current.cacheKey
        metadataRefreshMessage = L10n.string(
            "Metadata is filled into the editor. Review the fields, then save the game to keep the changes."
        )
    }

    private func imageAssetLabel(_ asset: AppleAppStoreImageAsset) -> String {
        switch asset.kind {
        case .icon:
            return L10n.string("App Store Icon")
        case .screenshot:
            return L10n.string("App Store Screenshot")
        }
    }
}
