//
//  GameView.swift
//  Procyon
//
//  Created by Italo Mandara on 31/01/2026.
//

import SwiftUI
import Kingfisher
import Flow
import AVKit

struct GameDetailView: View {
    @Binding var game: Game?
    @State private var player = AVPlayer()
    @State private var isMuted: Bool = true
    
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject private var compatibilityStore: GameCompatibilityStore
    @StateObject var gameOptions = GameOptions()
    var gameFolder: String {
        let meta = getMeta(libraryPageGlobals.gamesMeta, byID: String(game!.id))!
        return meta.libraryFolder.appendingPathComponent(meta.installdir).path(percentEncoded: false)
    }

    private var crossOverMacRequirements: Requirements? {
        guard
            let game,
            game.supportsCrossOverCompatibility,
            compatibilityStore.profile(for: game).crossOverStatus == .supported,
            let requirements = compatibilityStore.profile(for: game)
                .crossOverMacRequirements
        else {
            return nil
        }

        return Requirements(
            minimum: requirements.minimum.isEmpty ? nil : requirements.minimum,
            recommended: requirements.recommended.isEmpty ? nil : requirements.recommended
        )
    }
    
    var body: some View {
        if (game != nil) {
            VStack (alignment: .leading) {
                ZStack(alignment: .bottom ) {
                    if (game!.movies != nil && !game!.movies!.isEmpty) {
                        PlayerLayerView(player: player)
                            .ignoresSafeArea()
                            .frame(height: 540)
                            .position(x: 460, y: 260)
                            .onAppear {
                                let url = URL(string: game!.movies![0].hlsH264!)!
                                player = AVPlayer(url: url)
                                player.isMuted = true
                                player.play()
                            }
                            .onDisappear {
                                player.pause()
                            }
                    } else {
                        GameDetailHeaderImage(
                            headerImage: game!.headerImage,
                            title: game!.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? L10n.string("Untitled Game")
                                : game!.name
                        )
                    }
                    GameHeader(game: $game, showDetailView: $libraryPageGlobals.showDetailView)
                        .padding(30)
                        .padding(.top, 40)
                        .background(
                            LinearGradient(
                                colors: [
                                    .black.opacity(0),
                                    .black.opacity(0.8),
                                    .black.opacity(1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(.bottom, game!.movies != nil ? 20 : 0)
                }
                VStack (alignment: .leading) {
                    HStack (alignment: .top){
                        VStack(alignment: .leading) {
                            let detailedDescription = SteamTextFormatter.plainText(
                                fromHTML: game!.detailedDescription
                            )
                            if !detailedDescription.isEmpty {
                                Text(detailedDescription).padding(.bottom)
                            }
                            
                            if(game!.contentDescriptors?.notes != nil){
                                Text(game!.contentDescriptors!.notes!).padding(.bottom)
                            }
                            
                            if(game!.pcRequirements != nil){
                                VStack(alignment: .leading) {
                                    Text(L10n.string("PC Requirements:")).font(.title3).padding(.bottom, 5)
                                    RequirementsWidget(requirements: game!.pcRequirements)
                                }.padding(.bottom)
                            }
                            if(game!.macRequirements != nil){
                                VStack(alignment: .leading) {
                                    Text(L10n.string("Mac Requirements:")).font(.title3).padding(.bottom, 5)
                                    RequirementsWidget(requirements:game!.macRequirements)
                                }.padding(.bottom)
                            }
                            if let crossOverMacRequirements {
                                VStack(alignment: .leading) {
                                    Text(L10n.string("CrossOver macOS Requirements:"))
                                        .font(.title3)
                                        .padding(.bottom, 5)
                                    RequirementsWidget(requirements: crossOverMacRequirements)
                                }
                                .padding(.bottom)
                            }
                            if(game!.linuxRequirements != nil){
                                VStack(alignment: .leading) {
                                    Text(L10n.string("Linux Requirements:")).font(.title3).padding(.bottom, 5)
                                    RequirementsWidget(requirements:game!.linuxRequirements)
                                }.padding(.bottom)
                            }
                        }.padding(.bottom).padding(.trailing, 20)
                        Spacer()
                        VStack(alignment: .leading) {
                            if game!.isDirectNativeApplication {
                                NativeAppLaunchSettingsView(game: $game)
                                    .padding(.bottom)
                            } else {
                                GameCompatibilityEditor(game: game!)
                                    .padding(.bottom)
                            }

                            if !game!.releaseDate.date.isEmpty {
                                Text(L10n.format("Release date: %@", game!.releaseDate.date)).padding(.bottom)
                            }
                            
                            HStack{
                                if (game!.isFree == true){
                                    AccentTag(L10n.string("Free to Play")).padding(.bottom)
                                }
                                if (game!.requiredAge != "0"){
                                    AccentTag(
                                        L10n.format("Age: %@+", game!.requiredAge)
                                    )
                                    .padding(.bottom)
                                }
                            }
                            
                            if (game!.genres != nil && game!.genres!.count > 0){
                                Text(L10n.string("Genre:"))
                                HFlow(alignment: .center) {
                                    ForEach(game!.genres!, id: \.id) { genre in
                                        Tag(genre.description)
                                            .padding(.vertical, 0.5)
                                    }
                                }
                                .padding(.bottom)
                            }
                            
                            if (game!.categories.count > 0){
                                Text(L10n.string("Category:"))
                                HFlow(alignment: .center) {
                                    ForEach(game!.categories, id: \.id) { category in
                                        Tag(category.description)
                                            .padding(.vertical, 0.5)
                                    }
                                }
                                .padding(.bottom)
                            }
                            
                            let languages = SteamTextFormatter.supportedLanguages(
                                fromHTML: game!.supportedLanguages ?? ""
                            )

                            if !languages.isEmpty {
                                Text(L10n.string("Supported languages:"))
                                HFlow(alignment: .center) {
                                    ForEach(Array(languages.enumerated()), id: \.offset) { pair in
                                        AccentTag(pair.element)
                                            .padding(.vertical, 0.5)
                                    }
                                }.padding(.bottom)
                            }
                            
                            if(game!.legalNotice != nil){
                                Text(game!.legalNotice!).font(.footnote).padding(.bottom, 5)
                            }
                            if(game!.supportInfo != nil) {
                                VStack(alignment: .leading) {
                                    Text(L10n.string("Support:")).padding(.bottom, 2)
                                    if(game!.supportInfo!.url != nil && !game!.supportInfo!.url!.isEmpty){
                                        Text(L10n.format("Website: %@", game!.supportInfo!.url!)).font(Font.footnote.italic()).padding(.bottom, 2)
                                    }
                                    if(game!.supportInfo!.email != nil && !game!.supportInfo!.email!.isEmpty){
                                        Text(L10n.format("Email: %@", game!.supportInfo!.email!)).font(Font.footnote.italic()).padding(.bottom, 2)
                                    }
                                }.padding(.bottom, 5)
                            }
                        }.frame(width: 200)
                    }
                    
                    VStack (alignment: .leading) {
                        if(game!.screenshots != nil && game!.screenshots!.count > 0) {
                            Text(L10n.string("Screenshots:")).font(.title2).padding(.top)
                            LazyVGrid(columns: [
                                GridItem(.flexible(maximum: .infinity)),
                                GridItem(.flexible(maximum: .infinity)),
                                GridItem(.flexible(maximum: .infinity))
                            ]) {
                                ForEach(game!.screenshots!, id: \.id) { screenshot in
                                    KFImage(URL(string: screenshot.pathThumbnail))
                                        .placeholder {
                                            ProgressView()
                                        }
                                        .resizable()
                                        .scaledToFit()
                                    //                                    .frame(width: 180, height: 100)
                                }
                            }
                        }
                        
                        if (game!.movies != nil) {
                            Text(L10n.string("Videos:")).font(.title2).padding(.top)
                            LazyVGrid(columns: [
                                GridItem(.flexible(maximum: .infinity)),
                                GridItem(.flexible(maximum: .infinity)),
                                GridItem(.flexible(maximum: .infinity))
                            ]) {
                                ForEach(game!.movies!, id: \.id) { movie in
                                    KFImage(URL(string: movie.thumbnail))
                                        .placeholder {
                                            ProgressView()
                                        }
                                        .resizable()
                                        .scaledToFit()
                                    //                                    .frame(width: 180, height: 100)
                                }
                            }
                            
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, game!.movies == nil ? 30: -5)
                .padding(.bottom, 30)
            }
            .background(.procyonAccent.mix(with: .black, by: 0.6).opacity(0.9))
            .frame(width: windowWidth - 100)
            .environmentObject(gameOptions)
        }
    }
}

private struct GameDetailHeaderImage: View {
    let headerImage: String
    let title: String

    @State private var didLoad = false
    @State private var didFail = false
    @State private var timedOut = false

    private var imageURL: URL? {
        let value = headerImage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return URL(string: value)
    }

    private var shouldShowFallback: Bool {
        imageURL == nil || didFail || timedOut
    }

    var body: some View {
        Group {
            if shouldShowFallback {
                ZStack {
                    LinearGradient(
                        colors: [
                            .procyonAccent.mix(with: .black, by: 0.45),
                            .procyonAccent.mix(with: .black, by: 0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(32)
                }
            } else {
                KFImage(imageURL)
                    .placeholder {
                        ZStack {
                            Rectangle()
                                .fill(.procyonAccent.mix(with: .black, by: 0.6))
                            ProgressView()
                        }
                    }
                    .onSuccess { _ in
                        didLoad = true
                    }
                    .onFailure { _ in
                        didFail = true
                    }
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 540)
        .task(id: headerImage) {
            didLoad = false
            didFail = imageURL == nil
            timedOut = false

            guard imageURL != nil else { return }
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                guard !didLoad, !didFail else { return }
                timedOut = true
            } catch {
                // The detail view disappeared or its image URL changed.
            }
        }
    }
}

#Preview {
    @State @Previewable var game: Game? = .mock
    @State @Previewable var showDetailView: Bool = true
    
    ZStack (alignment: .topTrailing) {
        ScrollView {
            GameDetailView(game: $game)
        }
    }
}
    
