//
//  ArclumeApp.swift
//  Arclume
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI
import CoreData
import AppKit

let appName = "arclume"
let windowWidth: CGFloat = 1024
let windowHeight: CGFloat = 750
let appWindowResizable: Bool = {
    let env = ProcessInfo.processInfo.environment["ARCLUME_LAYOUT_RESIZABLE"]?.lowercased()
    switch env {
    case "1", "true", "yes":
        return true
    case "0", "false", "no":
        return false
    default:
        return false
    }
}()
var api = SteamAPI()

@main
struct ArclumeApp: App {
    @NSApplicationDelegateAdaptor(ArclumeAppDelegate.self) private var appDelegate
    @StateObject private var appSettings: AppSettings
    @StateObject private var updateService: ArclumeUpdateService
    private let resetError: String?

    init() {
        var failure: String?
        if !ArclumeTestEnvironment.isTesting {
            do {
                try ArclumeResetService.performPendingReset()
                migrateLegacyProcyonDataIfNeeded()
                LegacyBottleDirectory.removeEmptyDirectory(in: ARCLUME_SUPPORT_FOLDER_URL)
                migrateLegacyDefaultsIfNeeded()
                migrateUnavailableConfiguredMetadataSourceIfNeeded()
            } catch {
                failure = error.localizedDescription
            }
        }
        resetError = failure
        _appSettings = StateObject(wrappedValue: AppSettings())
        _updateService = StateObject(wrappedValue: ArclumeUpdateService())
    }

    var body: some Scene {
        WindowGroup {
            appContent
                .environment(\.locale, appSettings.language.locale)
                .environmentObject(appSettings)
                .environmentObject(updateService)
                .onAppear {
                    // Disable "Show Tab Bar" globally
                    NSWindow.allowsAutomaticWindowTabbing = false
                    // UI tests and first launch can otherwise leave the
                    // window behind the test runner, making visible controls
                    // inaccessible even though they exist in the hierarchy.
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: windowWidth, height: windowHeight)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { } // replaces "New Window" with nothing
        }
    }
    @ViewBuilder
    private var appContent: some View {
        if let resetError {
            VStack(spacing: 16) {
                Text("重置尚未完成").font(.title2)
                Text(resetError)
                Text("本次未加载游戏库。请按上方错误处理后重新打开 Arclume，程序会继续完成重置；已移入废纸篓的数据仍可恢复。")
                    .fixedSize(horizontal: false, vertical: true)
                Button("退出") { NSApp.terminate(nil) }
            }.padding(32).frame(width: 580)
        } else {
        #if DEBUG
        if ArclumeTestEnvironment.isUIFixture {
            ArclumeUITestRootView()
        } else if ArclumeTestEnvironment.isTesting {
            Text("Arclume Core Tests")
        } else {
            UnifiedContainerGate { ContentView() }
        }
        #else
        UnifiedContainerGate { ContentView() }
        #endif
        }
    }

}
