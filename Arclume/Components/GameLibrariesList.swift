//
//  GameLibrariesList.swift
//  Procyon
//
//  Created by Italo Mandara on 31/03/2026.
//

import SwiftUI

struct GameLibrariesList: View {
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @MainActor var load: @Sendable () async -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(L10n.string("Game libraries"))
                .padding(.horizontal)
            if !libraryPageGlobals.folders.isEmpty { VStack {
                Divider()
                ForEach(libraryPageGlobals.folders, id: \.self) {folder in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(folder.contains("drive_c") ? "Windows Steam" : "Steam 游戏库")
                            Text((URL(string: folder)?.path ?? folder).replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }.help(folder)
                        Spacer()
                        if getSteamFolderPaths().contains(folder) { Button(action: {
                            removeSteamFolderPath(folder)
                            libraryPageGlobals.folders = getSteamFolderPaths()
                            Task { await load() }
                        }) {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                        } else {
                            Text("自动发现").font(.caption).foregroundStyle(.secondary).fixedSize()
                        }
                    }
                    .padding(.horizontal)
                }
                Divider()
            }
            }
            Button(action: {
                if let url = openFolderSelectorPanel() {
                    validateAddSteamFolder(url, to: &libraryPageGlobals.folders)
                    Task { await load() }
                }
            }) {
                Label(L10n.string("Add a steam library"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
    }
}
