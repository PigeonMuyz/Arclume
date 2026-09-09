//
//  LibraryTitlebar.swift
//  Procyon
//

import SwiftUI

struct LibraryTitlebar: ToolbarContent {
    @ObservedObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject private var appGlobals: AppGlobals
    @EnvironmentObject private var compatibilityStore: GameCompatibilityStore
    @EnvironmentObject private var containerSteamStore: ContainerSteamStore

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

    private var onlineGameIsRunning: Bool {
        libraryPageGlobals.playingID == OnlineGameMode.jx3GameID
            || libraryPageGlobals.jx3RuntimeActivity.state != .idle
    }

    private var usesBundledWine: Bool {
        isOnlineMode ? OnlineGameRuntimeKind.selected() == .bundledWine
            : StandardGameRuntimeKind.selected() == .bundledWine
    }

    private var wineStopIcon: some View {
        ZStack {
            Image(systemName: "exclamationmark.octagon")
                .opacity(libraryPageGlobals.isStoppingWine ? 0 : 1)
            if libraryPageGlobals.isStoppingWine {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 24, height: 24)
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
                    if usesBundledWine { stopBundledWine() }
                    else { forceQuitOnlineGame() }
                } label: {
                    if usesBundledWine || libraryPageGlobals.isStoppingWine { wineStopIcon }
                    else { Image(systemName: onlineGameIsRunning ? "stop.fill" : "exclamationmark.octagon") }
                }
                .disabled(libraryPageGlobals.isStoppingWine)
                .help(
                    usesBundledWine ? "结束所有 Arclume Wine 进程" : onlineGameIsRunning
                        ? "停止当前 Games 容器中的剑网3启动器与游戏"
                        : "强制退出当前 Games 容器中的剑网3启动器与游戏"
                )
                .accessibilityLabel(libraryPageGlobals.isStoppingWine ? "正在停止 Arclume Wine" : usesBundledWine ? "结束所有 Arclume Wine 进程" : onlineGameIsRunning ? "停止游戏" : "强制退出游戏")

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
                    Label(L10n.string("Options"), systemImage: "gearshape")
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
                    if usesBundledWine { stopBundledWine() }
                    else { Task {
                        try? await closeWineActivities()
                        libraryPageGlobals.isLaunchingGame = false
                    } }
                } label: {
                    wineStopIcon
                }
                .disabled(libraryPageGlobals.isStoppingWine)
                .help(usesBundledWine ? "结束所有 Arclume Wine 进程" : L10n.string("Stop CrossOver activities"))
                .accessibilityLabel(libraryPageGlobals.isStoppingWine ? "正在停止 Arclume Wine" : "结束 Wine 进程")
                .accessibilityIdentifier("stop-wine-button")
            }
        }
        if !isOnlineMode {
            ToolbarItemGroup(placement: .secondaryAction) {
                standardToolbarControls
            }
        }
    }

    @MainActor
    private func stopBundledWine() {
        guard !libraryPageGlobals.isStoppingWine else { return }
        libraryPageGlobals.isStoppingWine = true
        libraryPageGlobals.wineStopErrorMessage = nil
        containerSteamStore.cancelPendingBundledWineLaunches()
        let root = BundledWineRuntime.installationURL.deletingLastPathComponent()
        Task {
            defer { libraryPageGlobals.isStoppingWine = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await ArclumeWineStopService.stop(runtimeRoot: root)
                }.value
                // Only report idle once kernel process enumeration confirms it.
                libraryPageGlobals.isLaunchingGame = false
                libraryPageGlobals.playingID = nil
                libraryPageGlobals.jx3RuntimeActivity = .idle
            } catch {
                libraryPageGlobals.wineStopErrorMessage = error.localizedDescription
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
