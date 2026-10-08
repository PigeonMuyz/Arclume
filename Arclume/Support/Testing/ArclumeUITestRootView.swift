#if DEBUG
import SwiftUI

/// Uses production views with inert data; never creates a Wine prefix or runs an installer.
struct ArclumeUITestRootView: View {
    @State private var mode: ArclumeMode?
    @State private var game: Game? = {
        var value = Game.emptyGame
        value.id = "arclume-ui-fixture"
        value.name = "Arclume Fixture"
        value.isNative = false
        return value
    }()
    @StateObject private var options = GameOptions()
    @StateObject private var appGlobals = AppGlobals(selectedBottle: "", cxAppPath: nil)

    var body: some View {
        Group {
            if ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_SCENARIO"] == "migration-gallery" {
                MigrationPreviewGallery()
            } else {
                fixtureContent
            }
        }
    }

    private var fixtureContent: some View {
        Group {
            switch ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_SCENARIO"] {
            case "announcement-reader":
                LauncherAnnouncementFixture()
            case "live-tour", "resource-upgrade", "resource-retry":
                LauncherLiveTourFixture()
            case "launch-hit-area":
                LaunchHitAreaFixture()
            case "library-welcome":
                if mode != nil {
                    Text("引导完成").accessibilityIdentifier("welcome-fixture-complete")
                } else {
                    LibraryWelcomeView { _, _ in mode = .standard }
                }
            case "wine-warmup":
                WineWarmupOption()
                    .padding(24)
                    .frame(width: 500, alignment: .leading)
            case "onboarding":
                if let mode {
                    Text(mode.rawValue).accessibilityIdentifier("fixture-selected-mode")
                } else {
                    ModeSelectionView { mode = $0 }
                }
            case "graphics":
                GameOptionsView(game: $game)
                    .environmentObject(options)
                    .environmentObject(appGlobals)
            default:
                ContentView()
            }
        }
        .frame(width: isTourScenario ? 1280 : 1024, height: isTourScenario ? 720 : 750)
        .overlay(alignment: .bottomTrailing) {
            Text("隔离测试").font(.caption).accessibilityIdentifier("arclume-test-isolated")
        }
    }
    private var isTourScenario: Bool {
        ["live-tour", "resource-upgrade", "resource-retry", "announcement-reader"].contains(ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_SCENARIO"] ?? "")
    }
}

/// Exercises the production control without launching or stopping a real game.
private struct LaunchHitAreaFixture: View {
    @State private var count = 0
    @State private var details = false
    @State private var game: Game? = {
        var game = Game.emptyGame
        game.id = "launch-hit-area"
        game.name = "点击区域测试"
        game.isInstalled = true
        game.downloadProgress = 100
        return game
    }()
    @StateObject private var library = LibraryPageGlobals()
    @StateObject private var globals = AppGlobals(selectedBottle: "", cxAppPath: nil)
    @StateObject private var options = GameOptions()
    @StateObject private var compatibility = GameCompatibilityStore()
    @StateObject private var nativeRuntime = NativeAppRuntimeStore()
    var body: some View {
        VStack(spacing: 30) {
            Text("点击次数：\(count)").accessibilityIdentifier("launch-hit-count")
            GameHeader(game: $game, showDetailView: $details, launcherStyle: true,
                       onLauncherStart: { count += 1 }, onLauncherStop: { count += 1 })
                .frame(width: 600)
            Toggle("禁用按钮", isOn: $library.isLaunchingGame)
                .frame(width: 200)
        }
        .environmentObject(library).environmentObject(globals).environmentObject(options)
        .environmentObject(compatibility).environmentObject(nativeRuntime)
    }
}

private struct LauncherLiveTourFixture: View {
    @StateObject private var registry = LauncherTourRegistry()
    @StateObject private var library = LibraryPageGlobals()
    @StateObject private var globals = AppGlobals(selectedBottle: "", cxAppPath: nil)
    @StateObject private var compatibility = GameCompatibilityStore()
    @StateObject private var nativeRuntime = NativeAppRuntimeStore()
    @State private var active = ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_SCENARIO"] == "live-tour"
    @State private var completed = false
    @State private var setup: (steam: Bool, jx3: Bool)? = {
        let scenario = ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_SCENARIO"]
        guard scenario == "resource-upgrade" || scenario == "resource-retry" else { return nil }
        return (steam: true, jx3: true)
    }()
    @StateObject private var steam = ContainerSteamStore()
    @StateObject private var installer = WindowsInstallerStore()
    @StateObject private var resources: DownloadableResourceStore = {
        let store = DownloadableResourceStore()
        let scenario = ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_SCENARIO"]
        store.demonstrationStatus = ResourceSetupStatus(
            runtime: scenario == "live-tour" ? .missing : .update(installed: "1.0.0"),
            targetVersion: "1.1.2", missingComponents: ["D3DMetal", "字体", "兼容组件"],
            componentCount: 7, downloadBytes: 420_000_000, catalogAvailable: true, noticeID: "fixture")
        store.demonstrationFailsOnce = scenario == "resource-retry"
        return store
    }()
    var body: some View {
        LauncherTourDemoView()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {} label: { Image(systemName: "plus") }.launcherTourTarget(.add)
                    Button {} label: { Image(systemName: "gearshape") }.launcherTourTarget(.settings)
                }
            }
            .environment(\.launcherTour, registry)
            .environmentObject(library).environmentObject(globals)
            .environmentObject(compatibility).environmentObject(nativeRuntime)
            .background(LauncherTourPresenter(active: active, registry: registry) { steam, jx3 in
                active = false
                setup = (steam, jx3)
            })
            .overlay {
                if let setup {
                    OnboardingSetupFlow(steam: setup.steam, jx3: setup.jx3, resourceStore: resources, demonstrationOnly: true) {
                        self.setup = nil; completed = true
                    }
                        .environmentObject(globals).environmentObject(library)
                        .environmentObject(steam).environmentObject(installer)
                } else if completed {
                    OnboardingStage(title: "引导流程已完成", showsBrand: true) {
                        Text("隔离演示结束，未下载组件或修改真实游戏环境。")
                            .accessibilityIdentifier("onboarding-fixture-complete")
                    } actions: {
                        Spacer()
                        Button("重新演示") { completed = false; active = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
    }
}
#endif
