//
//  NativeAppRuntimeStoreTests.swift
//  ProcyonTests
//

import Testing

@testable import Arclume

struct NativeAppRuntimeStoreTests {
    @Test @MainActor
    func terminationOnlyClearsTheSessionWithTheMatchingPID() {
        let store = NativeAppRuntimeStore()
        store.registerSession(
            gameID: "game-a",
            processIdentifier: 41_001,
            bundleIdentifier: "example.game.a"
        )
        store.registerSession(
            gameID: "game-b",
            processIdentifier: 41_002,
            bundleIdentifier: "example.game.b"
        )

        store.finish(processIdentifier: 99_999)
        #expect(store.isRunning(gameID: "game-a"))
        #expect(store.isRunning(gameID: "game-b"))

        store.finish(processIdentifier: 41_001)
        #expect(!store.isActive(gameID: "game-a"))
        #expect(store.isRunning(gameID: "game-b"))
    }

    @Test @MainActor
    func terminatedLaunchNeverBecomesRunning() {
        let store = NativeAppRuntimeStore()

        store.registerSession(
            gameID: "short-lived",
            processIdentifier: 42_001,
            bundleIdentifier: nil,
            isTerminated: true
        )

        #expect(!store.isActive(gameID: "short-lived"))
        #expect(store.sessions["short-lived"] == nil)
    }
}
