//
//  LibraryTitlebar.swift
//  Arclume
//

import SwiftUI

struct LibraryTitlebar: ToolbarContent {
    @ObservedObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject private var appGlobals: AppGlobals
    @EnvironmentObject private var compatibilityStore: GameCompatibilityStore
    @EnvironmentObject private var containerSteamStore: ContainerSteamStore

    var load: @Sendable () async -> Void
    let isOnlineMode: Bool
    var isLauncherPresentation = false
    @State private var steamLaunchError: String?

    private var filteredGames: [Game] {
        libraryPageGlobals.filteredGames { game in
            compatibilityStore.isPlayableOnMac(game)
        }
    }

    private var hasGameControls: Bool {
        !libraryPageGlobals.allGames.isEmpty
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
        if isLauncherPresentation || isOnlineMode {
            ToolbarItemGroup(placement: .primaryAction) {
                ArclumeLibraryActions(
                    compactIcons: true,
                    onStopContainer: stopCurrentContainerRuntime,
                    stopConfirmationMessage: stopConfirmationMessage
                )
                .labelStyle(.iconOnly)
                .controlSize(.regular)
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                libraryPageGlobals.showOptions = true
            } label: {
                if isLauncherPresentation {
                    LauncherToolbarIcon(symbol: "gearshape")
                        .accessibilityLabel(L10n.string("Options"))
                } else {
                    Label(L10n.string("Options"), systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
            }
            .help(L10n.string("Options"))
            .accessibilityIdentifier("library-settings-button")
            .launcherTourTarget(.settings)
        }
        if isOnlineMode {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("重新扫描剑网3")
            }
        }
        if !isOnlineMode && isLauncherPresentation && containerSteamStore.isReady {
            ToolbarItemGroup(placement: .secondaryAction) {
                SteamUpdateRecoveryControl()
                Button {
                    containerSteamStore.openSteam(using: .bundledWine) { steamLaunchError = $0 }
                } label: {
                    Label {
                        Text(containerSteamStore.steamOpening ? "准备 Steam…" : "打开 Steam")
                    } icon: {
                        Image("steam-fill").resizable().scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                }
                .disabled(libraryPageGlobals.isStoppingWine || containerSteamStore.steamOpening)
                .accessibilityIdentifier("library-open-steam-button")
                .help("打开当前 Windows 游戏容器中的 Steam")
                .alert("无法打开 Steam", isPresented: Binding(
                    get: { steamLaunchError != nil },
                    set: { if !$0 { steamLaunchError = nil } }
                )) {
                    Button("好", role: .cancel) { steamLaunchError = nil }
                } message: {
                    Text(steamLaunchError ?? "")
                }
            }
        }
        if !isOnlineMode && !isLauncherPresentation {
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
        if !isOnlineMode && !isLauncherPresentation {
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
    private func stopCurrentContainerRuntime() {
        guard !libraryPageGlobals.isStoppingWine else { return }
        if usesBundledWine {
            stopBundledWine()
        } else if isOnlineMode {
            forceQuitOnlineGame()
        } else {
            Task {
                do {
                    try await closeWineActivities()
                } catch {
                    libraryPageGlobals.wineStopErrorMessage = error.localizedDescription
                }
                libraryPageGlobals.isLaunchingGame = false
                libraryPageGlobals.playingID = nil
            }
        }
    }

    private var stopConfirmationMessage: String {
        if usesBundledWine {
            return "将结束 Arclume Wine 容器中的 Windows 程序，未保存内容可能丢失。不会结束其他容器，也不会删除游戏、缓存或账户数据。"
        }
        if isOnlineMode {
            return "将强制退出当前 Games 容器中的剑网3启动器与游戏，未保存内容可能丢失。不会删除游戏、缓存或账户数据。"
        }
        return "将尝试退出当前 Wine 或 CrossOver 程序，未保存内容可能丢失。"
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
                    ForEach([LibraryFilter.installed, .all]) { option in
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

}
