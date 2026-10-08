import Foundation
import Testing
@testable import Arclume

@MainActor
struct WineWarmupTests {
    @Test func oneContainerNeedsNoSecondarySelection() {
        #expect(WineWarmupTarget.effectiveSelection(selected: [], available: [.steam]) == [.steam])
        #expect(WineWarmupTarget.effectiveSelection(selected: [.games], available: [.steam]) == [.steam])
        #expect(WineWarmupTarget.effectiveSelection(selected: [.steam], available: [.games]) == [.games])
    }

    @Test func multipleContainersPreserveExplicitSelection() {
        #expect(WineWarmupTarget.effectiveSelection(selected: [], available: [.steam, .games]).isEmpty)
        #expect(WineWarmupTarget.effectiveSelection(selected: [.games], available: [.steam, .games]) == [.games])
        #expect(WineWarmupTarget.effectiveSelection(selected: [.steam, .games], available: [.steam, .games]) == [.steam, .games])
        #expect(WineWarmupTarget.effectiveSelection(selected: [.steam, .games], available: []).isEmpty)
    }

    @Test func legacyAliasesDoNotCountAsMultipleContainers() {
        let unified = URL(fileURLWithPath: "/fixture/ALBottles")
        #expect(WineWarmupTarget.uniqueTargets(prefixes: [.steam: unified, .games: unified]) == [.steam])
        #expect(WineWarmupTarget.uniqueTargets(prefixes: [
            .steam: unified, .games: URL(fileURLWithPath: "/fixture/Games")
        ]) == [.steam, .games])
        #expect(WineWarmupTarget.uniqueTargets(prefixes: [:]).isEmpty)
    }

    @Test func multipleTargetsRoundTripAndRemoval() {
        var targets: Set<WineWarmupTarget> = [.steam, .games]
        #expect(WineWarmupTarget.decode(WineWarmupTarget.encode(targets)) == targets)
        targets.remove(.steam)
        #expect(WineWarmupTarget.decode(WineWarmupTarget.encode(targets)) == [.games])
        #expect(WineWarmupTarget.decode("[\"steam\",\"steam\",\"unknown\"]") == [.steam])
        #expect(WineWarmupTarget.decode("broken").isEmpty)
        #expect(WineWarmupTarget.decode("[]").isEmpty)
    }

    @Test func migratesOnlyExistingEnabledSelectionOnce() {
        let name = "WineWarmupTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: WineWarmupService.defaultsKey)
        WineWarmupService.migrateSelection(in: defaults, previousTarget: .games)
        #expect(WineWarmupTarget.decode(defaults.string(forKey: WineWarmupService.targetsKey)!) == [.games])
        WineWarmupService.migrateSelection(in: defaults, previousTarget: .steam)
        #expect(WineWarmupTarget.decode(defaults.string(forKey: WineWarmupService.targetsKey)!) == [.games])
        defaults.set("[]", forKey: WineWarmupService.targetsKey)
        WineWarmupService.migrateSelection(in: defaults, previousTarget: .steam)
        #expect(defaults.string(forKey: WineWarmupService.targetsKey) == "[]")
    }

    @Test func newUsersDoNotSelectContainersAutomatically() {
        let name = "WineWarmupTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        WineWarmupService.migrateSelection(in: defaults, previousTarget: .steam)
        #expect(defaults.string(forKey: WineWarmupService.targetsKey) == "[]")
        #expect(!defaults.bool(forKey: WineWarmupService.defaultsKey))
    }

    @Test func optInAndTestingGates() {
        #expect(!WineWarmupService.shouldStart(enabled: false, suspended: false, testing: false))
        #expect(!WineWarmupService.shouldStart(enabled: true, suspended: true, testing: false))
        #expect(!WineWarmupService.shouldStart(enabled: true, suspended: false, testing: true))
        #expect(WineWarmupService.shouldStart(enabled: true, suspended: false, testing: false))
        let name = "WineWarmupTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(!defaults.bool(forKey: WineWarmupService.defaultsKey))
    }

    @Test func bundledHelperIsVerified() throws {
        let helper = try #require(Bundle.main.url(forResource: "wine-keepalive", withExtension: "exe"))
        try WineWarmupService.verifyHelper(helper)
        #expect(throws: (any Error).self) { try WineWarmupService.verifyHelper(URL(fileURLWithPath: "/bin/sh")) }
    }

    @Test func closingLeaseReleasesOnlyItsChild() async throws {
        // Native fixture only: no Wine, user prefix, preference or game access.
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["20"]
        try unrelated.run()
        defer { if unrelated.isRunning { unrelated.terminate() } }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf 'ARCLUME_WINE_READY\\n'; /bin/cat >/dev/null"]
        var ready = false
        var exitCode: Int32?
        let lease = WineWarmupLease(process: process, onReady: {
            Task { @MainActor in ready = true }
        }, onExit: { code in
            Task { @MainActor in exitCode = code }
        })
        defer { lease.release() }
        try process.run()
        for _ in 0..<100 where !ready { try await Task.sleep(for: .milliseconds(20)) }
        #expect(ready)
        #expect(process.isRunning)
        lease.release()
        lease.release()
        for _ in 0..<100 where exitCode == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(exitCode == 0)
        #expect(!process.isRunning)
        #expect(unrelated.isRunning)
    }
}
