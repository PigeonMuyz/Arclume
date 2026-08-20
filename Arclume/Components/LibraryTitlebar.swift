//
//  LibraryTitlebar.swift
//  Procyon
//

import SwiftUI

struct LibraryTitlebar: ToolbarContent {
    @ObservedObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject private var appGlobals: AppGlobals
    @EnvironmentObject private var compatibilityStore: GameCompatibilityStore

    var load: @Sendable () async -> Void
    let isOnlineMode: Bool

    private var filteredGames: [Game] {
        libraryPageGlobals.filteredGames { game in
            compatibilityStore.isPlayableOnMac(game)
        }
    }

    private var hasGameControls: Bool {
        !libraryPageGlobals.allGames.isEmpty
    }

    var body: some ToolbarContent {
        if isOnlineMode {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("重新扫描剑网3")

                Button {
                    forceQuitOnlineGame()
                } label: {
                    Image(systemName: "exclamationmark.octagon")
                }
                .help("强制退出当前 Games 容器中的剑网3启动器与游戏")

                if OnlineGameRuntimeKind.selected() == .crossOver,
                   let cxPath = appGlobals.cxAppPath {
                    Button {
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.environment = [
                            "CX_GRAPHICS_BACKEND": "d3dmetal",
                            "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "0"
                        ]
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: cxPath),
                            configuration: configuration
                        )
                    } label: {
                        Image("crossover-fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    .help("打开 CrossOver")
                }

                if let bottleURL = OnlineGameDiscovery.selectedBottleURL(
                    from: appGlobals.selectedBottle
                ) {
                    Button {
                        showFolder(url: bottleURL)
                    } label: {
                        Image(systemName: "waterbottle")
                    }
                    .help("在 Finder 中显示所选 Bottle")
                }

                Button {
                    presentTools()
                } label: {
                    Image(systemName: "wrench.adjustable.fill")
                }
                .help(L10n.string("Tools"))
                .accessibilityIdentifier("library-tools-button")

                Button {
                    libraryPageGlobals.showOptions = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help(L10n.string("Options"))
                .accessibilityIdentifier("library-settings-button")
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    libraryPageGlobals.showOptions = true
                } label: {
                    Label(L10n.string("Options"), systemImage: "gear")
                        .labelStyle(.iconOnly)
                }
                .help(L10n.string("Options"))
                .accessibilityIdentifier("library-settings-button")
            }
        }
        if !isOnlineMode {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    api.deleteOwnedGamesIDsCache()
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.string("Reload Steam libraries"))
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task {
                        try? await closeWineActivities()
                        libraryPageGlobals.isLaunchingGame = false
                    }
                } label: {
                    Image(systemName: "exclamationmark.octagon")
                }
                .help(L10n.string("Stop CrossOver activities"))
            }
        }
        if !isOnlineMode {
            ToolbarItemGroup(placement: .secondaryAction) {
                standardToolbarControls
            }
        }
    }

    @MainActor
    private func forceQuitOnlineGame() {
        guard let bottleURL = OnlineGameDiscovery.selectedBottleURL(
            from: appGlobals.selectedBottle
        ) else {
            return
        }
        libraryPageGlobals.isLaunchingGame = false
        libraryPageGlobals.playingID = nil
        libraryPageGlobals.jx3RuntimeActivity = .idle
        libraryPageGlobals.launchErrorMessage = nil
        Task {
            await OnlineGameLauncher.forceQuitJX3(
                in: bottleURL,
                crossOverAppPath: appGlobals.cxAppPath
            )
        }
    }

    private var standardToolbarControls: some View {
        HStack {
            HStack {
                Button {
                    libraryPageGlobals.filter = ""
                } label: {
                    Image(systemName: libraryPageGlobals.filter.isEmpty ? "magnifyingglass" : "xmark.circle")
                }
                .buttonStyle(.plain)
                TextField(L10n.string("Search Game..."), text: $libraryPageGlobals.filter)
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
                    .focusEffectDisabled()
                    .frame(width: 100)
            }
            .controlSize(.small)
            Divider()
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Picker(L10n.string("Filter"), selection: $libraryPageGlobals.libraryFilter) {
                    ForEach(LibraryFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
            }
            Divider()
            HStack {
                Image(systemName: "arrow.up.arrow.down.circle")
                Picker("", selection: $libraryPageGlobals.sortBy) {
                    Text(L10n.string("Name")).tag(SortingOptions.name)
                    Text(L10n.string("Release Date")).tag(SortingOptions.releaseDate)
                    Text(L10n.string("Publisher")).tag(SortingOptions.publisher)
                    Text(L10n.string("Developer")).tag(SortingOptions.developer)
                    Text(L10n.string("Installed")).tag(SortingOptions.installed)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }
            Divider()
            Text(
                L10n.format(
                    "Showing %@/%@",
                    String(filteredGames.count),
                    String(libraryPageGlobals.allGamesCount)
                )
            )
            .font(.footnote)
        }
        .padding(.horizontal)
        .disabled(!hasGameControls)
    }

    @MainActor
    private func presentTools() {
        // A sheet dismissed with its window control can leave the old binding
        // set to true. Resetting before presentation makes the toolbar action
        // reliable on every click.
        libraryPageGlobals.showTools = false
        DispatchQueue.main.async {
            libraryPageGlobals.showTools = true
        }
    }
}
