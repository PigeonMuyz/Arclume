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
            switch ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_SCENARIO"] {
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
        .frame(width: 1024, height: 750)
        .overlay(alignment: .bottomTrailing) {
            Text("隔离测试").font(.caption).accessibilityIdentifier("arclume-test-isolated")
        }
    }
}
#endif
