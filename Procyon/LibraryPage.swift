//
//  LibraryPage.swift
//  Procyon
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI
import Combine
import Kingfisher

struct LibraryPage: View {
    @StateObject var libraryPageGlobals = LibraryPageGlobals()
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var containerSteamStore: ContainerSteamStore
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var progress: Double = 0
    @State private var selectedGame: SteamGame? = nil
    @State private var mntObserver: MountObserver?
    @State private var loadGeneration = 0
    @State private var metadataRefreshTask: Task<Void, Never>?
    @State private var showOnlineSetupGuide = false
    @State private var showOnlineRuntimeUpdate = false
    @State private var didOfferOnlineSetupGuide = false
    @State private var jx3LaunchMonitor: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            if libraryPageGlobals.isLaunchingGame && !OnlineGameMode.isEnabled {
                VStack {
                    ProgressView(label: {
                        Text(
                            L10n.format(
                                "Launching %@...",
                                libraryPageGlobals.selectedGame?.name
                                    ?? L10n.string("Unknown")
                            )
                        )
                    })
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .background {
                        if (libraryPageGlobals.selectedGame?.headerImage != nil){
                            KFImage(URL(string: libraryPageGlobals.selectedGame!.headerImage))
                                .placeholder {
                                    ProgressView()
                                }
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 10)
                                .opacity(0.4)
                        }
                    }
                }
                .background(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity).zIndex(10)
            }
            
            VStack {
                if (errorMessage != nil) {
                    ContentUnavailableView {
                        Label(L10n.string("Unable to load game library"), systemImage: "exclamationmark.triangle")
                            .padding(.bottom)
                    } description: {
                        VStack(spacing: 12) {
                            Text(errorMessage!)
                                .multilineTextAlignment(.center)
                            Button {
                                libraryPageGlobals.showOptions = true
                            } label: {
                                Label(L10n.string("Open Library Options"), systemImage: "gearshape")
                            }
                        }
                    }
                    .foregroundStyle(.white)
                } else if (!isLoading && libraryPageGlobals.allGames.isEmpty) {
                    if OnlineGameMode.isEnabled {
                        OnlineGameSetupLandingView {
                            showOnlineSetupGuide = true
                        }
                    } else {
                        VStack {
                            ContentUnavailableView {
                                Label(L10n.string("No Libraries found"), systemImage: "gamecontroller")
                                    .padding(.bottom)
                            } description: {
                                Text(L10n.string("No Steam libraries found.\nPlease add a Steam library folder."))
                                Button {
                                    libraryPageGlobals.showOptions = true
                                } label: {
                                    Label(L10n.string("Add Library"), systemImage: "plus")
                                }
                            }
                            .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if OnlineGameMode.isEnabled {
                    if let jx3Game = libraryPageGlobals.allGames.first(
                        where: { $0.id == OnlineGameMode.jx3GameID }
                    ) {
                        JX3LauncherHomeView(
                            game: jx3Game,
                            isPresented: .constant(true),
                            onLaunch: {
                                launchJX3Game(jx3Game)
                            },
                            isLaunching: libraryPageGlobals.isLaunchingGame,
                            isPlaying: libraryPageGlobals.playingID == jx3Game.id,
                            runtimeActivity: libraryPageGlobals.jx3RuntimeActivity,
                            onStop: {
                                forceQuitJX3Game()
                            },
                            showsCloseButton: false
                        )
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(.white)
                    }
                } else {
                    GamesList(load: load)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $libraryPageGlobals.showOptions) {
                OptionsView(load: load)
            }
            .sheet(isPresented: $showOnlineSetupGuide) {
                OnlineGameSetupGuide(
                    isPresented: $showOnlineSetupGuide,
                    load: load
                )
            }
            .sheet(isPresented: $showOnlineRuntimeUpdate) {
                OnlineGameRuntimeUpdateView(
                    isPresented: $showOnlineRuntimeUpdate,
                    load: load
                )
            }
            .sheet(isPresented: $libraryPageGlobals.showTools) {
                ToolsView(load: load)
            }
            .sheet(isPresented: $libraryPageGlobals.showDetailView) {
                Modal(showModal: $libraryPageGlobals.showDetailView, collapse: true, content:  {
                    GameDetailView(game: $libraryPageGlobals.selectedGame)
                })
            }
            .sheet(isPresented: $libraryPageGlobals.showCustomGameEditor) {
                Modal(
                    L10n.string("Custom Game Editor"),
                    showModal: $libraryPageGlobals.showCustomGameEditor,
                    scrollable: true
                ) {
                    CustomGameView(
                        isPresented: $libraryPageGlobals.showCustomGameEditor,
                        initialGameID: libraryPageGlobals.editingCustomGameID
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if OnlineGameMode.isEnabled {
                    if isLoading {
                        HStack {
                            Spacer()
                            LoadingProgress(progress: $progress)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .transition(.opacity)
                    }
                } else {
                    HStack(alignment: .bottom) {
                        ProcyonToolbar()
                        Spacer()
                        if (isLoading) {
                            LoadingProgress(progress: $progress)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .transition(.opacity)
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial.opacity(0.5))
                            .overlay(.procyonAccent.mix(with: .black, by: 0.4).opacity(0.5))
                            .mask {
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .black.opacity(0.0), location: 0.0), // top = transparent
                                        .init(color: .black.opacity(0.9), location: 0.5), // fade in
                                        .init(color: .black.opacity(1.0), location: 1.0)              // bottom = solid
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                    }
                }
            }
            .onAppear() {
                isLoading = true // fixes missing library issue
                try? FileManager.default.createDirectory(at: PROCYON_SUPPORT_FOLDER_URL.appendingPathComponent(DEFAULT_CXP_BOTTLES_FOLDER), withIntermediateDirectories: true)
                if loadDebugFixtureIfRequested() {
                    isLoading = false
                    return
                }
                if OnlineGameMode.isEnabled,
                   !didOfferOnlineSetupGuide {
                    didOfferOnlineSetupGuide = true
                    DispatchQueue.main.async {
                        if OnlineGameSetupStatus.requiresBundledWineRuntimeUpdate(
                            appGlobals: appGlobals
                        ) {
                            showOnlineRuntimeUpdate = true
                        } else if !OnlineGameSetupStatus.isComplete(
                            appGlobals: appGlobals
                        ) {
                            showOnlineSetupGuide = true
                        }
                    }
                }
                Task(priority: .background) {
                    await load()
                }
                mntObserver = MountObserver(
                    onMount: {
                        Task(priority: .background) {
                            await load()
                        }
                    },
                    onUnmount: {
                        Task(priority: .background) {
                            await load()
                        }
                    }
                )
            }
            .onDisappear {
                mntObserver = nil
                jx3LaunchMonitor?.cancel()
                jx3LaunchMonitor = nil
                metadataRefreshTask?.cancel()
                metadataRefreshTask = nil
            }
            .toolbar {
                LibraryTitlebar(
                    libraryPageGlobals: libraryPageGlobals,
                    load: load,
                    isOnlineMode: OnlineGameMode.isEnabled
                )
            }
            .environmentObject(libraryPageGlobals)
        }
    }

    private var isDebugFixtureRequested: Bool {
        #if DEBUG
        let explicitFixture = ProcessInfo.processInfo.environment["PROCYON_UI_TEST_FIXTURE"] == "1"
        // Unit tests are hosted inside the app process. Avoid starting the
        // real Bottle/font scan there; tests should not depend on the user's
        // CrossOver state or leave a background extraction task behind.
        return explicitFixture || NSClassFromString("XCTestCase") != nil
        #else
        false
        #endif
    }

    @MainActor
    private func loadDebugFixtureIfRequested() -> Bool {
        guard isDebugFixtureRequested else { return false }

        #if DEBUG
        let libraryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProcyonUITestLibrary", isDirectory: true)
        var fixtureGame = Game.mock
        fixtureGame.id = "owned-uninstalled"
        fixtureGame.name = "Owned Uninstalled Game"
        fixtureGame.isCustom = false
        fixtureGame.isInstalled = false
        fixtureGame.isNative = false
        fixtureGame.downloadProgress = 0
        fixtureGame.isFromNativeSteamLibrary = nil
        libraryPageGlobals.gamesMeta = [
            GamesMeta(
                appid: String(Game.mock.steamAppID),
                installdir: "",
                isNative: false,
                libraryFolder: libraryURL,
                bytesDownloaded: "0",
                BytesTodownload: "0"
            )
        ]
        libraryPageGlobals.games = [fixtureGame]
        libraryPageGlobals.ownershipByAppID = [fixtureGame.steamAppID: [.native]]
        libraryPageGlobals.ownershipSessionCacheKeys = [:]
        libraryPageGlobals.libraryFilter = .all
        return true
        #else
        return false
        #endif
    }
    
    @MainActor
    private func load() async {
        guard !isDebugFixtureRequested else { return }
        if OnlineGameMode.isEnabled {
            await loadOnlineGames()
            return
        }
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        progress = 0
        let folders = getSteamFolderPaths()
        var loadedGamesMeta: [GamesMeta] = []
        var ownershipByAppID: [Int: Set<SteamClientKind>] = [:]
        var ownershipSessionCacheKeys: [SteamClientKind: String] = [:]
        let detectedNativeSteam = appGlobals.nativeSteamInstallation
            ?? SteamDiscoveryService().detectNativeSteam()
        let nativeLibraryPaths = Set(
            (detectedNativeSteam?.libraryURLs ?? []).map {
                $0.standardizedFileURL.path
            }
        )
        if folders.isEmpty {
            console.warn("There are no folders to scan.")
        } else {
            for folder in folders {
                guard let folderURL = URL(string: folder) else {
                    console.error("Invalid persisted Steam library URL: \(folder)")
                    continue
                }
                let scanURL = steamAppsFolderURL(for: folderURL)
                    ?? folderURL.standardizedFileURL
                do {
                    let foldergamesMeta = try getGamesMeta(
                        from: folderURL,
                        isNativeSteamLibrary: nativeLibraryPaths.contains(
                            scanURL.path
                        )
                    )
                    loadedGamesMeta.append(contentsOf: foldergamesMeta)
                } catch {
                    console.error(String(reflecting: error))
                    let retainedGamesMeta = libraryPageGlobals.gamesMeta.filter {
                        $0.libraryFolder.standardizedFileURL.path == scanURL.path
                    }
                    if !retainedGamesMeta.isEmpty {
                        console.warn(
                            "Retaining \(retainedGamesMeta.count) games from the previous scan of \(scanURL.path)"
                        )
                        loadedGamesMeta.append(contentsOf: retainedGamesMeta)
                    }
                }
            }
        }

        for meta in loadedGamesMeta {
            guard let appID = Int(meta.appid) else { continue }
            if meta.isFromNativeSteamLibrary == true {
                ownershipByAppID[appID, default: []].insert(.native)
            } else if meta.isFromNativeSteamLibrary == false {
                ownershipByAppID[appID, default: []].insert(.container)
            }
        }

        let ownedLibraryService = SteamOwnedLibraryService()
        var ownedAppIDsBySteamID: [String: Set<String>] = [:]
        for session in appGlobals.steamSessions {
            ownershipSessionCacheKeys[session.clientKind] = session.cacheKey
            let scanResult = ownedLibraryService.scanOwnedAppIDs(
                steamID: session.identity.steamID,
                steamRootURLs: [session.steamRootURL]
            )
            var sessionAppIDs = Set(
                scanResult.appIDs
            )
            var didResolveCompleteLibrary = scanResult.didReadAllRoots

            if isConfiguredMetadataServiceAvailable {
                do {
                    let remoteAppIDs = try await api.fetchOwnedGamesIDs(
                        userID: session.identity.steamID,
                        identityCacheKey: "account:\(session.identity.steamID)"
                    )
                    sessionAppIDs.formUnion(remoteAppIDs)
                    didResolveCompleteLibrary = true
                } catch {
                    console.error("fetchOwnedGamesIDs \(String(reflecting: error))")
                }
            }

            if !didResolveCompleteLibrary,
               libraryPageGlobals.ownershipSessionCacheKeys[session.clientKind]
                    == session.cacheKey {
                let retainedAppIDs = libraryPageGlobals.ownershipByAppID.compactMap {
                    appID, ownership in
                    ownership.contains(session.clientKind) ? String(appID) : nil
                }
                if !retainedAppIDs.isEmpty {
                    console.warn(
                        "Retaining \(retainedAppIDs.count) owned games for \(session.cacheKey) after a temporary librarycache read failure"
                    )
                    sessionAppIDs.formUnion(retainedAppIDs)
                }
            }

            ownedAppIDsBySteamID[
                session.identity.steamID,
                default: []
            ].formUnion(sessionAppIDs)
        }

        // Steam licenses belong to the account, not to one client cache. When
        // native Steam and the selected bottle use the same SteamID, a title
        // discovered from either userdata/librarycache is installable through
        // both compatible clients.
        for (appID, accountOwnership) in ownedLibraryService.ownershipByAppID(
            sessions: appGlobals.steamSessions,
            appIDsBySteamID: ownedAppIDsBySteamID
        ) {
            ownershipByAppID[appID, default: []].formUnion(accountOwnership)
        }

        let ownedMeta = ownershipByAppID.keys
            .filter { appID in
                !loadedGamesMeta.contains(where: { $0.appid == String(appID) })
            }
            .map {
                GamesMeta(
                    appid: String($0),
                    installdir: "",
                    bytesDownloaded: "0",
                    BytesTodownload: "0"
                )
            }
        loadedGamesMeta.append(contentsOf: ownedMeta)

        let loadedGames = api.cachedGamesInfo(
            meta: loadedGamesMeta,
            setProgress: { value in
                if generation == loadGeneration {
                    progress = value
                }
            }
        )
        guard generation == loadGeneration, !Task.isCancelled else { return }
        libraryPageGlobals.folders = folders
        libraryPageGlobals.gamesMeta = loadedGamesMeta
        libraryPageGlobals.games = loadedGames
        libraryPageGlobals.ownershipByAppID = ownershipByAppID
        libraryPageGlobals.ownershipSessionCacheKeys = ownershipSessionCacheKeys
        progress = 100

        metadataRefreshTask = Task(priority: .utility) {
            do {
                try await api.refreshGamesInfoIncrementally(
                    meta: loadedGamesMeta,
                    onGame: { refreshedGame in
                        guard generation == loadGeneration,
                              !Task.isCancelled,
                              let index = libraryPageGlobals.games.firstIndex(
                                where: { $0.id == refreshedGame.id }
                              )
                        else {
                            return
                        }
                        libraryPageGlobals.games[index] = refreshedGame
                    }
                )
            } catch is CancellationError {
                return
            } catch {
                guard generation == loadGeneration else { return }
                console.error("refreshGamesInfoIncrementally \(String(reflecting: error))")
            }

            guard generation == loadGeneration, !Task.isCancelled else { return }
            await libraryPageGlobals.refreshNativeAppStoreMetadata()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            await libraryPageGlobals.refreshNativeSteamMetadata()
        }
    }

    @MainActor
    private func loadOnlineGames() async {
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // Keep the shared saved custom-game list intact on disk, but never
        // surface standard-edition entries in the online-only edition.
        libraryPageGlobals.customAddedGames = []

        guard let bottleURL = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle) else {
            libraryPageGlobals.games = []
            libraryPageGlobals.gamesMeta = []
            return
        }
        guard FileManager.default.fileExists(atPath: bottleURL.path) else {
            libraryPageGlobals.games = []
            libraryPageGlobals.gamesMeta = []
            errorMessage = "所选 Bottle 已不存在，请在设置中重新选择。"
            return
        }

        do {
            try OnlineGameBottleConfiguration.apply(to: bottleURL)
        } catch {
            console.error("Unable to configure the Bottle locale: \(String(reflecting: error))")
        }

        if OnlineGameDiscovery.jx3Installation(in: bottleURL).isDetected {
            OnlineGameInitialConfiguration.startPolling(for: bottleURL)
        }
        libraryPageGlobals.games = OnlineGameDiscovery.games(in: bottleURL)
        libraryPageGlobals.gamesMeta = []
        libraryPageGlobals.ownershipByAppID = [:]
        libraryPageGlobals.ownershipSessionCacheKeys = [:]
        progress = 100
    }

    @MainActor
    private func launchJX3Game(_ game: Game) {
        guard !libraryPageGlobals.isLaunchingGame else { return }

        libraryPageGlobals.selectedGame = game
        libraryPageGlobals.launchErrorMessage = nil
        libraryPageGlobals.setLoader(state: true)

        Task {
            do {
                let id = OnlineGameMode.gameOptionsIdentifier(for: game)
                let gameOptKey = namespacedKey("GameOptions", id)
                let gameOptions = GameOptions()
                if let gameOptionsData: GameOptionsData = readUsrDefData(key: gameOptKey) {
                    gameOptions.set(data: gameOptionsData)
                }
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
                libraryPageGlobals.playingID = game.id
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
                        guard libraryPageGlobals.playingID == game.id else { return }
                        libraryPageGlobals.playingID = nil
                        libraryPageGlobals.jx3RuntimeActivity = .idle
                        libraryPageGlobals.setLoader(state: false)
                        jx3LaunchMonitor = nil
                    }
                )
            } catch {
                console.error(String(reflecting: error))
                libraryPageGlobals.setLoader(state: false)
                libraryPageGlobals.playingID = nil
                libraryPageGlobals.jx3RuntimeActivity = .idle
                libraryPageGlobals.launchErrorMessage = "无法启动剑网3：\(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func forceQuitJX3Game() {
        guard let bottleURL = OnlineGameDiscovery.selectedBottleURL(
            from: appGlobals.selectedBottle
        ) else {
            return
        }
        libraryPageGlobals.setLoader(state: false)
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

#Preview {
    ContentView()
}
