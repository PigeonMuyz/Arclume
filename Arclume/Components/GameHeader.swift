//
//  GameHeader.swift
//  Procyon
//
//  Created by Italo Mandara on 05/02/2026.
//

import SwiftUI

struct GameHeader: View {
    @Binding var game: Game?
    @Binding var showDetailView: Bool
    var overlaysPoster = false
    var launcherStyle = false
    var onLauncherStart: (() -> Void)? = nil
    var onLauncherStop: (() -> Void)? = nil
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject var gameOptions: GameOptions
    @EnvironmentObject var compatibilityStore: GameCompatibilityStore
    @EnvironmentObject var nativeRuntimeStore: NativeAppRuntimeStore
    @State private var showGameOptions: Bool = false
    @State private var showEditor = false
    @State private var showQuality = false
    @State private var iconAccent = Color.accentColor
    var isPlaying: Bool {
        if game!.isNative {
            return nativeRuntimeStore.isActive(gameID: game!.id)
        }
        return libraryPageGlobals.playingID == game!.id
    }
    @State private var tObserver: TerminationObserver?
    @State private var jx3LaunchMonitor: Task<Void, Never>?
    
    var developers: String {
        L10n.format("Developer: %@", game!.developers.joined(separator: ", "))
    }
    
    var publishers: String { // @To do: DRY
        L10n.format("Publisher: %@", game!.publishers.joined(separator: ", "))
    }

    var displayName: String {
        game!.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.string("Untitled Game")
            : game!.name
    }

    var isDirectNativeApplication: Bool {
        game?.isDirectNativeApplication == true
    }

    var hasOfficialMacSupport: Bool {
        game?.isNative == true || game?.platforms.mac == true
    }

    var hasCrossOverMacSupport: Bool {
        guard let game, game.supportsCrossOverCompatibility else { return false }
        return compatibilityStore.profile(for: game).crossOverStatus == .supported
    }
    
