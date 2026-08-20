//
//  ArclumeToolbar.swift
//  Arclume
//
//  Created by Italo Mandara on 07/04/2026.
//

import SwiftUI

struct ArclumeToolbar: View {
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    
    let iconSize:CGFloat = 20
    var body: some View {
        HStack(alignment: .center) {
            Button {
                libraryPageGlobals.showOptions = true
            } label: {
                Image(systemName: "gear")
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            }
            .accessibilityIdentifier("library-settings-button")
            .help(L10n.string("Options"))
            if !OnlineGameMode.isEnabled {
                Divider()
                Button {
                    libraryPageGlobals.openCustomGameEditor()
                } label: {
                    Image(systemName: "rectangle.badge.plus").resizable().scaledToFit().frame(width: iconSize, height: iconSize)
                }
            }
            if appGlobals.cxAppPath != nil,
               (!OnlineGameMode.isEnabled
                    || OnlineGameRuntimeKind.selected() == .crossOver) {
                Divider()
                Button {
                    if let cxPath = appGlobals.cxAppPath {
                        let url = URL(fileURLWithPath: cxPath)
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.environment = [
                            "CX_GRAPHICS_BACKEND": "d3dmetal",
                            "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "0"
                        ]
                        NSWorkspace.shared.open(url, configuration: configuration)
                    }
                } label: {
                    Image("crossover-fill").resizable().scaledToFit().frame(width: iconSize, height: iconSize)
                }
            }
            if appGlobals.selectedBottle != "" {
                Divider()
                Button {
                    if let selectedBottleURL = URL(string: appGlobals.selectedBottle){
                        showFolder(url: selectedBottleURL)
                    }
                } label: {
                    Image(systemName: "waterbottle").resizable().scaledToFit().frame(width: iconSize, height: iconSize)
                }
            }
            Divider()
            Button {
                libraryPageGlobals.showTools = true
            } label: {
                Image(systemName: "wrench.adjustable.fill").resizable().scaledToFit().frame(width: iconSize, height: iconSize)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 15)
        .frame(height: 35)
        .background(.arclumeAccent.mix(with: .black, by: 0.6).opacity(0.9))
        .clipShape(.capsule)
    }
}
