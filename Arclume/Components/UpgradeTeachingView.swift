import SwiftUI

/// Teaching before migration must not load a real library or adopt prefix settings.
struct UpgradeTeachingView: View {
    @StateObject private var registry = LauncherTourRegistry()
    @StateObject private var library = LibraryPageGlobals(loadSavedLibrary: false)
    @StateObject private var globals = AppGlobals(demonstrationOnly: true)
    @StateObject private var compatibility = GameCompatibilityStore()
    @StateObject private var nativeRuntime = NativeAppRuntimeStore()
    let onFinish: () -> Void

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
            .background(LauncherTourPresenter(active: true, registry: registry,
                onFinish: { _, _ in onFinish() }, offersSetup: false))
    }
}
