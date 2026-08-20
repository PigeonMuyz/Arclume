//
//  ProcyonApp.swift
//  Procyon
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI
import CoreData
import AppKit

let appName = "procyon"
let windowWidth: CGFloat = 1024
let windowHeight: CGFloat = 750
let appWindowResizable: Bool = {
    let env = ProcessInfo.processInfo.environment["PROCYON_LAYOUT_RESIZABLE"]?.lowercased()
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
struct ProcyonApp: App {
    @StateObject private var appSettings: AppSettings

    init() {
        migrateLegacyProcyonForkDefaultsIfNeeded()
        migrateUnavailableConfiguredMetadataSourceIfNeeded()
        _appSettings = StateObject(wrappedValue: AppSettings())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: appWindowResizable ? nil : windowWidth, height: appWindowResizable ? nil : windowHeight)
                .environment(\.locale, appSettings.language.locale)
                .environmentObject(appSettings)
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
