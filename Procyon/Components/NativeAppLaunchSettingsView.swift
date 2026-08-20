//
//  NativeAppLaunchSettingsView.swift
//  Procyon
//

import SwiftUI

struct NativeAppLaunchSettingsView: View {
    @Binding var game: Game?
    @State private var metalHUDEnabled = false

    private var gameOptionsKey: String {
        let id = game?.steamAppID ?? 0
        let persistentID = id != 0 ? String(id) : (game?.id ?? "")
        return namespacedKey("GameOptions", persistentID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Native App Settings"))
                .font(.title3)
            Toggle(L10n.string("Metal HUD"), isOn: $metalHUDEnabled)
                .toggleStyle(.switch)
                .help(L10n.string("Show Metal performance HUD while this native app runs."))
            Text(L10n.string("Show Metal performance HUD while this native app runs."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if let data: GameOptionsData = readUsrDefData(key: gameOptionsKey) {
                metalHUDEnabled = data.mtlHudEnabled ?? false
            }
        }
        .onChange(of: metalHUDEnabled) { _, enabled in
            var data: GameOptionsData = readUsrDefData(key: gameOptionsKey)
                ?? GameOptionsData(data: GameOptions())
            data.mtlHudEnabled = enabled
            persistUsrDefData(key: gameOptionsKey, data: data)
        }
    }
}
