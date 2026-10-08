//
//  ArclumeModeTests.swift
//  ArclumeTests
//

import Foundation
import Testing

@testable import Arclume

struct ArclumeModeTests {
    @Test @MainActor
    func modeStoreRequiresAnExplicitFirstLaunchChoice() {
        let defaults = UserDefaults(suiteName: "ArclumeModeTests.\(UUID().uuidString)")!
        let store = ArclumeModeStore(defaults: defaults)

        #expect(store.selectedMode == nil)
    }

    @Test @MainActor
    func modeStorePersistsAndReloadsTheSelectedMode() {
        let defaults = UserDefaults(suiteName: "ArclumeModeTests.\(UUID().uuidString)")!
        let store = ArclumeModeStore(defaults: defaults)

        store.select(.jx3)

        #expect(store.selectedMode == .jx3)
        #expect(defaults.string(forKey: ArclumeMode.defaultsKey) == ArclumeMode.jx3.rawValue)

        let reloadedStore = ArclumeModeStore(defaults: defaults)
        #expect(reloadedStore.selectedMode == .jx3)
    }
}
