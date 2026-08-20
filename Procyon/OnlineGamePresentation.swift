//
//  OnlineGamePresentation.swift
//  Procyon
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct OnlineGameArtwork: Codable, Identifiable, Equatable {
    let id: UUID
    let urlString: String
}

struct OnlineGamePresentation: Codable, Equatable {
    var title: String? = nil
    var artworks: [OnlineGameArtwork] = []
    var selectedArtworkID: UUID? = nil
    var logoURLString: String? = nil

    var selectedArtworkURLString: String? {
        if let selectedArtworkID,
           let selected = artworks.first(where: { $0.id == selectedArtworkID }) {
            return selected.urlString
        }
        return artworks.first?.urlString
    }

    enum CodingKeys: String, CodingKey {
        case title
        case artworks
        case selectedArtworkID
        case logoURLString
        // Import the single-image format written by the first preview build.
        case artworkURLString
    }

    init(
        title: String? = nil,
        artworks: [OnlineGameArtwork] = [],
        selectedArtworkID: UUID? = nil,
        logoURLString: String? = nil
    ) {
        self.title = title
        self.artworks = artworks
        self.selectedArtworkID = selectedArtworkID
        self.logoURLString = logoURLString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        artworks = try container.decodeIfPresent(
            [OnlineGameArtwork].self,
            forKey: .artworks
        ) ?? []
        selectedArtworkID = try container.decodeIfPresent(UUID.self, forKey: .selectedArtworkID)
        logoURLString = try container.decodeIfPresent(String.self, forKey: .logoURLString)

        if artworks.isEmpty,
           let legacyURL = try container.decodeIfPresent(String.self, forKey: .artworkURLString),
           !legacyURL.isEmpty {
            let artwork = OnlineGameArtwork(id: UUID(), urlString: legacyURL)
            artworks = [artwork]
            selectedArtworkID = artwork.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(artworks, forKey: .artworks)
        try container.encodeIfPresent(selectedArtworkID, forKey: .selectedArtworkID)
        try container.encodeIfPresent(logoURLString, forKey: .logoURLString)
    }
}

enum OnlineGamePresentationStore {
    private static let defaultsKey = "onlineGamePresentations.v1"

    static func presentation(for gameID: String) -> OnlineGamePresentation {
        guard
            let data = UserDefaults(suiteName: suiteName)?.data(forKey: defaultsKey),
            let presentations = try? JSONDecoder().decode(
                [String: OnlineGamePresentation].self,
                from: data
            )
        else {
            return OnlineGamePresentation()
        }
        return presentations[gameID] ?? OnlineGamePresentation()
    }

    static func save(_ presentation: OnlineGamePresentation, for gameID: String) {
        let defaults = UserDefaults(suiteName: suiteName)
        var presentations: [String: OnlineGamePresentation] = [:]
        if let data = defaults?.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(
               [String: OnlineGamePresentation].self,
               from: data
           ) {
            presentations = saved
        }
        presentations[gameID] = presentation
        guard let data = try? JSONEncoder().encode(presentations) else { return }
        defaults?.set(data, forKey: defaultsKey)
    }

    static func apply(_ presentation: OnlineGamePresentation, to game: inout Game) {
        if let title = presentation.title?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           !(game.id == OnlineGameMode.jx3GameID && title == "剑网3旗舰版") {
            game.name = title
        }
        game.headerImage = presentation.selectedArtworkURLString ?? ""
    }

    static func logoURL(for gameID: String) -> URL? {
        guard
            let logoURLString = presentation(for: gameID).logoURLString,
            !logoURLString.isEmpty
        else {
            return nil
        }
        return URL(string: logoURLString)
    }

    @MainActor
    static func chooseArtworkSources() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "选择卡片海报或截图"
        panel.message = "可选择一张或多张图片，之后可随时切换卡片海报。"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls : []
    }

    @MainActor
    static func chooseLogoSource() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择卡片徽标"
        panel.message = "徽标会显示在卡片标题位置。"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func importArtwork(from sourceURL: URL, for gameID: String) throws -> String {
        guard NSImage(contentsOf: sourceURL) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let artworkDirectory = PROCYON_SUPPORT_FOLDER_URL
            .appendingPathComponent("OnlineGameArtwork", isDirectory: true)
        try FileManager.default.createDirectory(
            at: artworkDirectory,
            withIntermediateDirectories: true
        )

        let fileExtension = sourceURL.pathExtension.isEmpty
            ? "png"
            : sourceURL.pathExtension.lowercased()
        let destinationURL = artworkDirectory
            .appendingPathComponent(gameID, isDirectory: false)
            .appendingPathExtension(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL.absoluteString
    }
}
