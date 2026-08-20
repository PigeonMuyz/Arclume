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
    @StateObject private var appSettings: AppSettings
    @StateObject private var updateService: ArclumeUpdateService

    init() {
        migrateLegacyProcyonDataIfNeeded()
        migrateLegacyDefaultsIfNeeded()
        migrateUnavailableConfiguredMetadataSourceIfNeeded()
        _appSettings = StateObject(wrappedValue: AppSettings())
        _updateService = StateObject(wrappedValue: ArclumeUpdateService())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: appWindowResizable ? nil : windowWidth, height: appWindowResizable ? nil : windowHeight)
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
    
}
