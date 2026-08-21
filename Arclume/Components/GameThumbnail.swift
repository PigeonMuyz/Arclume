//
//  GameThumbnail.swift
//  Procyon
//
//  Created by Italo Mandara on 30/01/2026.
//

import SwiftUI
import Kingfisher
import AppKit

struct GameThumbnail: View {
    var item: Game
    var isResizable: Bool = false
    var fixedCardWidth: CGFloat? = nil
    var fixedCardHeight: CGFloat? = nil
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject var containerSteamStore: ContainerSteamStore
    @EnvironmentObject var nativeSteamStore: NativeSteamStore
    @EnvironmentObject var compatibilityStore: GameCompatibilityStore
    @EnvironmentObject var nativeRuntimeStore: NativeAppRuntimeStore
    @State private var tObserver: TerminationObserver?
    @State private var jx3LaunchMonitor: Task<Void, Never>?
    @State private var coverDidLoad = false
    @State private var coverDidFail = false
    @State private var coverTimedOut = false
    @State private var showRemoveConfirmation = false
    @State private var isHovering = false
    @State private var cardLogoDidFail = false
    @State private var showCardPresentationEditor = false
    @State private var showJX3LauncherHome = false
    @State private var jx3LauncherFeed: JX3LauncherFeed?

    private var coverURL: URL? {
        let urlString = item.headerImage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.isEmpty, let url = URL(string: urlString) {
            return url
        }
        guard isOnlineJX3 else { return nil }
        return jx3LauncherFeed?.primaryArtworkURL
    }

    private var shouldShowCoverFallback: Bool {
        coverURL == nil || coverDidFail || coverTimedOut
    }

