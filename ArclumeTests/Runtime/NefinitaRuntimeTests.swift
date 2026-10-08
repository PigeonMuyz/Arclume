import Foundation
import Testing
@testable import Arclume

@Suite(.serialized)
struct NefinitaRuntimeTests {
    @Test func oldPreferencesContinueUsingArclume() throws {
        let name = "NefinitaTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(WineRuntimeProvider.selected(in: defaults) == .arclume)
        defaults.set("unknown-provider", forKey: WineRuntimeProvider.defaultsKey)
        #expect(WineRuntimeProvider.selected(in: defaults) == .arclume)
        defaults.set("nefinita", forKey: WineRuntimeProvider.defaultsKey)
        #expect(WineRuntimeProvider.selected(in: defaults) == .nefinita)
    }

    @Test func providersShareOnePrefixAndSelectionChangesOnlyTheEngine() throws {
        let name = "NefinitaTests.shared-prefix-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let root = URL(fileURLWithPath: "/tmp/isolated-nefinita-\(UUID().uuidString)")
        let old = WineRuntimeProvider.arclume.prefixURL(root: root)
        let new = WineRuntimeProvider.nefinita.prefixURL(root: root)
        #expect(old.lastPathComponent == "ALBottles")
        #expect(old == new)
        #expect(WineRuntimeProvider.provider(for: old, root: root, defaults: defaults) == .arclume)
        defaults.set("nefinita", forKey: WineRuntimeProvider.defaultsKey)
        #expect(WineRuntimeProvider.provider(for: old, root: root, defaults: defaults) == .nefinita)
        #expect(WineRuntimeProvider.provider(for: new.appendingPathComponent("child"), root: root, defaults: defaults) == nil)
        #expect(WineRuntimeProvider.provider(for: root.appendingPathComponent("CrossOver"), root: root, defaults: defaults) == nil)
        #expect(WineRuntimeProvider.provider(for: root.appendingPathComponent("NefinitaBottles"), root: root, defaults: defaults) == nil)
    }

    @Test func switchingBothWaysPreservesContainerAndCancelsQueuedLaunches() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nefinita-switch-\(UUID().uuidString)")
        let name = "NefinitaTests.switch-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name); try? fm.removeItem(at: root) }
        let prefix = WineRuntimeProvider.arclume.prefixURL(root: root)
        let game = prefix.appendingPathComponent("drive_c/Games/Example/save.dat")
        try fm.createDirectory(at: game.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unchanged save".utf8).write(to: game)
        defaults.set(prefix.absoluteString, forKey: "selectedBottle")
        defaults.set(game.path, forKey: "gamePath")
        for provider in [WineRuntimeProvider.nefinita, .arclume] {
            let ticket = try ArclumeWineStopService.launchTicket()
            try WineRuntimeProvider.commitSelection(provider, in: defaults, runtimeReady: { true }, processesIdle: {
                #expect(ArclumeWineStopService.isStopping)
                return true
            })
            #expect(throws: CancellationError.self) { try ArclumeWineStopService.withLaunchTicket(ticket) {} }
            #expect(!ArclumeWineStopService.isStopping)
            #expect(WineRuntimeProvider.provider(for: prefix, root: root, defaults: defaults) == provider)
            #expect(defaults.string(forKey: "selectedBottle") == prefix.absoluteString)
            #expect(defaults.string(forKey: "gamePath") == game.path)
            #expect(try Data(contentsOf: game) == Data("unchanged save".utf8))
            #expect(try fm.contentsOfDirectory(atPath: root.path) == ["ALBottles"])
        }
    }

