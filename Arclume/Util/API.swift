//
//  API.swift
//  Procyon
//
//  Created by Italo Mandara on 29/01/2026.
//

import Foundation
import Alamofire

private func infoString(_ key: String, default defaultValue: String = "") -> String {
    Bundle.main.object(forInfoDictionaryKey: key) as? String ?? defaultValue
}

let configuredAPIKey = infoString("API_KEY")
let pr = infoString("API_PROTOCOL", default: "https")
let host = infoString("API_HOST")
let path = infoString("API_PATH")

let baseAPIURL = "\(pr)://\(host)\(path)"

var isConfiguredMetadataServiceAvailable: Bool {
    !host.isEmpty && !configuredAPIKey.isEmpty
}

enum SteamMetadataSource: String, CaseIterable, Identifiable {
    case localOnly
    case steamStore
    case localProxy
    case configuredService

    var id: Self { self }

    var title: String {
        switch self {
        case .localOnly:
            return L10n.string("Local library only")
        case .steamStore:
            return L10n.string("Steam Store (Direct)")
        case .localProxy:
            return L10n.string("Local Steam Store proxy")
        case .configuredService:
            return L10n.string("Configured metadata service")
        }
    }
}

func resolvedSteamMetadataSource(
    storedValue: String?,
    configuredServiceAvailable: Bool
) -> SteamMetadataSource {
    let selectedSource = SteamMetadataSource(rawValue: storedValue ?? "") ?? .steamStore
    if selectedSource == .configuredService, !configuredServiceAvailable {
        return .steamStore
    }
    return selectedSource
}

func migrateUnavailableConfiguredMetadataSourceIfNeeded() {
    guard let defaults = UserDefaults(suiteName: suiteName),
          defaults.string(forKey: "steamMetadataSource")
            == SteamMetadataSource.configuredService.rawValue,
          !isConfiguredMetadataServiceAvailable
    else {
        return
    }
    defaults.set(SteamMetadataSource.steamStore.rawValue, forKey: "steamMetadataSource")
}

struct SteamGameResponse: Codable, Sendable {
    let data: [SteamGame]
}

struct SteamOwnedGamesResponse: Codable, Sendable {
    let response: SteamOwnedGames
}

struct SteamOwnedGamesResponseData: Codable, Sendable {
    let data: SteamOwnedGamesResponse
}

struct SteamGameResponseArray: Codable, Sendable {
    let data: [SteamGame]
}

enum APIError: LocalizedError {
    case badURL
    case invalidResponse
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .badURL:
            return L10n.string("The API URL is invalid.")
        case .invalidResponse:
            return L10n.string("The API returned an invalid response.")
        case .missingConfiguration:
            return L10n.string("Steam metadata API settings are missing. Configure Arclume/Config.local.xcconfig.")
        }
    }
}

private let localSteamProxyBaseURL = "http://127.0.0.1:18765/steam"

private struct SteamGameCacheEntry: Codable {
    let game: SteamGame
    let fetchedAt: Date
}

private func validateAPIConfiguration() throws {
    guard !host.isEmpty, !configuredAPIKey.isEmpty else {
        throw APIError.missingConfiguration
    }
}