    private var displayName: String {
        item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.string("Untitled Game")
            : item.name
    }
    private var nativeAppIcon: NSImage? {
        guard item.isDirectNativeApplication,
              let appURL = item.appExeURL,
              FileManager.default.fileExists(atPath: appURL.path)
        else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
    var isPlaying: Bool {
        if usesNativeSteamRuntime {
            return nativeRuntimeStore.isActive(gameID: item.id)
        }
        return libraryPageGlobals.playingID == item.id
    }
    var isDownloading: Bool {
        if let state = currentInstallSnapshot?.state {
            switch state {
            case .waiting, .downloading:
                return true
            case .installed, .notInstalled, .failed:
                return false
            case .unknown:
                break
            }
        }
        return item.downloadProgress > 0 && item.downloadProgress < 100
    }
    var containerInstallState: SteamInstallState? {
        containerInstallSnapshot?.state
    }
    var nativeInstallState: SteamInstallState? {
        nativeInstallSnapshot?.state
    }
    var isContainerInstalled: Bool {
        containerInstallState == .installed
    }
    var isInstalled: Bool {
        item.isInstalled || isContainerInstalled || nativeInstallState == .installed
    }
    private var nativeInstallSnapshot: SteamInstallSnapshot? {
        guard item.steamAppID > 0,
              item.isFromNativeSteamLibrary != false
        else {
            return nil
        }
        return nativeSteamStore.snapshot(for: item.steamAppID)
    }
    private var containerInstallSnapshot: SteamInstallSnapshot? {
        guard item.steamAppID > 0,
              item.isFromNativeSteamLibrary != true
        else {
            return nil
        }
        return containerSteamStore.snapshot(for: item.steamAppID)
    }
    private var usesNativeSteamRuntime: Bool {
        if item.isNative || item.isFromNativeSteamLibrary == true {
            return true
        }
        guard let nativeInstallState else { return false }
        return nativeInstallState != .notInstalled
    }
    private var hasLaunchTarget: Bool {
        item.steamAppID > 0 || item.appExeURL != nil
    }
    private var steamInstallDestination: SteamInstallDestination {
        item.steamInstallDestination(
            nativeSteamAvailable: nativeSteamStore.isReady,
            containerSteamAvailable: containerSteamStore.isReady
                && (StandardGameRuntimeKind.selected() == .bundledWine
                    || appGlobals.cxAppPath != nil),
            ownership: steamOwnership
        )
    }
    private var steamOwnership: Set<SteamClientKind> {
        libraryPageGlobals.ownershipByAppID[item.steamAppID] ?? []
    }
    private var canRequestSteamAction: Bool {
        item.steamAppID > 0 && !item.isSteamTool
    }
    private var steamActionBackground: Color {
        if steamInstallDestination != .unavailable {
            return .arclumeSecondary
        }
        return hasSteamAccountMismatch ? .orange : .gray
    }
    private var steamActionForeground: Color {
        steamInstallDestination != .unavailable ? .black : .white
    }
    private var hasSteamAccountMismatch: Bool {
        guard !steamOwnership.isEmpty,
              item.platforms.mac || item.platforms.windows
        else {
            return false
        }
        let ownsCompatibleClient = (item.platforms.mac && steamOwnership.contains(.native))
            || (item.platforms.windows && steamOwnership.contains(.container))
        return !ownsCompatibleClient
    }
    private var installHelp: String {
        switch steamInstallDestination {
        case .nativeSteam:
            return L10n.string("Install with Steam for macOS")
        case .containerSteam:
            return L10n.string("Install with Steam in the selected CrossOver bottle")
        case .unavailable:
            if hasSteamAccountMismatch {
                return L10n.string(
                    "Switch the compatible Steam client to an account that owns this game before installing"
                )
            }
            return L10n.string("Configure a compatible Steam installation before installing this game")
        }
    }
    var updatedItem: Game {
        var newItem = item
        if let meta = libraryPageGlobals.gamesMeta.first(where: { $0.id == item.id }){
            
            newItem.appNames = getAppNames(isNative: meta.isNative, gameURL: meta.gameURL)
            return newItem
        }
        return newItem
    }

    private var isOnlineJX3: Bool {
        OnlineGameMode.isEnabled && item.id == OnlineGameMode.jx3GameID
    }

    private var cardLogoURL: URL? {
        if let presentationLogoURL = OnlineGamePresentationStore.logoURL(for: item.id) {
            return presentationLogoURL
        }

        guard item.steamAppID > 0 else { return nil }
        return URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(item.steamAppID)/logo.png")
    }

    private let cardAspectRatio: CGFloat = 1.52
    
    var body: some View {
        standardThumbnail
    }

    private var cardCanvas: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Group {
                    if let coverURL, !shouldShowCoverFallback {
                        KFImage(coverURL)
                            .placeholder {
                                GameCoverLoading()
                            }
                            .onSuccess { _ in
                                coverDidLoad = true
                            }
                            .onFailure { _ in
                                coverDidFail = true
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } else if let nativeAppIcon {
                        NativeGameCoverIcon(icon: nativeAppIcon)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        GameCoverFallback()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    openDetailPage()
                }

                if !isOnlineJX3, usesNativeSteamRuntime {
                    OIcon("apple.logo")
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                }

                cardLaunchOverlay
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(.arclumeAccent.mix(with: .black, by: 0.6).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    @ViewBuilder
    private var cardSizedCanvas: some View {
        if let fixedCardWidth, let fixedCardHeight {
            cardCanvas
                .frame(width: fixedCardWidth, height: fixedCardHeight)
        } else {
            cardCanvas
                .frame(maxWidth: .infinity)
                .aspectRatio(cardAspectRatio, contentMode: .fit)
                .frame(height: isResizable ? nil : 214)
        }
    }

    private var standardThumbnail: some View {
        cardSizedCanvas
        .onContinuousHover { phase in
            let hovering: Bool
            switch phase {
            case .active:
                hovering = true
            case .ended:
                hovering = false
            }

            guard isHovering != hovering else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .onChange(of: cardLogoURL?.absoluteString) { _, _ in
            cardLogoDidFail = false
        }
        .contextMenu {
            if isOnlineJX3 || item.isCustom == true {
                Button {
                    showCardPresentationEditor = true
                } label: {
                    Label(
                        isOnlineJX3 ? "编辑剑网3卡片" : "编辑卡片",
                        systemImage: "pencil"
                    )
                }
            }

            if item.isCustom == true {
                Button {
                    libraryPageGlobals.openCustomGameEditor(for: item)
                } label: {
                    Label(L10n.string("Edit Game"), systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Label(L10n.string("Remove from Arclume"), systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showCardPresentationEditor) {
            GameCardPresentationEditor(
                game: item,
                isPresented: $showCardPresentationEditor,
                onSave: updateGamePresentation
            )
        }
        .sheet(isPresented: $showJX3LauncherHome) {
            JX3LauncherHomeView(
                game: item,
                isPresented: $showJX3LauncherHome,
                initialFeed: jx3LauncherFeed,
                onLaunch: {
                    showJX3LauncherHome = false
                    performCardAction()
                },
                isPlaying: isPlaying,
                runtimeActivity: libraryPageGlobals.jx3RuntimeActivity,
                onStop: {
                    showJX3LauncherHome = false
                    stopOnlineGame()
                },
                onFeedUpdated: { refreshedFeed in
                    jx3LauncherFeed = refreshedFeed
                }
            )
            .frame(minWidth: 900, idealWidth: 980, minHeight: 620, idealHeight: 700)
        }
        .alert(
            isOnlineJX3 ? "无法启动剑网3" : "无法启动游戏",
            isPresented: Binding(
                get: { libraryPageGlobals.launchErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        libraryPageGlobals.launchErrorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.string("OK"), role: .cancel) {
                libraryPageGlobals.launchErrorMessage = nil
            }
        } message: {
            Text(libraryPageGlobals.launchErrorMessage ?? "")
        }
        .confirmationDialog(
            L10n.format("Remove %@ from Arclume?", displayName),
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.string("Remove"), role: .destructive) {
                libraryPageGlobals.deleteCustomAddedGame(game: item)
            }
            Button(L10n.string("Cancel"), role: .cancel) { }
        } message: {
            Text(L10n.string("This only removes the game from Arclume and does not delete its app or files."))
        }
        .task(id: coverURL?.absoluteString) {
            coverDidLoad = false
            coverDidFail = coverURL == nil
            coverTimedOut = false

            guard coverURL != nil else { return }

            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                guard !coverDidLoad, !coverDidFail else { return }
                coverTimedOut = true
            } catch {
                // The view disappeared or its image URL changed before the timeout.
            }
        }
        .task(id: isOnlineJX3) {
            guard isOnlineJX3 else {
                jx3LauncherFeed = nil
                return
            }
            jx3LauncherFeed = JX3LauncherFeedStore.cachedFeed()
        }
    }

    private var cardLaunchOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(isHovering ? 0.88 : 0.64)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: isHovering ? 118 : 78)
            .overlay(alignment: .bottom) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: openDetailPage) {
                        cardTitle
                            .frame(maxWidth: 150, maxHeight: 38, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel(displayName)

                    Spacer(minLength: 8)
                    if isHovering, canShowCardAction {
                        Button(action: performCardAction) {
                            Label(
                                cardActionTitle,
                                systemImage: cardActionSystemImage
                            )
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .disabled(cardActionIsDisabled)
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.38), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeInOut(duration: 0.16), value: isHovering)
    }

    @ViewBuilder
    private var cardTitle: some View {
        if let cardLogoURL, !cardLogoDidFail {
            KFImage(cardLogoURL)
                .onFailure { _ in
                    cardLogoDidFail = true
                }
                .placeholder {
                    Text(displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                }
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 138, maxHeight: 38, alignment: .leading)
        } else {
            Text(displayName)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
        }
    }

    private var canShowCardAction: Bool {
        hasLaunchTarget && !isDownloading
    }

    private var cardActionTitle: String {
        if isPlaying {
            return L10n.string("Stop")
        }
        if isOnlineJX3 {
            return "打开启动器"
        }
        if isInstalled {
            return L10n.string("Play")
        }
        return steamInstallDestination != .unavailable
            ? L10n.string("Install")
            : hasSteamAccountMismatch
                ? L10n.string("Switch Account")
                : L10n.string("Set Up Steam")
    }

    private var cardActionSystemImage: String {
        if isPlaying {
            return "stop.fill"
        }
        if isOnlineJX3 || isInstalled {
            return "play.fill"
        }
        return steamInstallDestination != .unavailable
            ? "square.and.arrow.down"
            : hasSteamAccountMismatch
                ? "person.crop.circle.badge.exclamationmark"
                : "gear"
    }

    private var cardActionIsDisabled: Bool {
        if isOnlineJX3 {
            return libraryPageGlobals.isLaunchingGame && !isPlaying
        }
        if isInstalled {
            return false
        }
        return !canRequestSteamAction
    }

    @MainActor
    private func performCardAction() {
        if isPlaying {
            if isOnlineJX3 {
                stopOnlineGame()
            } else {
                stopStandardGame()
            }
        } else if isInstalled || isOnlineJX3 {
            PlayGame()
        } else {
            installGame()
        }
    }

    @MainActor
    private func stopStandardGame() {
        if usesNativeSteamRuntime {
            nativeRuntimeStore.stop(gameID: item.id)
        } else {
            Task {
                try? await closeWineActivities()
                libraryPageGlobals.playingID = nil
            }
        }
    }

    private func stopOnlineGame() {
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

    private var currentInstallSnapshot: SteamInstallSnapshot? {
        if let nativeInstallSnapshot,
           nativeInstallSnapshot.state == .waiting
            || nativeInstallSnapshot.state == .downloading {
            return nativeInstallSnapshot
        }
        if let containerInstallSnapshot,
           containerInstallSnapshot.state == .waiting
            || containerInstallSnapshot.state == .downloading {
            return containerInstallSnapshot
        }
        return nativeInstallSnapshot ?? containerInstallSnapshot
    }

    @MainActor
    private func installGame() {
        guard item.steamAppID > 0 else {
            containerSteamStore.errorMessage = L10n.string(
                "This game does not have a valid Steam app ID."
            )
            return
        }

        switch steamInstallDestination {
        case .nativeSteam:
            nativeSteamStore.install(appID: item.steamAppID)
        case .containerSteam:
            switch StandardGameRuntimeKind.selected() {
            case .bundledWine:
                containerSteamStore.install(
                    appID: item.steamAppID,
                    using: .bundledWine
                )
            case .crossOver:
                guard let cxPath = appGlobals.cxAppPath else {
                    containerSteamStore.errorMessage = L10n.string(
                        "Select a CrossOver app before installing a game."
                    )
                    return
                }
                containerSteamStore.install(
                    appID: item.steamAppID,
                    crossOverAppURL: URL(fileURLWithPath: cxPath)
                )
            }
        case .unavailable:
            if hasSteamAccountMismatch {
                nativeSteamStore.errorMessage = installHelp
            } else {
                libraryPageGlobals.showOptions = true
            }
        }
    }
    
    @MainActor
    func PlayGame () {
        // Do not turn the global loading state on when the game is already
        // running. The previous ordering left the launcher permanently in a
        // disabled/loading state after a second click.
        guard !isPlaying else { return }

        libraryPageGlobals.selectedGame = updatedItem
        libraryPageGlobals.launchErrorMessage = nil
        libraryPageGlobals.setLoader(state: true)
        Task {
            do {
                let id = OnlineGameMode.gameOptionsIdentifier(for: item)
                let gameOptKey = namespacedKey("GameOptions", id)
                let gameOptions: GameOptions = GameOptions()
                if let gameOptionsData: GameOptionsData = readUsrDefData(key: gameOptKey) {
                    gameOptions.set(data: gameOptionsData)
                    console.log("options retrieved")
                } else {
                    console.warn("failed to retrieve game options")
                }
                if item.usesCrossOverRuntime && !usesNativeSteamRuntime {
                    compatibilityStore.applyRuntimePreferences(for: item, to: gameOptions)
                }
                if OnlineGameMode.isEnabled, item.id == OnlineGameMode.jx3GameID {
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
                    libraryPageGlobals.playingID = item.id
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
                            guard libraryPageGlobals.playingID == item.id else { return }
                            libraryPageGlobals.playingID = nil
                            libraryPageGlobals.jx3RuntimeActivity = .idle
                            libraryPageGlobals.setLoader(state: false)
                            jx3LaunchMonitor = nil
                        }
                    )
                } else if item.isDirectNativeApplication {
                    guard let appURL = item.appExeURL else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let environment = gameOptions.mtlHudEnabled
                        ? ["MTL_HUD_ENABLED": "1"]
                        : [:]
                    try await nativeRuntimeStore.launchApplication(
                        gameID: item.id,
                        at: appURL,
                        environment: environment
                    )
                    libraryPageGlobals.setLoader(state: false)
                } else if usesNativeSteamRuntime {
                    nativeRuntimeStore.expectApplicationLaunch(
                        gameID: item.id,
                        appNames: updatedItem.appNames,
                        bundleIdentifier: item.nativeAppBundleIdentifier
                    )
                    do {
                        try await launchNativeGame(
                            id: String(item.steamAppID),
                            cxAppPath: appGlobals.cxAppPath ?? "",
                            selectedBottle: appGlobals.selectedBottle,
                            options: gameOptions,
                            appExeURL: item.appExeURL
                        )
                    } catch {
                        nativeRuntimeStore.cancelExpectedLaunch(
                            gameID: item.id,
                            error: error
                        )
                        throw error
                    }
                    libraryPageGlobals.setLoader(state: false)
                } else {
                    Task(priority: .background) {
                        do {
                            tObserver = try await getGameTracker(appNames: updatedItem.appNames, cxAppPath: appGlobals.cxAppPath, bottleName: appGlobals.selectedBottle, onLoad: {
                                libraryPageGlobals.playingID = item.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                    libraryPageGlobals.setLoader(state: false)
                                }
                            }, onTerminate: {
                                libraryPageGlobals.setLoader(state: false) // if doesn't get loaded i need to close the loader
                                libraryPageGlobals.playingID = nil
                                tObserver = nil
                            }, isNative: item.isNative,
                            steamAppID: item.isCustom == true ? nil : item.steamAppID,
                            steamRootURL: appGlobals.windowsSteamFolder)
                        } catch {
                            console.error("Game tracking failed: \(String(reflecting: error))")
                            libraryPageGlobals.setLoader(state: false)
                        }
                    }
                    if(item.isCustom == true && item.appExeURL == nil) {
                        console.error("custom game doesn't have an executable associated")
                        libraryPageGlobals.setLoader(state: false)
                        return
                    }
                    let steamExePath = appGlobals.windowsSteamFolder?.appendingPathComponent("Steam.exe").path(percentEncoded: false) ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
                    try await launchWindowsGame(id: String(item.steamAppID), cxAppPath: appGlobals.cxAppPath, selectedBottle: appGlobals.selectedBottle, steamExePath: steamExePath, options: gameOptions, appExeURL: item.appExeURL)
                }
            } catch {
                console.error(String(reflecting: error))
                libraryPageGlobals.setLoader(state: false)
                if OnlineGameMode.isEnabled, item.id == OnlineGameMode.jx3GameID {
                    libraryPageGlobals.playingID = nil
                    libraryPageGlobals.jx3RuntimeActivity = .idle
                    libraryPageGlobals.launchErrorMessage = "无法启动剑网3：\(error.localizedDescription)"
                }
            }
        }
    }
    
    func openDetailPage() {
        if isOnlineJX3 {
            showJX3LauncherHome = true
            return
        }
        libraryPageGlobals.selectedGame = updatedItem
        libraryPageGlobals.showDetailView =  true
    }

    private func updateGamePresentation(_ presentation: OnlineGamePresentation) {
        var updatedGame = item
        OnlineGamePresentationStore.apply(presentation, to: &updatedGame)
        if item.isCustom == true {
            libraryPageGlobals.updateCustomAddedGames(gameData: updatedGame)
        } else if let index = libraryPageGlobals.games.firstIndex(where: { $0.id == item.id }) {
            libraryPageGlobals.games[index] = updatedGame
        }
        if libraryPageGlobals.selectedGame?.id == item.id {
            libraryPageGlobals.selectedGame = updatedGame
        }
    }
}

private struct NativeGameCoverIcon: View {
    let icon: NSImage

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .arclumeAccent.mix(with: .black, by: 0.45),
                    .arclumeAccent.mix(with: .black, by: 0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .shadow(radius: 8)
            }
            .padding(24)
        }
    }
}

private struct GameCoverLoading: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.arclumeAccent.mix(with: .black, by: 0.55))
            ProgressView()
                .controlSize(.regular)
        }
    }
}

private struct GameCoverFallback: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.arclumeAccent.mix(with: .black, by: 0.48), .arclumeAccent.mix(with: .black, by: 0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

#Preview {
    GameThumbnail(item: .mock)
}