    var body: some View {
        Group {
            if launcherStyle { launcherControls }
            else { detailControls }
        }
        .sheet(isPresented: $showGameOptions) {
            Modal("运行设置 · \(displayName)", showModal: $showGameOptions, scrollable: false, subdued: true) {
                if game?.isNative == true {
                    NativeProjectOptionsView(game: game!)
                } else {
                    ScrollView { GameOptionsView(game: $game) }.frame(width: 720, height: 480)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            ProjectEditorView(isPresented: $showEditor, initialGame: game)
        }
        .sheet(isPresented: $showQuality) {
            Modal("剑网3画质设置", showModal: $showQuality, scrollable: false) {
                JX3QualitySettingsView(bottleURL: OnlineGameMode.jx3BottleURL(appGlobals: appGlobals))
                    .frame(width: 760, height: 520)
            }
        }
        .background {
            if let game {
                LauncherApplicationIcon(game: game, size: 1, onLoad: { iconAccent = LauncherAccent.color(from: $0) })
                    .hidden().allowsHitTesting(false)
            }
        }
    }

    private var launcherControls: some View {
        HStack(spacing: 10) {
            Button {
                if isPlaying {
                    if let onLauncherStop { onLauncherStop() } else { stopGame() }
                } else {
                    if let onLauncherStart { onLauncherStart() } else { playGame() }
                }
            } label: {
                HStack(spacing: 10) {
                    if libraryPageGlobals.isLaunchingGame { ProgressView().controlSize(.small) }
                    else { Image(systemName: isPlaying ? "stop.fill" : "play.fill") }
                    Text(libraryPageGlobals.isLaunchingGame ? "正在启动…" : isPlaying ? "停止运行" : game?.isInstalled == true ? "开始游戏" : "尚未安装")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .foregroundStyle(.white)
            .glassEffect(.regular.tint(iconAccent.opacity(0.45)).interactive(), in: .capsule)
            .disabled(libraryPageGlobals.isStoppingWine || libraryPageGlobals.isLaunchingGame || game?.isInstalled != true || game?.downloadProgress != 100)
            .accessibilityIdentifier("launcher.primaryAction")
            Menu {
                Button(action: revealInstallation) {
                    Label("打开安装目录", systemImage: "folder")
                }.disabled(installationDirectory == nil)
                Button { showGameOptions = true } label: {
                    Label("运行设置", systemImage: "slider.horizontal.3")
                }
                Button { showEditor = true } label: {
                    Label("编辑项目信息", systemImage: "pencil")
                }
                if let game, OnlineGameMode.isJX3(game) {
                    Divider()
                    Button { showQuality = true } label: { Label("画质设置", systemImage: "display") }
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 48, height: 48)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(iconAccent.opacity(0.30))
            .foregroundStyle(.white)
            .help("更多操作")
            .accessibilityLabel("更多操作")
            .accessibilityIdentifier("launcher.more")
        }
        .controlSize(.large)
    }

    private var detailControls: some View {
        HStack(alignment: .center, spacing: 24) {
            HStack(spacing: 10) {
                if game!.downloadProgress == 100 && game!.isInstalled {
                    Button(action: { isPlaying ? stopGame() : playGame() }) {
                        Label(isPlaying ? L10n.string("Stop") : "启动",
                              systemImage: isPlaying ? "stop.fill" : "play.fill")
                            .font(.headline)
                            .frame(minWidth: 100, minHeight: 26)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .disabled(libraryPageGlobals.isStoppingWine)
                    .accessibilityIdentifier("gameDetail.primaryAction")
                }
            }
            .controlSize(.large)
            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .textSelection(.enabled)
                Label(game!.isNative ? "macOS" : "Windows", systemImage: game!.isNative ? "apple.logo" : "desktopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                if !isDirectNativeApplication {
                    Button { showGameOptions = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help("运行设置")
                    .accessibilityLabel("运行设置")
                    .accessibilityIdentifier("gameDetail.options")
                }
                Menu {
                    if game!.isCustom == true {
                        Button { showEditor = true } label: {
                            Label("编辑项目信息…", systemImage: "pencil")
                        }
                    }
                    Button(action: revealInstallation) {
                        Label("打开安装目录", systemImage: "folder")
                    }
                    .disabled(installationDirectory == nil)
                    .accessibilityIdentifier("gameDetail.installationDirectory")
                } label: {
                    Image(systemName: "ellipsis")
                }
                .help("更多操作")
                .accessibilityLabel("更多操作")

                if game!.controllerSupport == "full" {
                    Image(systemName: "gamecontroller").help("支持控制器")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .fixedSize()
        }
    }

    private var installationDirectory: URL? {
        guard let game else { return nil }
        if let meta = getMeta(libraryPageGlobals.gamesMeta, byID: String(game.id)),
           let url = meta.gameURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return LibraryProgramLocation.directory(for: game)
    }

    private func revealInstallation() {
        guard let url = installationDirectory else { return }
        showFolder(url: url)
    }

    private func stopGame() {
        guard let game else { return }
        if game.isNative {
            nativeRuntimeStore.stop(gameID: game.id)
        } else if OnlineGameMode.isJX3(game) {
            forceQuitJX3Game()
        } else {
            Task {
                do { try await closeWineActivities() }
                catch { libraryPageGlobals.wineStopErrorMessage = error.localizedDescription }
                libraryPageGlobals.playingID = nil
            }
        }
    }

    @MainActor
    func playGame() {
        guard !isPlaying, !libraryPageGlobals.isStoppingWine else { return }
        libraryPageGlobals.setLoader(state: true)
        Task {
            do {
                let id = OnlineGameMode.gameOptionsIdentifier(for: game!)
                let gameOptKey = namespacedKey("GameOptions", id)
                if let data: GameOptionsData = readUsrDefData(key: gameOptKey) {
                    gameOptions.set(data: data)
                }
                if OnlineGameMode.isJX3(game!) {
                    OnlineGameMode.applyDefaultRuntimePreferences(to: gameOptions)
                    guard let bottleURL = OnlineGameMode.jx3BottleURL(appGlobals: appGlobals) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let crossOverPath = appGlobals.cxAppPath
                    if OnlineGameRuntimeKind.selected() == .crossOver,
                       crossOverPath == nil {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let launchSession = try await OnlineGameLauncher.launchJX3(
                        in: bottleURL,
                        crossOverAppPath: crossOverPath,
                        options: gameOptions
                    )
                    libraryPageGlobals.playingID = game!.id
                    libraryPageGlobals.setLoader(state: false)
                    libraryPageGlobals.jx3RuntimeActivity = JX3RuntimeActivity(
                        launcherProcessIdentifiers: [],
                        gameProcessIdentifiers: [],
                        rootProcessIsRunning: true,
                        clientLaunchObservedInLog: false
                    )
                    jx3LaunchMonitor?.cancel()
                    jx3LaunchMonitor = OnlineGameLauncher.monitor(
                        launchSession,
                        onUpdate: { activity in
                            libraryPageGlobals.jx3RuntimeActivity = activity
                        },
                        onTermination: {
                            guard libraryPageGlobals.playingID == game!.id else { return }
                            libraryPageGlobals.playingID = nil
                            libraryPageGlobals.jx3RuntimeActivity = .idle
                            libraryPageGlobals.setLoader(state: false)
                            jx3LaunchMonitor = nil
                        }
                    )
                } else if isDirectNativeApplication {
                    guard let appURL = game!.appExeURL else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let environment = gameOptions.mtlHudEnabled
                        ? ["MTL_HUD_ENABLED": "1"]
                        : [:]
                    try await nativeRuntimeStore.launchApplication(
                        gameID: game!.id,
                        at: appURL,
                        environment: environment
                    )
                    libraryPageGlobals.setLoader(state: false)
                } else if game!.isNative {
                    nativeRuntimeStore.expectApplicationLaunch(
                        gameID: game!.id,
                        appNames: game!.appNames,
                        bundleIdentifier: game!.nativeAppBundleIdentifier
                    )
                    do {
                        try await launchNativeGame(
                            id: String(game!.steamAppID),
                            cxAppPath: appGlobals.cxAppPath ?? "",
                            selectedBottle: appGlobals.selectedBottle,
                            options: gameOptions,
                            appExeURL: game!.appExeURL
                        )
                    } catch {
                        nativeRuntimeStore.cancelExpectedLaunch(
                            gameID: game!.id,
                            error: error
                        )
                        throw error
                    }
                    libraryPageGlobals.setLoader(state: false)
                } else {
                    Task(priority: .background) {
                        do {
                            tObserver = try await getGameTracker(appNames: game!.appNames, cxAppPath: game!.installedCrossOverPath ?? appGlobals.cxAppPath, bottleName: game!.installedBottleURL?.absoluteString ?? appGlobals.selectedBottle, onLoad: {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                    libraryPageGlobals.setLoader(state: false)
                                }
                                libraryPageGlobals.playingID = game!.id
                            }, onTerminate: {
                                libraryPageGlobals.setLoader(state: false) // if doesn't get loaded i need to close the loader
                                libraryPageGlobals.playingID = nil
                                tObserver = nil
                            }, isNative: game!.isNative,
                            stopSteamOnTermination: game!.installedBottleURL == nil,
                            steamAppID: game!.isCustom == true ? nil : game!.steamAppID,
                            steamRootURL: appGlobals.windowsSteamFolder)
                        } catch {
                            console.error("Game tracking failed: \(String(reflecting: error))")
                            libraryPageGlobals.setLoader(state: false) // if doesn't get loaded i need to close the loader
                        }
                    }
                    if(game!.isCustom == true && game!.appExeURL == nil) {
                        console.error("custom game doesn't have an executable associated")
                        libraryPageGlobals.setLoader(state: false)
                        return
                    }
                    let steamExePath = appGlobals.windowsSteamFolder?.appendingPathComponent("Steam.exe").path(percentEncoded: false) ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
                    try await launchWindowsGame(id: String(game!.steamAppID), cxAppPath: game!.installedCrossOverPath ?? appGlobals.cxAppPath, selectedBottle: game!.installedBottleURL?.absoluteString ?? appGlobals.selectedBottle, steamExePath: steamExePath, options: gameOptions, appExeURL: game!.appExeURL, installedRuntimeKind: game!.installedRuntimeKind)
                }
            } catch {
                libraryPageGlobals.setLoader(state: false)
                if OnlineGameMode.isJX3(game!) {
                    libraryPageGlobals.jx3RuntimeActivity = .idle
                }
                console.error("Error launching game: \(String(reflecting: error))")
            }
            showDetailView = false
        }
    }

    @MainActor
    private func forceQuitJX3Game() {
        guard let bottleURL = OnlineGameMode.jx3BottleURL(appGlobals: appGlobals) else {
            return
        }
        libraryPageGlobals.playingID = nil
        libraryPageGlobals.jx3RuntimeActivity = .idle
        jx3LaunchMonitor?.cancel()
        jx3LaunchMonitor = nil
        Task {
            await OnlineGameLauncher.forceQuitJX3(
                in: bottleURL,
                crossOverAppPath: appGlobals.cxAppPath
            )
        }
    }
}
