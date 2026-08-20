//
//  SteamMetadataResolver.swift
//  Procyon
//

import Foundation

nonisolated enum SteamMetadataResolver {
    static func resolvedGame(
        base: Game,
        metadata: SteamGame,
        link: SteamMetadataLink
    ) -> Game {
        guard link.appID == metadata.steamAppID else { return base }

        var resolved = base
        let fields = link.fields

        if fields.contains(.descriptions) {
            // The native bundle and executable remain the launch identity, but
            // the visible title belongs to the confirmed Steam metadata.
            resolved.name = metadata.name
            resolved.detailedDescription = metadata.detailedDescription
            resolved.aboutTheGame = metadata.aboutTheGame
            resolved.shortDescription = metadata.shortDescription
        }
        if fields.contains(.artwork), !metadata.headerImage.isEmpty {
            resolved.headerImage = metadata.headerImage
        }
        if fields.contains(.media) {
            resolved.screenshots = metadata.screenshots
            resolved.movies = metadata.movies
        }
        if fields.contains(.developers) {
            resolved.developers = metadata.developers ?? []
        }
        if fields.contains(.publishers) {
            resolved.publishers = metadata.publishers ?? []
        }
        if fields.contains(.genres) {
            resolved.genres = metadata.genres
        }
        if fields.contains(.categories) {
            resolved.categories = metadata.categories ?? []
        }
        if fields.contains(.controllerSupport) {
            resolved.controllerSupport = metadata.controllerSupport
        }

        return resolved
    }
}