final class SteamAPI {
    var progress: Double = 0
    private var cacheProfileData: [String: UserInfo] = [:]
    private var cache: [String: SteamGameCacheEntry] = [:]
    private var cacheOwnedGamesIDs: [String: [String]] = [:]
    private var autoConfigCache: [String: GameOptionsData] = [:]
    private let apiKey: String = configuredAPIKey
    private var cacheBlacklistURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ArclumeSteamCacheBlacklist.plist")
    }
    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ArclumeSteamCache.plist")
    }
    private var cacheOwnedGamesIDsURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ArclumeSteamOwnedGamesIDsCache.plist")
    }
    private var profileDataCacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ArclumeSteamProfileDataCache.plist")
    }

    private func loadCache() {
        console.log("Loading caches...")
        self.loadGameCache()
        self.loadIDCache()
        self.loadProfileDataCache()
    }
    
    init() {
        self.loadCache()
        if(self.cache.isEmpty){
            console.warn("Cache is empty")
        }
        if(self.cacheOwnedGamesIDs.isEmpty){
            console.warn("ID Cache is empty")
        }
    }
    private func loadGameCache() {
        do {
            let data = try Data(contentsOf: cacheURL)
            if let decoded = try? JSONDecoder().decode(
                [String: SteamGameCacheEntry].self,
                from: data
            ) {
                self.cache = decoded
            } else {
                let legacy = try JSONDecoder().decode([String: SteamGame].self, from: data)
                self.cache = legacy.mapValues {
                    SteamGameCacheEntry(game: $0, fetchedAt: .distantPast)
                }
            }
            if (self.cache.isEmpty == false){
                console.warn("Cache loaded")
            }
        } catch {
            console.error("Cache is empty, coulnd't read the file")
        }
    }
    private func saveGameCache() {
        do {
            let encoded = try JSONEncoder().encode(self.cache)
            try encoded.write(to: self.cacheURL, options: [.atomic])
            console.warn("Cache saved")
        } catch {
            console.error(String(reflecting: error))
        }
    }
    func deleteGameCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        self.cache.removeAll()
        console.warn("Cache deleted")
    }
    private func loadIDCache() {
        do {
            let data = try Data(contentsOf: cacheOwnedGamesIDsURL)
            let decoded = try JSONDecoder().decode([String: [String]].self, from: data)
            self.cacheOwnedGamesIDs = decoded
            if(self.cacheOwnedGamesIDs.isEmpty == false){
                console.warn("ID Cache loaded")
            }
        } catch {
            console.error("ID Cache is empty, coulnd't read the file")
        }
    }
    func deleteBlacklistCache() {
        try? FileManager.default.removeItem(at: cacheBlacklistURL)
        console.warn("Legacy metadata blacklist cache deleted")
    }
    func loadProfileDataCache() {
        do {
            let data = try Data(contentsOf: profileDataCacheURL)
            let decoded = try JSONDecoder().decode([String: UserInfo].self, from: data)
            self.cacheProfileData = decoded
            console.warn("Profile Data Cache loaded")
        } catch {
            console.error("Profile Data Cache is empty, couldn't read the file")
        }
    }
    func saveProfileDataCache() {
        do {
            let encoded = try JSONEncoder().encode(self.cacheProfileData)
            try encoded.write(to: self.profileDataCacheURL, options: [.atomic])
            console.warn("Profile Data Cache saved")
        } catch {
            console.error(String(reflecting: error))
        }
    }
    func deleteProfileDataCache() {
        try? FileManager.default.removeItem(at: profileDataCacheURL)
        self.cacheProfileData.removeAll()
        console.warn("Profile Data Cache deleted")
    }
    private func saveOwnedGamesIDsCache() {
        do {
            let encoded = try JSONEncoder().encode(self.cacheOwnedGamesIDs)
            try encoded.write(to: self.cacheOwnedGamesIDsURL, options: [.atomic])
            console.warn("IDs Cache saved")
        } catch {
            console.error(String(reflecting: error))
        }
    }

    func deleteOwnedGamesIDsCache() {
        try? FileManager.default.removeItem(at: cacheOwnedGamesIDsURL)
        self.cacheOwnedGamesIDs.removeAll()
        console.warn("IDs Cache deleted")
    }

    var metadataSource: SteamMetadataSource {
        let storedValue = UserDefaults(suiteName: suiteName)?
            .string(forKey: "steamMetadataSource")
        return resolvedSteamMetadataSource(
            storedValue: storedValue,
            configuredServiceAvailable: isConfiguredMetadataServiceAvailable
        )
    }

    private func metadataRequestConfiguration(
        for source: SteamMetadataSource
    ) -> (baseURL: String, headers: HTTPHeaders)? {
        let languageHeader: HTTPHeaders = [
            "Accept-Language": GameMetadataLanguage.current.acceptLanguage
        ]
        switch source {
        case .localOnly:
            return nil
        case .steamStore:
            return nil
        case .localProxy:
            return (localSteamProxyBaseURL, languageHeader)
        case .configuredService:
            guard !host.isEmpty, !configuredAPIKey.isEmpty else {
                return nil
            }
            var headers = languageHeader
            headers.add(name: "x-api-key", value: configuredAPIKey)
            return (baseAPIURL, headers)
        }
    }

    private func gameCacheKey(
        for appID: String,
        source: SteamMetadataSource
    ) -> String {
        "\(source.rawValue):\(GameMetadataLanguage.current.cacheKey):\(appID)"
    }

    private var canFetchMetadata: Bool {
        switch metadataSource {
        case .localOnly:
            return false
        case .steamStore, .localProxy:
            return true
        case .configuredService:
            return isConfiguredMetadataServiceAvailable
        }
    }

    private func cachedGameInfo(
        appID: String,
        source: SteamMetadataSource
    ) -> SteamGameCacheEntry? {
        cache[gameCacheKey(for: appID, source: source)]
    }

    func fetchGameInfo(
        appID: String,
        forceRefresh: Bool = false,
        source sourceOverride: SteamMetadataSource? = nil
    ) async throws -> SteamGame? {
        let source = sourceOverride ?? metadataSource
        let cacheKey = gameCacheKey(for: appID, source: source)
        let cachedEntry = cache[cacheKey]
        if !forceRefresh, let cachedEntry {
            console.cache(appID, key: "gameCache")
            return cachedEntry.game
        }
        console.log("fetching \(appID) metadata")

        do {
            let game: SteamGame?
            switch source {
            case .localOnly:
                throw APIError.missingConfiguration
            case .steamStore:
                game = try await SteamStoreMetadataService.shared.metadata(
                    appID: appID,
                    language: GameMetadataLanguage.current.steamStoreLanguage
                )
            case .localProxy, .configuredService:
                guard let configuration = metadataRequestConfiguration(for: source) else {
                    throw APIError.missingConfiguration
                }
                let urlString = "\(configuration.baseURL)?appid=\(appID)&language=\(GameMetadataLanguage.current.steamStoreLanguage)"
                let data = try await AF.request(
                    urlString,
                    method: .get,
                    headers: configuration.headers
                )
                    .validate(statusCode: 200..<300)
                    .serializingData()
                    .value
                game = try JSONDecoder().decode(SteamGameResponse.self, from: data).data.first
            }

            guard let game else {
                console.warn("Game with id: \(appID) did not return remote metadata")
                return nil
            }
            cache[cacheKey] = SteamGameCacheEntry(game: game, fetchedAt: Date())
            saveGameCache()
            return game
        } catch {
            if let cachedEntry {
                console.warn("Using cached Steam metadata for \(appID)")
                return cachedEntry.game
            }
            throw error
        }
    }

    /// Builds the library immediately from the current source/language cache.
    /// Cached entries remain valid until a caller explicitly forces a refresh.
    func cachedGamesInfo(
        meta: [GamesMeta],
        setProgress: (Double) -> Void = { _ in }
    ) -> [Game] {
        let source = metadataSource
        let total = meta.count
        var items: [Game] = []
        items.reserveCapacity(total)

        progress = 0
        setProgress(progress)

        for (index, gameMeta) in meta.enumerated() {
            let item: Game
            if let cachedEntry = cachedGameInfo(appID: gameMeta.appid, source: source) {
                console.cache(gameMeta.appid, key: "gameCache")
                item = game(from: cachedEntry.game, meta: gameMeta)
            } else {
                item = localGame(
                    from: gameMeta,
                    downloadProgress: downloadProgress(for: gameMeta)
                )
            }
            items.append(item)
            updateProgress(processed: index + 1, total: total, setProgress: setProgress)
        }

        if total == 0 {
            progress = 100
            setProgress(progress)
        }
        console.cacheRelease("The following game's data cache was used", key: "gameCache")
        return items
    }

    /// Refreshes only metadata that is completely missing from the cache.
    /// Each refreshed game is delivered independently so a caller can update
    /// its already-visible library without waiting for the complete batch.
    func refreshGamesInfoIncrementally(
        meta: [GamesMeta],
        setProgress: (Double) -> Void = { _ in },
        onGame: (Game) -> Void
    ) async throws {
        let source = metadataSource
        guard source != .localOnly else {
            progress = 100
            setProgress(progress)
            return
        }

        let metasByAppID = Dictionary(grouping: meta, by: \.appid)
        let candidates = metasByAppID.keys.sorted().filter { appID in
            cachedGameInfo(appID: appID, source: source) == nil
        }
        let total = candidates.count

        progress = 0
        setProgress(progress)
        guard total > 0 else {
            progress = 100
            setProgress(progress)
            return
        }

        for (index, appID) in candidates.enumerated() {
            try Task.checkCancellation()
            do {
                if let gameInfo = try await fetchGameInfo(
                    appID: appID,
                    forceRefresh: true,
                    source: source
                ) {
                    try Task.checkCancellation()
                    for gameMeta in metasByAppID[appID] ?? [] {
                        onGame(game(from: gameInfo, meta: gameMeta))
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                console.warn(
                    "Game with id: \(appID) metadata refresh failed; keeping cached or local metadata"
                )
                console.error(String(reflecting: error))
            }

            updateProgress(processed: index + 1, total: total, setProgress: setProgress)
        }
    }

    func fetchGamesInfo(meta: [GamesMeta], setProgress: @escaping (Double) -> Void = { _ in }) async throws -> [Game] {
        var items: [Game] = []
        let total = meta.count
        let canFetchMetadata = self.canFetchMetadata

        if !canFetchMetadata && !meta.isEmpty {
            console.warn("Steam metadata service is disabled; using local Steam library metadata")
        }

        // Reset progress at start
        self.progress = 0
        setProgress(self.progress)
        
        for (index, meta) in meta.enumerated() {
            let downloadProgress = downloadProgress(for: meta)

            if canFetchMetadata {
                do {
                    if let gameInfo = try await self.fetchGameInfo(appID: meta.appid) {
                        items.append(game(from: gameInfo, meta: meta))
                    } else {
                        items.append(localGame(from: meta, downloadProgress: downloadProgress))
                    }
                } catch {
                    console.warn("Game with id: \(meta.appid) metadata request failed; using local metadata")
                    console.error(String(reflecting: error))
                    items.append(localGame(from: meta, downloadProgress: downloadProgress))
                }
            } else {
                items.append(localGame(from: meta, downloadProgress: downloadProgress))
            }

            updateProgress(processed: index + 1, total: total, setProgress: setProgress)
        }
        // Ensure progress is 100% at completion when there were items to process
        if total > 0 {
            self.progress = 100
            setProgress(self.progress)
        }
        console.cacheRelease("The following game's data cache was used", key: "gameCache")
        return items
    }

    private func downloadProgress(for meta: GamesMeta) -> Double {
        let bDownloaded = Double(meta.BytesDownloaded ?? "0") ?? 0
        let bToDownload = Double(meta.BytesToDownload ?? "0") ?? 0
        let bStaged = Double(meta.BytesStaged ?? "0") ?? 0
        let bToStage = Double(meta.BytesToStage ?? "0") ?? 0

        if meta.isDownloaded() {
            return 100
        }
        if bToStage > 0, bDownloaded >= bToDownload {
            return min(max((bStaged / bToStage) * 100, 0), 100)
        }
        if bToDownload > 0 {
            return min(max((bDownloaded / bToDownload) * 100, 0), 100)
        }
        return 0
    }

    private func game(from gameInfo: SteamGame, meta: GamesMeta) -> Game {
        var game = Game(
            from: gameInfo,
            id: meta.id,
            isNative: meta.isNative,
            downloadProgress: downloadProgress(for: meta),
            isInstalled: !meta.installdir.isEmpty && meta.isDownloaded(),
            appNames: meta.appNames
        )
        game.nativeAppBundleIdentifier = meta.nativeAppBundleIdentifier
        game.isFromNativeSteamLibrary = meta.isFromNativeSteamLibrary
        return game
    }

    private func updateProgress(
        processed: Int,
        total: Int,
        setProgress: (Double) -> Void
    ) {
        guard total > 0 else { return }
        progress = (Double(processed) / Double(total)) * 100
        setProgress(progress)
    }

    private func localGame(from meta: GamesMeta, downloadProgress: Double) -> Game {
        var game = Game.emptyGame
        let appID = Int(meta.appid) ?? 0
        let name = meta.name?.trimmingCharacters(in: .whitespacesAndNewlines)

        game.id = meta.id
        game.isNative = meta.isNative
        game.downloadProgress = downloadProgress
        game.isInstalled = !meta.installdir.isEmpty && meta.isDownloaded()
        game.appNames = meta.appNames
        game.nativeAppBundleIdentifier = meta.nativeAppBundleIdentifier
        game.isFromNativeSteamLibrary = meta.isFromNativeSteamLibrary
        game.name = name?.isEmpty == false ? name! : "Steam App \(meta.appid)"
        game.steamAppID = appID
        if appID == 228980 {
            game.type = "tool"
        }
        game.headerImage = appID > 0
            ? "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/header.jpg"
            : ""
        if meta.installdir.isEmpty {
            // An owned-only librarycache entry has no local manifest and does
            // not tell us which platforms Steam ships. Keep it unknown until
            // cached or refreshed Store metadata arrives.
            game.platforms = Platforms(windows: false, mac: false, linux: false)
        } else {
            game.platforms = Platforms(
                windows: !meta.isNative,
                mac: meta.isNative,
                linux: false
            )
        }
        return game
    }

    func fetchAutoConfig(steamID: String) async throws -> GameOptionsData {
        try validateAPIConfiguration()
        if let cached = autoConfigCache[steamID] {
            console.log("Using cached auto configuration for \(steamID)")
            return cached
        }

        let headers: HTTPHeaders = [
            "x-api-key": apiKey,
            "Accept-Language": GameMetadataLanguage.current.acceptLanguage
        ]
        let data = try await AF.request(
            "\(baseAPIURL)/settings/",
            method: .get,
            parameters: ["steamID": steamID],
            headers: headers
        )
            .validate(statusCode: 200..<300)
            .serializingData()
            .value
        let autoConfig = try JSONDecoder()
            .decode(GameOptionsDataResponse.self, from: data)
            .data
        autoConfigCache[steamID] = autoConfig
        return autoConfig
    }

    func fetchOwnedGamesIDs(
        userID: String,
        identityCacheKey: String? = nil
    ) async throws -> [String] {
        try validateAPIConfiguration()
        let cacheKey = identityCacheKey ?? userID
        if let cachedIDs = cacheOwnedGamesIDs[cacheKey] {
            console.log("Using cached user data")
            return cachedIDs
        }
        let urlString = "\(baseAPIURL)/ownedGames/?userid=\(userID)"
        let headers: HTTPHeaders = [
            "x-api-key": configuredAPIKey,
            "Accept-Language": GameMetadataLanguage.current.acceptLanguage
        ]

        do {
            let data = try await AF.request(urlString, method: .get, headers: headers)
                .validate(statusCode: 200..<300)
                .serializingData()
                .value
            
            let root = try JSONDecoder().decode(SteamOwnedGamesResponseData.self, from: data)
            let ids = root.data.response.games.map { String($0.appID) }
            self.cacheOwnedGamesIDs[cacheKey] = ids
            self.saveOwnedGamesIDsCache()
            return ids
        }
    }
    func fetchProfileDetails(
        userID: String,
        identityCacheKey: String? = nil
    ) async throws -> UserInfo? {
        try validateAPIConfiguration()
        let cacheKey = identityCacheKey ?? userID
        if let cachedProfile = cacheProfileData[cacheKey] {
            console.log("Using cached user data")
            return cachedProfile
        }
        let urlString = "\(baseAPIURL)/profile/?userid=\(userID)"
        let headers: HTTPHeaders = [
            "x-api-key": apiKey,
            "Accept-Language": GameMetadataLanguage.current.acceptLanguage
        ]

        do {
            let data = try await AF.request(urlString, method: .get, headers: headers)
                .validate(statusCode: 200..<300)
                .serializingData()
                .value
            
            let root = try JSONDecoder().decode(UserInfoResponse.self, from: data)
            guard let profileData = root.data.first else { return nil }
            self.cacheProfileData[cacheKey] = profileData
            self.saveProfileDataCache()
            return profileData
        } catch {
            console.error(String(reflecting: error))
            return nil
        }
    }
}

final class CustomGameAPI {
    var game: Game?
    private var cache: [String: Game] = [:]
    
    init() {
        //@TO DO: load cache
    }
    func fetch(hints: String) async throws -> Game? {
        try validateAPIConfiguration()
        let urlString = "\(baseAPIURL)/custom"
        let headers: HTTPHeaders = [
            "x-api-key": configuredAPIKey,
            "Accept-Language": GameMetadataLanguage.current.acceptLanguage
        ]
        let data = try await AF.request(
            urlString,
            method: .post,
            parameters: [
                "hints": hints,
                "language": GameMetadataLanguage.current.steamStoreLanguage
            ],
            headers: headers
        ) { $0.timeoutInterval = 120 }
            .validate(statusCode: 200..<300)
            .serializingData()
            .value
        print("fetching custom game")
        let root = try JSONDecoder().decode(GameResponse.self, from: data)
        
//        cache[appID] = root.data[0]
//        saveGameCache()
        return root.data
    }
}
