//
//  GameOptionsDataTests.swift
//  ArclumeTests
//

import Foundation
import Testing

@testable import Arclume

struct GameOptionsDataTests {
    @Test func partialAutoConfigOnlyChangesReturnedValues() throws {
        let response = try JSONDecoder().decode(
            GameOptionsDataResponse.self,
            from: Data(
                #"{"data":{"cxGraphicsBackend":"d3dmetal4","d3dMtl4Enabled":true}}"#.utf8
            )
        )
        let options = GameOptions(
            cxGraphicsBackend: "dxvk",
            wineMSync: false,
            mtlHudEnabled: true,
            d3dMtl4Enabled: false,
            vulkanLib: "experimental"
        )

        options.importAutoConfig(data: response.data)

        #expect(options.cxGraphicsBackend == "d3dmetal4")
        #expect(options.d3dMtl4Enabled)
        #expect(!options.wineMSync)
        #expect(options.mtlHudEnabled)
        #expect(options.vulkanLib == "experimental")
    }

    @Test func partialSavedOptionsUseCurrentDefaultsForMissingValues() throws {
        let data = try JSONDecoder().decode(
            GameOptionsData.self,
            from: Data(#"{"mtlHudEnabled":true}"#.utf8)
        )
        let options = GameOptions(
            cxGraphicsBackend: "dxvk",
            wineMSync: false,
            vulkanLib: "experimental"
        )

        options.set(data: data)

        #expect(options.cxGraphicsBackend == "d3dmetal4")
        #expect(options.d3dMtl4Enabled)
        #expect(options.wineMSync)
        #expect(options.mtlHudEnabled)
        #expect(options.vulkanLib == "latest")
    }

    @MainActor
    @Test func savingJX3TogglesPreservesOtherSavedOptions() throws {
        let suite = "ArclumeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "GameOptions-JX3"
        defaults.set(Data(#"{"cxGraphicsBackend":"dxmt","gameArguments":"-example"}"#.utf8), forKey: key)

        GameOptionsPersistence.update(key: key, defaults: defaults) { $0.jx3SkipLauncher = true }
        GameOptionsPersistence.update(key: key, defaults: defaults) { $0.mtlHudEnabled = true }

        let data = try #require(defaults.data(forKey: key))
        let options = try JSONDecoder().decode(GameOptionsData.self, from: data)
        #expect(options.jx3SkipLauncher == true)
        #expect(options.mtlHudEnabled == true)
        #expect(options.cxGraphicsBackend == "dxmt")
        #expect(options.gameArguments == "-example")
    }

    @MainActor
    @Test func refreshingOptionsUsesDefaultsForAnUnconfiguredGame() throws {
        let suite = "ArclumeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let options = GameOptions()

        GameOptionsPersistence.update(key: "GameOptions.First", defaults: defaults) {
            $0.wineMSync = false
            $0.gameArguments = "-example"
        }
        options.set(data: GameOptionsPersistence.read(key: "GameOptions.First", defaults: defaults))
        #expect(!options.wineMSync)
        #expect(options.gameArguments == "-example")

        options.set(data: GameOptionsPersistence.read(key: "GameOptions.Second", defaults: defaults))
        #expect(options.wineMSync)
        #expect(options.gameArguments.isEmpty)
        #expect(defaults.data(forKey: "GameOptions.Second") == nil)
    }
}