    @Test func unavailableRuntimeOrRunningProcessesDoNotChangeSelection() throws {
        let name = "NefinitaTests.failed-switch-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(throws: NefinitaBuildError.self) {
            try WineRuntimeProvider.commitSelection(.nefinita, in: defaults, runtimeReady: { false }, processesIdle: { true })
        }
        #expect(defaults.object(forKey: WineRuntimeProvider.defaultsKey) == nil)
        #expect(throws: ResourceDownloadError.self) {
            try WineRuntimeProvider.commitSelection(.nefinita, in: defaults, runtimeReady: { true }, processesIdle: { false })
        }
        #expect(defaults.object(forKey: WineRuntimeProvider.defaultsKey) == nil)
        #expect(!ArclumeWineStopService.isStopping)
    }

    @Test func bundledRecipePinsAllExecutableInputs() throws {
        let recipe = try NefinitaBuildRecipe.load()
        #expect(recipe.provider == "Nefinita")
        #expect(recipe.files.count == 13)
        #expect(recipe.files["script/build-runtime.sh"] != nil)
        #expect(recipe.files["runtime.env"] != nil)
        #expect(recipe.files["sources/DEPENDENCIES.lock"] != nil)
        #expect(recipe.files.values.allSatisfy { $0.count == 64 })
    }

    @Test func modifiedSourceAndSymlinksAreRejectedBeforeExecution() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nefinita-input-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let env = root.appendingPathComponent("runtime.env")
        try "locked".write(to: env, atomically: true, encoding: .utf8)
        let recipe = NefinitaBuildRecipe(schemaVersion: 1, provider: "Nefinita", revision: NefinitaRuntime.revision,
            version: NefinitaRuntime.version, files: ["runtime.env": try DownloadedResourceFiles.hash(env)])
        #expect(try recipe.validateSource(root) == root)
        try "changed".write(to: env, atomically: true, encoding: .utf8)
        #expect(throws: NefinitaBuildError.self) { try recipe.validateSource(root) }
        try fm.removeItem(at: env)
        let target = root.appendingPathComponent("target")
        try "locked".write(to: target, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: env, withDestinationURL: target)
        #expect(throws: NefinitaBuildError.self) { try recipe.validateSource(root) }
    }

    @Test func upstreamManifestKeepsItsOwnABIAndRejectsWrongArchitectures() throws {
        let json = """
        {"schemaVersion":1,"id":"dev.macgamestater.runtime.wine","version":"0.3.0",
         "runtimeABI":1,"prefixABI":"macgamestater-prefix-1","architecture":"x86_64",
         "win32":true,"peArchitectures":["i386","x86_64"],"minimumMacOS":"13.0",
         "engine":{"wineVersion":"11.0","crossOverSourceVersion":"26.3.0",
         "finewineRevision":"e5d4ccad235eefe32d912733e57e4c0bb53a5b58"}}
        """
        let valid = try JSONDecoder().decode(NefinitaRuntime.Manifest.self, from: Data(json.utf8))
        try valid.validate()
        for invalid in [json.replacingOccurrences(of: "macgamestater-prefix-1", with: "arclume-jx3-prefix-1"),
                        json.replacingOccurrences(of: "\"architecture\":\"x86_64\"", with: "\"architecture\":\"arm64\""),
                        json.replacingOccurrences(of: "\"win32\":true", with: "\"win32\":false")] {
            let manifest = try JSONDecoder().decode(NefinitaRuntime.Manifest.self, from: Data(invalid.utf8))
            #expect(throws: NefinitaBuildError.self) { try manifest.validate() }
        }
    }

    @Test func buildEnvironmentDoesNotPassCredentialsOrWinePrefix() {
        let environment = NefinitaBuildService.environment
        #expect(environment["GH_TOKEN"] == nil)
        #expect(environment["GITHUB_TOKEN"] == nil)
        #expect(environment["WINEPREFIX"] == nil)
        #expect(environment["WINE_SIGN_IDENTITY"] == "-")
        #expect(Int(environment["JOBS"] ?? "0")! <= 4)
    }

    @Test @MainActor func nefinitaDoesNotDownloadArclumeOrUnrelatedMediaComponents() {
        let store = DownloadableResourceStore(nefinitaReady: { false })
        store.selectedProvider = .nefinita
        #expect(store.requiredIDs(for: .runtime).isEmpty)
        #expect(store.requiredIDs(for: .steam).contains("fonts"))
        #expect(!store.components.contains { $0.type == "runtime" || $0.id == "gstreamer" || $0.id == "dxmt" })
        #expect(store.preparationTitle == "编译 Nefinita")
    }
}
