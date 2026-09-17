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
    @StateObject private var windowsInstallerStore = WindowsInstallerStore()
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var containerSteamStore: ContainerSteamStore
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var progress: Double = 0
    @State private var selectedGame: SteamGame? = nil
    @State private var mntObserver: MountObserver?
    @State private var loadGeneration = 0
    @State private var metadataRefreshTask: Task<Void, Never>?
    @State private var libraryScanner = SteamLibraryScanner()
    @State private var scanInProgress = false
    @State private var scanAgain = false
    @State private var lastScan = Date.distantPast
    @State private var showOnlineSetupGuide = false
    @State private var showOnlineRuntimeUpdate = false
    @State private var didOfferOnlineSetupGuide = false
    @State private var jx3LaunchMonitor: Task<Void, Never>?
    @AppStorage("libraryPresentation", store: UserDefaults(suiteName: suiteName))
    private var libraryPresentation = "grid"
    @AppStorage("unifiedLibraryOnboarding.v1", store: UserDefaults(suiteName: suiteName))
    private var completedUnifiedOnboarding = false
    @State private var showUnifiedOnboarding = false
    @State private var showUnifiedJX3Setup = false
    @State private var configureSteamAfterJX3 = false
    @State private var launcherTitle = "Arclume"
    
    var body: some View {
        ZStack {
            if libraryPageGlobals.isLaunchingGame && !OnlineGameMode.isEnabled && libraryPresentation != "launcher" {
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
                                Text("可以添加 Windows 程序、原生应用或 Steam 游戏库。Steam 是可选组件。")
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
                } else if libraryPresentation == "launcher" {
                    LauncherLibraryView(selectedTitle: $launcherTitle, onLaunchJX3: launchJX3Game, onStopJX3: forceQuitJX3Game)
                } else {
                    GamesList(load: load)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $libraryPageGlobals.showOptions) {
                OptionsView(load: load, onShowWelcome: {
                    libraryPageGlobals.showOptions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showUnifiedOnboarding = true
                    }
                })
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
            .sheet(isPresented: $showUnifiedJX3Setup, onDismiss: {
                Task { await load() }
                if configureSteamAfterJX3 {
                    configureSteamAfterJX3 = false
                    openSteamConfiguration()
                }
            }) {
                UnifiedJX3SetupView()
            }
            .alert(
                "无法启动剑网3",
                isPresented: Binding(
                    get: { libraryPageGlobals.launchErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            libraryPageGlobals.launchErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {
                    libraryPageGlobals.launchErrorMessage = nil
                }
            } message: {
                Text(libraryPageGlobals.launchErrorMessage ?? "")
            }
            .sheet(isPresented: $libraryPageGlobals.showTools) {
                ToolsView(load: load)
            }
            .alert("未能结束 Wine", isPresented: Binding(
                get: { libraryPageGlobals.wineStopErrorMessage != nil },
                set: { if !$0 { libraryPageGlobals.wineStopErrorMessage = nil } }
            )) {
                Button("好", role: .cancel) { libraryPageGlobals.wineStopErrorMessage = nil }
            } message: {
                Text(libraryPageGlobals.wineStopErrorMessage ?? "")
            }
            .sheet(isPresented: $libraryPageGlobals.showDetailView) {
                GameDetailView(game: $libraryPageGlobals.selectedGame)
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
            .sheet(isPresented: $libraryPageGlobals.showWindowsInstaller) {
                WindowsInstallerView()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
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
                } else if libraryPresentation != "launcher" {
                    HStack(alignment: .bottom) {
                        ArclumeToolbar()
                        Spacer()
                        if containerSteamStore.steamSetupBusy {
                            ProgressView(value: containerSteamStore.steamSetupProgress) {
                                Text(containerSteamStore.steamSetupMessage ?? "正在安装 Steam…")
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                            .frame(width: 230)
                        } else if isLoading {
                            LoadingProgress(progress: $progress)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .transition(.opacity)
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial.opacity(0.5))
                            .overlay(.arclumeAccent.mix(with: .black, by: 0.4).opacity(0.5))
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
            .overlay(alignment: .bottomLeading) {
                if libraryPresentation == "launcher" && !OnlineGameMode.isEnabled {
                    HStack(spacing: 14) {
                        if containerSteamStore.steamSetupBusy {
                            ProgressView(value: containerSteamStore.steamSetupProgress)
                                .frame(width: 100)
                                .help(containerSteamStore.steamSetupMessage ?? "正在安装 Steam…")
                        } else if isLoading {
                            ProgressView().controlSize(.small).help("正在后台更新游戏库")
                        }
                    }
                    .padding(.leading, 84)
                    .padding(18)
                }
            }
            .navigationTitle(libraryPresentation == "launcher" ? launcherTitle : "Arclume")
            .background {
                if !OnlineGameMode.isEnabled {
                    LibraryWindowTitle(title: libraryPresentation == "launcher" ? launcherTitle : "Arclume")
                }
            }
            .toolbarBackgroundVisibility(libraryPresentation == "launcher" ? .hidden : .automatic, for: .windowToolbar)
            .onAppear() {
                libraryPageGlobals.restoreSnapshot(context: appGlobals.selectedBottle)
                isLoading = !libraryPageGlobals.hasLibrarySnapshot
                if loadDebugFixtureIfRequested() {
                    isLoading = false
                    return
                }
                showUnifiedOnboarding = !completedUnifiedOnboarding
                if OnlineGameMode.isEnabled,
                   !didOfferOnlineSetupGuide {
                    // A mode switch leaves the shared selection pointing at
                    // Steam until the JX3 selection has been restored.
                    OnlineGameRuntimeKind.migrateLegacyCrossOverConfigurationIfNeeded(appGlobals: appGlobals)
                    OnlineGameRuntimeKind.restoreActiveBottleIfAvailable(appGlobals: appGlobals)
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
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                libraryPageGlobals.refreshLocalProgramAvailability()
                if Date().timeIntervalSince(lastScan) > 30 { Task { await load() } }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                if NSApplication.shared.isActive && !scanInProgress { Task { await load() } }
            }
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                // Revalidate saved launch paths without repeatedly scanning containers.
                if NSApplication.shared.isActive {
                    libraryPageGlobals.refreshLocalProgramAvailability()
                }
            }
            .toolbar {
                if !showUnifiedOnboarding { LibraryTitlebar(
                    libraryPageGlobals: libraryPageGlobals,
                    load: load,
                    isOnlineMode: OnlineGameMode.isEnabled,
                    isLauncherPresentation: libraryPresentation == "launcher"
                ) }
            }
            .environmentObject(libraryPageGlobals)
            .environmentObject(windowsInstallerStore)
            .disabled(showUnifiedOnboarding)
            .accessibilityHidden(showUnifiedOnboarding)
            if showUnifiedOnboarding {
                LibraryWelcomeView(onFinish: finishUnifiedOnboarding)
                    .zIndex(20)
            }
        }
    }

    private var isDebugFixtureRequested: Bool {
        #if DEBUG
        let explicitFixture = ProcessInfo.processInfo.environment["ARCLUME_UI_TEST_FIXTURE"] == "1"
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
            .appendingPathComponent("ArclumeUITestLibrary", isDirectory: true)
        var fixtureGame = Game.mock
        fixtureGame.id = "owned-uninstalled"
        fixtureGame.name = "Owned Uninstalled Game"
        fixtureGame.isCustom = false
        fixtureGame.isInstalled = false
        fixtureGame.isNative = false
        fixtureGame.downloadProgress = 0
        fixtureGame.isFromNativeSteamLibrary = nil
        fixtureGame.headerImage = ""
        fixtureGame.screenshots = []
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
    
    private func finishUnifiedOnboarding(steam: Bool, jx3: Bool) {
        completedUnifiedOnboarding = true
        showUnifiedOnboarding = false
        if jx3 {
            configureSteamAfterJX3 = steam
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showUnifiedJX3Setup = true }
        } else if steam {
            openSteamConfiguration()
        }
    }

    private func openSteamConfiguration() {
        libraryPageGlobals.requestedSettingsPage = "运行时"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            libraryPageGlobals.showOptions = true
        }
    }

    @MainActor
    private func load() async {
        guard !isDebugFixtureRequested else { return }
        if OnlineGameMode.isEnabled {
            await loadOnlineGames()
            return
        }
        guard !scanInProgress else { scanAgain = true; return }
        scanInProgress = true
        lastScan = Date()
        let scanContext = appGlobals.selectedBottle
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = !libraryPageGlobals.hasLibrarySnapshot
        errorMessage = nil
        defer {
            scanInProgress = false
            if generation == loadGeneration {
                isLoading = false
            }
            if scanAgain {
                scanAgain = false
                Task { await load() }
            }
        }
        progress = 0
        containerSteamStore.refreshClientDetection(
            bottleURL: OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle),
            legacyOverride: readUsrDefOptionString(key: "windowsSteamFolder").map(fileURL(from:))
        )
        appGlobals.windowsSteamFolder = containerSteamStore.installation?.steamRootURL
        appGlobals.refreshSteamIdentity(containerInstallation: containerSteamStore.installation)
        let discoveredFolders = (appGlobals.nativeSteamInstallation?.libraryURLs ?? [])
            + (containerSteamStore.installation?.libraries.compactMap(\.steamAppsURL) ?? [])
        // Keep discovered external libraries while their volume is temporarily offline.
        let offlineFolders = libraryPageGlobals.folders.filter {
            guard let url = URL(string: $0) else { return false }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        let folders = Array(Set(getSteamFolderPaths() + discoveredFolders.map(\.absoluteString) + offlineFolders)).sorted()
        libraryPageGlobals.folders = folders
        var loadedGamesMeta: [GamesMeta] = []
        var scannedRecords: [LibraryManifestRecord] = []
        await libraryScanner.seed(libraryPageGlobals.scanRecords)
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
                    let records = try await libraryScanner.scan(folderURL, native: nativeLibraryPaths.contains(scanURL.path))
                    scannedRecords.append(contentsOf: records)
                    loadedGamesMeta.append(contentsOf: records.map { $0.model() })
                } catch {
                    console.error(String(reflecting: error))
                    let retainedGamesMeta = libraryPageGlobals.gamesMeta.filter {
                        $0.libraryFolder.standardizedFileURL.path == scanURL.path
                    }
                    if !retainedGamesMeta.isEmpty {
                        scannedRecords.append(contentsOf: libraryPageGlobals.scanRecords.filter {
                            $0.library.standardizedFileURL.path == scanURL.path
                        })
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
            let scanResult = await Task.detached(priority: .utility) {
                SteamOwnedLibraryService().scanOwnedAppIDs(steamID: session.identity.steamID,
                    steamRootURLs: [session.steamRootURL])
            }.value
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

        let ownedMeta = ownershipByAppID.keys.sorted()
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

        var loadedGames = api.cachedGamesInfo(
            meta: loadedGamesMeta,
            setProgress: { value in
                if generation == loadGeneration {
                    progress = value
                }
            }
        )
        // Legacy Steam libraries stay visible but may not be silently launched
        // inside the newly selected prefix.
        for index in loadedGames.indices where !loadedGames[index].isNative {
            if let meta = loadedGamesMeta.first(where: { $0.appid == String(loadedGames[index].steamAppID) && !$0.isNative }),
               !(containerSteamStore.installation?.libraries.compactMap(\.steamAppsURL) ?? []).contains(where: {
                   $0.resolvingSymlinksInPath().standardizedFileURL == meta.libraryFolder.resolvingSymlinksInPath().standardizedFileURL
               }),
               ![BundledWineRuntime.prefixURL, BundledWineRuntime.standardSteamPrefixURL].contains(where: {
                   meta.libraryFolder.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + "/")
               }) {
                loadedGames[index].installedRuntimeKind = StandardGameRuntimeKind.crossOver.rawValue
            }
        }
        if let bottleURL = OnlineGameMode.jx3BottleURL(appGlobals: appGlobals) {
            let installation = await Task.detached(priority: .utility) {
                OnlineGameDiscovery.jx3Installation(in: bottleURL)
            }.value
            guard generation == loadGeneration, !Task.isCancelled else { return }
            if let launcher = OnlineGameDiscovery.games(from: installation).first {
                libraryPageGlobals.registerStandardJX3(
                    launcher, bottle: bottleURL,
                    runtimeKind: OnlineGameRuntimeKind.selected().rawValue,
                    crossOverPath: appGlobals.cxAppPath
                )
            }
        }
        guard generation == loadGeneration, !Task.isCancelled else { return }
        libraryPageGlobals.folders = folders
        if StandardGameRuntimeKind.selected() == .bundledWine {
            let bottle = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle)
                ?? BundledWineRuntime.standardSteamPrefixURL
            if (BundledWineRuntime.ownsStandardSteamPrefix(bottle) || BundledWineRuntime.ownsPrefix(bottle)),
               BundledWineRuntime.isValidPrefix(at: bottle) {
                let candidates = await Task.detached(priority: .utility) {
                    WindowsGameLaunchRules.discover(in: bottle)
                }.value
                guard generation == loadGeneration, !Task.isCancelled else { return }
                for candidate in candidates {
                    libraryPageGlobals.addInstalledProgram(candidate, bottle: bottle,
                        runtimeKind: StandardGameRuntimeKind.bundledWine.rawValue, crossOverPath: nil)
                }
            }
        }
        guard scanContext == appGlobals.selectedBottle else { scanAgain = true; return }
        libraryPageGlobals.gamesMeta = loadedGamesMeta
        libraryPageGlobals.applyScannedGames(loadedGames)
        libraryPageGlobals.scanRecords = scannedRecords
        libraryPageGlobals.ownershipByAppID = ownershipByAppID
        libraryPageGlobals.ownershipSessionCacheKeys = ownershipSessionCacheKeys
        libraryPageGlobals.hasLibrarySnapshot = true
        libraryPageGlobals.saveSnapshot(context: scanContext)
        progress = 100

        metadataRefreshTask = Task(priority: .utility) {
            await libraryPageGlobals.refreshGameDBMetadata()
            guard generation == loadGeneration, !Task.isCancelled else { return }
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
            guard generation == loadGeneration, !Task.isCancelled else { return }
            libraryPageGlobals.saveSnapshot(context: scanContext)
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
        guard !libraryPageGlobals.isLaunchingGame, !libraryPageGlobals.isStoppingWine else { return }

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
                if !(error is CancellationError) {
                    libraryPageGlobals.launchErrorMessage = "无法启动剑网3：\(error.localizedDescription)"
                }
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
