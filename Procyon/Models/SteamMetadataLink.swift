//
//  SteamMetadataLink.swift
//  Procyon
//

import Foundation

nonisolated enum SteamMetadataField: String, Codable, CaseIterable, Hashable, Sendable {
    case descriptions
    case artwork
    case media
    case developers
    case publishers
    case genres
    case categories
    case controllerSupport

    var title: String {
        switch self {
        case .descriptions:
            return L10n.string("Descriptions")
        case .artwork:
            return L10n.string("Artwork")
        case .media:
            return L10n.string("Screenshots and videos")
        case .developers:
            return L10n.string("Developers")
        case .publishers:
            return L10n.string("Publishers")
        case .genres:
            return L10n.string("Genres")
        case .categories:
            return L10n.string("Categories")
        case .controllerSupport:
            return L10n.string("Controller support")
        }
    }

    static let defaultSelection: Set<Self> = Set(allCases)
}

nonisolated struct SteamMetadataLink: Codable, Equatable, Sendable {
    var appID: Int
    var confirmedStoreName: String
    var fields: Set<SteamMetadataField>
    var linkedAt: Date

    init(
        appID: Int,
        confirmedStoreName: String,
        fields: Set<SteamMetadataField> = SteamMetadataField.defaultSelection,
        linkedAt: Date = Date()
    ) {
        self.appID = appID
        self.confirmedStoreName = confirmedStoreName
        self.fields = fields
        self.linkedAt = linkedAt
    }
}

nonisolated enum SteamMetadataLinkParser {
    static func appID(from input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let appID = Int(trimmed), appID > 0 {
            return appID
        }

        guard let components = URLComponents(string: trimmed) else { return nil }

        if let queryAppID = components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("appid") == .orderedSame })?
            .value
            .flatMap(Int.init), queryAppID > 0 {
            return queryAppID
        }

        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)
        if let appIndex = pathComponents.firstIndex(where: {
            $0.caseInsensitiveCompare("app") == .orderedSame
        }), pathComponents.indices.contains(appIndex + 1),
           let appID = Int(pathComponents[appIndex + 1]), appID > 0 {
            return appID
        }

        if components.scheme?.caseInsensitiveCompare("steam") == .orderedSame,
           components.host?.caseInsensitiveCompare("store") == .orderedSame,
           let firstPathComponent = pathComponents.first,
           let appID = Int(firstPathComponent), appID > 0 {
            return appID
        }

        return nil
    }
}
