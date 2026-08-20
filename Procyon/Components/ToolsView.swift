//
//  ToolsView.swift
//  Procyon
//
//  Created by Italo Mandara on 06/07/2026.
//

import SwiftUI

struct ToolsView: View {
    @State var bottles: [URL] = []
    @State var progress: Double = 0
    @State var progressLabel = L10n.string("Processing...")
    @State var downloading: Bool = false
    @State var shouldShowBottleSelector: Bool = false
    @State var creatingBottle: Bool = false
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @MainActor var load: @Sendable () async -> Void
    @State var createBtlPrc: Process?
    @State var cleard3dmCacheStatus: DeleteStatus = DeleteStatus.idle
    
    var body: some View {
        Modal(
            L10n.string("Tools"),
            showModal: $libraryPageGlobals.showTools,
        ) {
            VStack(alignment: .leading) {
                Text(L10n.string("Cache management"))
                    .padding(.vertical, 5)
                ProminentButton(L10n.string("Delete owned games cache"), systemImage: "trash") {
                    api.deleteOwnedGamesIDsCache()
                    libraryPageGlobals.gamesMeta.removeAll()
                    Task {
                        await load()
                    }
                    libraryPageGlobals.showOptions = false
                }
                ProminentButton(L10n.string("Delete metadata cache"), systemImage: "trash") {
                    api.deleteGameCache()
                    api.deleteBlacklistCache()
                    libraryPageGlobals.games.removeAll()
                    Task {
                        await load()
                    }
                    libraryPageGlobals.showOptions = false
                }
                ProminentButton(L10n.string("Delete download cache"), systemImage: "trash") {
                    TarDownloader.deleteAllDownloadCache()
                }
                ProminentButton(L10n.string("Delete D3DMetal cache"), systemImage: "trash") {
                    cleard3dmCacheStatus = removeD3DMetalCaches()
                }
                ProminentButton(L10n.string("Show D3DMetal cache folder"), systemImage: "folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: darwinUserCacheDir()!.appendingPathComponent(D3DM_CACHE_FOLDER, isDirectory: true).path)
                }
                if(DEBUG_ENABLED == true) {
                    Divider().padding(.top, 10)
                    Text(L10n.string("Debug"))
                        .padding(.vertical, 5)
                    VStack(alignment: .leading) {
                        ProminentButton(L10n.string("Start logging"), systemImage: "ant") {
                            console.enableLogFile = true
                        }
                        Spacer()
                        ProminentButton(L10n.string("Download logs"), systemImage: "square.and.arrow.down") {
                            console.saveLogs()
                        }
                    }
                }
            }.padding(.vertical, 10)
        }
    }
}

#Preview {
    ToolsView(load: {})
}
