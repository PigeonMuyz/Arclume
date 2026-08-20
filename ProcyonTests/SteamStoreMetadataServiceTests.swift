//
//  SteamStoreMetadataServiceTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Procyon

struct SteamStoreMetadataServiceTests {
    @Test @MainActor
    func directStoreEnvelopeDecodesFlexibleFields() throws {
        let encodedGame = try JSONEncoder().encode(Game.steamMock)
        var game = try #require(
            JSONSerialization.jsonObject(with: encodedGame) as? [String: Any]
        )
        game["required_age"] = 18
        game["pc_requirements"] = []
        if var packageGroups = game["package_groups"] as? [[String: Any]],
           !packageGroups.isEmpty {
            packageGroups[0]["display_type"] = 0
            game["package_groups"] = packageGroups
        }
        let response: [String: Any] = [
            "720": [
                "success": true,
                "data": game,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: response)

        let decodedGame = try SteamStoreAppDetailsDecoder.decodeGame(
            from: data,
            appID: "720"
        )
        let decoded = try #require(decodedGame)

        #expect(decoded.steamAppID == 720)
        #expect(decoded.name == "Mock Game")
        #expect(decoded.requiredAge == "18")
        #expect(decoded.pcRequirements == nil)
        #expect(decoded.packageGroups?.first?.displayType == "0")
    }

    @Test func unsuccessfulStoreEnvelopeReturnsNil() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "42": ["success": false],
        ])

        let decoded = try SteamStoreAppDetailsDecoder.decodeGame(
            from: data,
            appID: "42"
        )

        #expect(decoded == nil)
    }

    @Test @MainActor
    func unavailableConfiguredServiceFallsBackToDirectStore() {
        #expect(
            resolvedSteamMetadataSource(
                storedValue: SteamMetadataSource.configuredService.rawValue,
                configuredServiceAvailable: false
            ) == .steamStore
        )
        #expect(
            resolvedSteamMetadataSource(
                storedValue: SteamMetadataSource.configuredService.rawValue,
                configuredServiceAvailable: true
            ) == .configuredService
        )
    }
}
