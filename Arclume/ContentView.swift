//
//  ContentView.swift
//  Procyon
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI
import Combine
import AppKit

enum AppRoute {
    case libraryPage
    case profilePage
}

final class Router: ObservableObject {
    @Published var route: AppRoute = .libraryPage

    // Convenience helpers if you like
    func go(to newRoute: AppRoute) {
        route = newRoute
    }
}

struct ContentView: View {
    @State private var compactHomeVisible = false
    @AppStorage("jx3CompactHome", store: UserDefaults(suiteName: suiteName))
    private var compactJX3Home = false
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var updateService: ArclumeUpdateService
    @StateObject private var router = Router()
    @StateObject private var modeStore = ArclumeModeStore()
    @StateObject private var appGlobals = AppGlobals(
        selectedBottle: readUsrDefOptionString(key: "selectedBottle"),
        cxAppPath: readUsrDefOptionString(key: "cxAppPath"),
    )
    @StateObject private var containerSteamStore = ContainerSteamStore()
    @StateObject private var nativeSteamStore = ArclumeTestEnvironment.nativeSteamStore()
    @StateObject private var compatibilityStore = GameCompatibilityStore()
    @StateObject private var nativeRuntimeStore = NativeAppRuntimeStore()

    var body: some View {
        Group {
            if modeStore.selectedMode?.isOnlineGameMode == true {
                routedContent
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                    .background {
                        OnlineTitlebarWindowConfigurator()
                    }
            } else {
                routedContent
            }
        }
        .animation(.easeInOut, value: router.route)
        .onPreferenceChange(JX3CompactHomePreferenceKey.self) { compactHomeVisible = $0 }
        .frame(
            width: appWindowResizable ? nil : (compactHomeVisible ? 720 : windowWidth),
            height: appWindowResizable ? nil : (compactHomeVisible ? 480 : windowHeight)
        )
        .preferredColorScheme(.dark)
        .environmentObject(router)
        .environmentObject(modeStore)
        .environmentObject(appGlobals)
        .environmentObject(containerSteamStore)
        .environmentObject(nativeSteamStore)
        .environmentObject(compatibilityStore)
        .environmentObject(nativeRuntimeStore)
        .background(
            ZStack {
                if compactJX3Home && modeStore.selectedMode?.isOnlineGameMode == true {
                    Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                } else {
                    LinearGradient(
                        colors: [
                            .arclumeAccent.mix(with: .black, by: modeStore.selectedMode?.isOnlineGameMode == true ? 0.60 : 0.2),
                            .arclumeAccent.mix(with: .black, by: modeStore.selectedMode?.isOnlineGameMode == true ? 0.78 : 0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ).ignoresSafeArea()
                }
            }
        )
        .onAppear {
            guard !ArclumeTestEnvironment.isTesting else { return }
            nativeRuntimeStore.reconcileRunningApplications()
        }
        .task {
            guard !ArclumeTestEnvironment.isTesting else { return }
            await updateService.checkForUpdatesAtLaunch()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && !ArclumeTestEnvironment.isTesting {
                nativeRuntimeStore.reconcileRunningApplications()
            }
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        if let selectedMode = modeStore.selectedMode {
            switch router.route {
            case .libraryPage:
                LibraryPage()
                    .id(selectedMode.rawValue)
            case .profilePage:
                Text(L10n.string("Profile Page"))
            }
        } else {
            ModeSelectionView { mode in
                modeStore.select(mode)
            }
        }
    }
}

/// Only a ready, embedded JX3 home may shrink the main window. Setup screens
/// and standard-mode game sheets retain their original window dimensions.
struct JX3CompactHomePreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Keeps the online-mode titlebar visually transparent while allowing AppKit
/// to retain the native trailing placement of SwiftUI toolbar items.
private struct OnlineTitlebarWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowConfiguratorView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowConfiguratorView)?.configureWindow()
    }

    private final class WindowConfiguratorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            guard let window else { return }

            // Keep the native title item in the toolbar layout so primary
            // actions remain trailing, while using an invisible title glyph.
            window.title = " "
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none

            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.title = " "
                window.titlebarAppearsTransparent = true
                window.titlebarSeparatorStyle = .none
            }
        }
    }
}

func fileURL(from value: String) -> URL {
    if let url = URL(string: value), url.isFileURL {
        return url
    }
    return URL(fileURLWithPath: value)
}

#Preview {
    ContentView()
}
