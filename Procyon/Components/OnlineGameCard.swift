//
//  OnlineGameCard.swift
//  Procyon
//

import SwiftUI
import Kingfisher

private struct OnlineGamePosterFallback: View {
    var body: some View {
        LinearGradient(
            colors: [
                .procyonAccent.mix(with: .black, by: 0.56),
                .procyonAccent.mix(with: .black, by: 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.42))
        }
    }
}

struct GameCardPresentationEditor: View {
    let game: Game
    @Binding var isPresented: Bool
    let onSave: (OnlineGamePresentation) -> Void

    @State private var title: String
    @State private var artworks: [OnlineGameArtwork]
    @State private var selectedArtworkID: UUID?
    @State private var logoURLString: String?
    @State private var errorMessage: String?

    private var isJX3: Bool {
        game.id == OnlineGameMode.jx3GameID
    }

    private var editorTitle: String {
        isJX3 ? "编辑剑网3卡片" : "编辑卡片"
    }

    init(
        game: Game,
        isPresented: Binding<Bool>,
        onSave: @escaping (OnlineGamePresentation) -> Void
    ) {
        self.game = game
        self._isPresented = isPresented
        self.onSave = onSave
        let presentation = OnlineGamePresentationStore.presentation(for: game.id)
        self._title = State(initialValue: presentation.title ?? game.name)
        var initialArtworks = presentation.artworks
        var initialSelectedArtworkID = presentation.selectedArtworkID
        let existingArtworkURL = game.headerImage.trimmingCharacters(in: .whitespacesAndNewlines)
        if initialArtworks.isEmpty, !existingArtworkURL.isEmpty {
            let artwork = OnlineGameArtwork(id: UUID(), urlString: existingArtworkURL)
            initialArtworks = [artwork]
            initialSelectedArtworkID = artwork.id
        }
        self._artworks = State(initialValue: initialArtworks)
        self._selectedArtworkID = State(initialValue: initialSelectedArtworkID)
        self._logoURLString = State(initialValue: presentation.logoURLString)
    }

    private var artworkURL: URL? {
        let selectedArtwork = artworks.first(where: { $0.id == selectedArtworkID })
            ?? artworks.first
        return selectedArtwork.flatMap { URL(string: $0.urlString) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editorTitle)
                .font(.title2.weight(.semibold))

            ZStack {
                if let artworkURL {
                    KFImage(artworkURL)
                        .resizable()
                        .scaledToFill()
                } else {
                    OnlineGamePosterFallback()
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            TextField("游戏标题", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                if let logoURLString, let logoURL = URL(string: logoURLString) {
                    KFImage(logoURL)
                        .placeholder {
                            Image(systemName: "seal")
                                .foregroundStyle(.secondary)
                        }
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 150, maxHeight: 42)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Label("未设置卡片徽标", systemImage: "seal")
                        .foregroundStyle(.secondary)
                }

                Button("添加徽标…") {
                    chooseLogo()
                }
                if logoURLString != nil {
                    Button("删除徽标", role: .destructive) {
                        logoURLString = nil
                    }
                }
            }

            if !artworks.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(artworks) { artwork in
                            Button {
                                selectedArtworkID = artwork.id
                            } label: {
                                KFImage(URL(string: artwork.urlString))
                                    .placeholder {
                                        OnlineGamePosterFallback()
                                    }
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 64)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(
                                                selectedArtworkID == artwork.id
                                                    ? Color.procyonSecondary
                                                    : .white.opacity(0.28),
                                                lineWidth: selectedArtworkID == artwork.id ? 3 : 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .help("设为卡片海报")
                        }
                    }
                }
                .frame(height: 72)
            }

            HStack {
                Button("添加海报或截图…") {
                    chooseArtwork()
                }
                if let selectedArtworkID {
                    Button("删除所选图片", role: .destructive) {
                        artworks.removeAll { $0.id == selectedArtworkID }
                        self.selectedArtworkID = artworks.first?.id
                    }
                }
                if !artworks.isEmpty {
                    Button("清除全部图片", role: .destructive) {
                        artworks = []
                        selectedArtworkID = nil
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(L10n.string("Cancel")) {
                    isPresented = false
                }
                Button(L10n.string("Save")) {
                    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let presentation = OnlineGamePresentation(
                        title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                        artworks: artworks,
                        selectedArtworkID: selectedArtworkID,
                        logoURLString: logoURLString
                    )
                    OnlineGamePresentationStore.save(presentation, for: game.id)
                    onSave(presentation)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func chooseArtwork() {
        let sourceURLs = OnlineGamePresentationStore.chooseArtworkSources()
        guard !sourceURLs.isEmpty else { return }
        var lastImportedArtwork: OnlineGameArtwork?
        do {
            for sourceURL in sourceURLs {
                let artwork = OnlineGameArtwork(
                    id: UUID(),
                    urlString: try OnlineGamePresentationStore.importArtwork(
                        from: sourceURL,
                        for: game.id
                    )
                )
                artworks.append(artwork)
                lastImportedArtwork = artwork
            }
            selectedArtworkID = lastImportedArtwork?.id
            errorMessage = nil
        } catch {
            errorMessage = "无法导入此图片，请换一张图片后重试。"
        }
    }

    private func chooseLogo() {
        guard let sourceURL = OnlineGamePresentationStore.chooseLogoSource() else { return }
        do {
            logoURLString = try OnlineGamePresentationStore.importArtwork(
                from: sourceURL,
                for: "\(game.id)-logo"
            )
            errorMessage = nil
        } catch {
            errorMessage = "无法导入此徽标，请换一张图片后重试。"
        }
    }
}
