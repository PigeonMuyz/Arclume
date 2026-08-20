//
//  GameOptionsDataTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Procyon

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

        #expect(options.cxGraphicsBackend == "d3dmetal")
        #expect(options.wineMSync)
        #expect(options.mtlHudEnabled)
        #expect(options.vulkanLib == "latest")
    }
}
