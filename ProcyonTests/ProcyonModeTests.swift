//
//  ProcyonModeTests.swift
//  ProcyonTests
//

import Foundation
import Testing

@testable import Procyon

struct ProcyonModeTests {
    @Test @MainActor
    func modeStoreRequiresAnExplicitFirstLaunchChoice() {
        let defaults = UserDefaults(suiteName: "ProcyonModeTests.\(UUID().uuidString)")!
        let store = ProcyonModeStore(defaults: defaults)

        #expect(store.selectedMode == nil)
    }

    @Test @MainActor
    func modeStorePersistsAndReloadsTheSelectedMode() {
        let defaults = UserDefaults(suiteName: "ProcyonModeTests.\(UUID().uuidString)")!
        let store = ProcyonModeStore(defaults: defaults)

        store.select(.jx3)

        #expect(store.selectedMode == .jx3)
        #expect(defaults.string(forKey: ProcyonMode.defaultsKey) == ProcyonMode.jx3.rawValue)

        let reloadedStore = ProcyonModeStore(defaults: defaults)
        #expect(reloadedStore.selectedMode == .jx3)
    }
}
