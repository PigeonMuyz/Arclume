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
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject var gameOptions: GameOptions
    @EnvironmentObject var compatibilityStore: GameCompatibilityStore
    @EnvironmentObject var nativeRuntimeStore: NativeAppRuntimeStore
    @State private var showGameOptions: Bool = false
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
        HStack (alignment: .bottom) {
            VStack(alignment: .leading){
                Text(displayName).font(.largeTitle.bold())
                if !game!.developers.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(developers).font(.footnote)
                }
                if !game!.publishers.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(publishers).font(.footnote)
                }
            }
            HStack(alignment: .center) {
                if(game!.downloadProgress == 100 && game!.isInstalled) {
                    PlayButtonExtras(playAction: playGame,
                    stopAction: {
                        if game!.isNative {
                            nativeRuntimeStore.stop(gameID: game!.id)
                        } else if OnlineGameMode.isJX3(game!) {
                            forceQuitJX3Game()
                        } else {
                            Task {
                                try! await closeWineActivities()
                                libraryPageGlobals.playingID = nil
                            }
                        }
                    }, optionsAction: isDirectNativeApplication ? nil : {
                        showGameOptions = true
                    }, editAction: game!.isCustom == true ? {
                        libraryPageGlobals.openCustomGameEditor(for: game)
                    } : nil, folderAction: {
                        if let meta = getMeta(libraryPageGlobals.gamesMeta, byID: String(game!.id)) {
                            showFolder(url: meta.gameURL!)
                        } else if game!.appExeURL != nil {
                            showFolder(url: game!.appExeURL!.deletingLastPathComponent())
                        }
                    }, isPlaying: isPlaying)
                }
            Spacer()
            
                HStack{
                    if(game!.isNative == true) {
                        Image(systemName: "apple.logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20)
                            .foregroundStyle(.white)
                        
                    }
                    if(game!.controllerSupport == "full") {
                        Image(systemName: "gamecontroller.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20)
                            .foregroundStyle(.white)
                        
                    }
                }
                HStack(alignment: .center){
                    Text(L10n.string("Available for:"))
                    if hasOfficialMacSupport {
                        Image("os-apple")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20)
                            .help(L10n.string("Native macOS support"))
                    } else if hasCrossOverMacSupport {
                        ZStack(alignment: .bottomTrailing) {
                            Image("os-apple")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20)

                            Image("crossover-fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 9, height: 9)
                                .padding(2)
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.85), in: Circle())
                                .offset(x: 5, y: 4)
                        }
                        .help(L10n.string("Available on macOS through CrossOver"))
                    }
                    if (game!.platforms.linux) {
                        Image("os-linux")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20)
                    }
                    if (game!.platforms.windows) {
                        Image("os-win")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 30)
                .background(.clear)
                .overlay(
                    Capsule()
                        .stroke(.white, lineWidth: 2)
                )
                .clipShape(.capsule)
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showGameOptions) {
            Modal(
                L10n.format("Options for %@", displayName),
                showModal: $showGameOptions
            ) {
                GameOptionsView(game: $game)
            }
        }
    }
    
    @MainActor
    func playGame() {
        guard !isPlaying else { return }
        libraryPageGlobals.setLoader(state: true)
        Task {
            do {
                let id = OnlineGameMode.gameOptionsIdentifier(for: game!)
                let gameOptKey = namespacedKey("GameOptions", id)
                if let data: GameOptionsData = readUsrDefData(key: gameOptKey) {
                    gameOptions.set(data: data)
                }
                if game!.usesCrossOverRuntime {
                    compatibilityStore.applyRuntimePreferences(for: game!, to: gameOptions)
                }
                if OnlineGameMode.isEnabled, game!.id == OnlineGameMode.jx3GameID {
                    OnlineGameMode.applyDefaultRuntimePreferences(to: gameOptions)
                    guard let bottleURL = OnlineGameDiscovery.selectedBottleURL(
                        from: appGlobals.selectedBottle
                    ) else {
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
                            tObserver = try await getGameTracker(appNames: game!.appNames, cxAppPath: appGlobals.cxAppPath, bottleName: appGlobals.selectedBottle, onLoad: {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                    libraryPageGlobals.setLoader(state: false)
                                }
                                libraryPageGlobals.playingID = game!.id
                            }, onTerminate: {
                                libraryPageGlobals.setLoader(state: false) // if doesn't get loaded i need to close the loader
                                libraryPageGlobals.playingID = nil
                                tObserver = nil
                            }, isNative: game!.isNative,
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
                    try await launchWindowsGame(id: String(game!.steamAppID), cxAppPath: appGlobals.cxAppPath, selectedBottle: appGlobals.selectedBottle, steamExePath: steamExePath, options: gameOptions, appExeURL: game!.appExeURL)
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
        guard let bottleURL = OnlineGameDiscovery.selectedBottleURL(
            from: appGlobals.selectedBottle
        ) else {
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
