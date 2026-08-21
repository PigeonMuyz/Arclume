//
//  Types.swift
//  Procyon
//
//  Created by Italo Mandara on 19/02/2026.
//

import Foundation
import Combine

typealias DropdownOptions = [(id: String, label: String)]

var cxGraphicsBackend: DropdownOptions {
    [
        (id: "dxmt", label: "DXMT"),
        (id: "d3dmetal3", label: "D3Dmetal3"),
        (id: "d3dmetal4", label: "D3DMetal 4 (Beta 2)"),
        (id: "wined3d", label: "Wine"),
        (id: "dxvk", label: "DXVK"),
        (id: "auto", label: L10n.string("Auto"))
    ]
}

var cxVulkanBackend: DropdownOptions {
    [
        (id: "", label: L10n.string("Standard")),
        (id: "latest", label: L10n.string("Latest")),
        (id: "experimental", label: L10n.string("Experimental")),
        (id: "dbh", label: "Detroit Become Human"),
//      (id: "kosmickrisp", label: "KosmicKrisp")
    ]
}

enum OnOff: String {
    case off = "0"
    case on = "1"
}

typealias CXDrives = [String: URL]

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: Self { self }

    var locale: Locale {
        switch self {
        case .system:
            return .current
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    var resourceLocalization: String? {
        switch self {
        case .simplifiedChinese:
            return "zh-Hans"
        case .system, .english:
            return nil
        }
    }

    var title: String {
        switch self {
        case .system:
            return L10n.string("System Default")
        case .english:
            return L10n.string("English")
        case .simplifiedChinese:
            return L10n.string("Simplified Chinese")
        }
    }
}

enum GameMetadataLanguage: String {
    case english
    case simplifiedChinese

    static var current: Self {
        let storedValue = UserDefaults(suiteName: suiteName)?
            .string(forKey: "appLanguage")
        let selectedLanguage = AppLanguage(rawValue: storedValue ?? "") ?? .system

        switch selectedLanguage {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        case .system:
            return Locale.current.identifier.lowercased().hasPrefix("zh")
                ? .simplifiedChinese
                : .english
        }
    }

    var cacheKey: String { rawValue }

    var steamStoreLanguage: String {
        switch self {
        case .english:
            return "english"
        case .simplifiedChinese:
            return "schinese"
        }
    }

    var appleStorefront: String {
        switch self {
        case .english:
            return "us"
        case .simplifiedChinese:
            return "cn"
        }
    }

    var acceptLanguage: String {
        switch self {
        case .english:
            return "en-US"
        case .simplifiedChinese:
            return "zh-Hans-CN"
        }
    }
}

var isAppleAppStoreMetadataEnabled: Bool {
    let defaults = UserDefaults(suiteName: suiteName)
    guard defaults?.object(forKey: "appleAppStoreMetadataEnabled") != nil else {
        return true
    }
    return defaults?.bool(forKey: "appleAppStoreMetadataEnabled") ?? true
}

final class AppSettings: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults(suiteName: suiteName)?
                .set(language.rawValue, forKey: "appLanguage")
        }
    }

    init() {
        let storedValue = UserDefaults(suiteName: suiteName)?
            .string(forKey: "appLanguage")
        self.language = AppLanguage(rawValue: storedValue ?? "") ?? .system
    }
}

nonisolated struct GameOptionsData: Codable { // this is used for reading saved properties
    var cxGraphicsBackend: String?
    var wineMSync: Bool?
    var mtlHudEnabled: Bool?
    var d3dMtl4Enabled: Bool?
    var dlssFrameGenerationEnabled: Bool?
    var externalQualitySettingsEnabled: Bool?
    var closeLauncherWhenGameStarts: Bool?
    var dx9PatchEnabled: Bool?
    var gameArguments: String?
    var dxmtPreferredMaxFrameRate: Double?
    var dxmtMetalFXSpatial: Bool?
    var dxmtMetalSpatialUpscaleFactor: Double?
    var advertiseAVX: Bool?
    var envVariables: String?
    var enableSDL: Bool?
    var disableHidraw: Bool?
    var ue4Hack: Bool?
    var mvkArgBuff: Bool?
    var vulkanLib: String?
    var dxvk: String?
    var wineEsync: String?
    var d3dMEnableMetalFX: String?
    var d3dSupportDXR: String?
    var d3dMaxFPS: Double?
    
    @MainActor
    init(data: GameOptions) {
        self.cxGraphicsBackend = data.cxGraphicsBackend
        self.wineMSync = data.wineMSync
        self.mtlHudEnabled = data.mtlHudEnabled
        self.dlssFrameGenerationEnabled = data.dlssFrameGenerationEnabled
        self.externalQualitySettingsEnabled = data.externalQualitySettingsEnabled
        self.closeLauncherWhenGameStarts = data.closeLauncherWhenGameStarts
        self.dx9PatchEnabled = data.dx9PatchEnabled
        self.gameArguments = data.gameArguments
        self.dxmtPreferredMaxFrameRate = data.dxmtPreferredMaxFrameRate
        self.dxmtMetalFXSpatial = data.dxmtMetalFXSpatial
        self.dxmtMetalSpatialUpscaleFactor = data.dxmtMetalSpatialUpscaleFactor
        self.advertiseAVX = data.advertiseAVX
        self.envVariables = data.envVariables
        self.enableSDL = data.enableSDL
        self.disableHidraw = data.disableHidraw
        self.ue4Hack = data.ue4Hack
        self.mvkArgBuff = data.mvkArgBuff
        self.vulkanLib = data.vulkanLib
        self.dxvk = data.dxvk
        self.wineEsync = data.wineEsync
        self.d3dMEnableMetalFX = data.d3dMEnableMetalFX
        self.d3dSupportDXR = data.d3dSupportDXR
        self.d3dMtl4Enabled = data.d3dMtl4Enabled
        self.d3dMaxFPS = data.d3dMaxFPS
    }
}

class GameOptions: ObservableObject { // this is used as form state
    @Published var cxGraphicsBackend: String
    @Published var wineMSync: Bool
    @Published var mtlHudEnabled: Bool
    @Published var dlssFrameGenerationEnabled: Bool
    @Published var externalQualitySettingsEnabled: Bool
    @Published var closeLauncherWhenGameStarts: Bool
    @Published var dx9PatchEnabled: Bool
    @Published var gameArguments: String
    @Published var dxmtPreferredMaxFrameRate: Double
    @Published var dxmtMetalFXSpatial: Bool
    @Published var dxmtMetalSpatialUpscaleFactor: Double
    @Published var advertiseAVX: Bool
    @Published var envVariables: String
    @Published var enableSDL: Bool
    @Published var disableHidraw: Bool
    @Published var ue4Hack: Bool
    @Published var mvkArgBuff: Bool
    @Published var vulkanLib: String
    @Published var dxvk: String?
    @Published var wineEsync: String?
    @Published var d3dMEnableMetalFX: String?
    @Published var d3dSupportDXR: String?
    @Published var d3dMtl4Enabled: Bool
    @Published var d3dMaxFPS: Double
    
    init(cxGraphicsBackend: String = "d3dmetal", wineMSync: Bool = true, mtlHudEnabled: Bool = false, d3dMtl4Enabled: Bool = false, dx9PatchEnabled: Bool = false, gameArguments: String = "", dxmtPreferredMaxFrameRate: Double = 0, dxmtMetalFXSpatial: Bool = false, dxmtMetalSpatialUpscaleFactor: Double = 1.0, advertiseAVX: Bool = true, envVariables: String = "", sdlEnabled: Bool = true, hidrawDisabled: Bool = false, ue4Hack: Bool = true, mvkArgBuff: Bool = true, vulkanLib: String = "latest", dxvk: String? = nil, wineEsync: String? = nil, d3dMEnableMetalFX: String? = nil, d3dMaxFPS: Double = 0, d3dSupportDXR: String? = nil, dlssFrameGenerationEnabled: Bool = false, externalQualitySettingsEnabled: Bool = false, closeLauncherWhenGameStarts: Bool = false) {
        self.cxGraphicsBackend = cxGraphicsBackend
        self.wineMSync = wineMSync
        self.mtlHudEnabled = mtlHudEnabled
        self.dlssFrameGenerationEnabled = dlssFrameGenerationEnabled
        self.externalQualitySettingsEnabled = externalQualitySettingsEnabled
        self.closeLauncherWhenGameStarts = closeLauncherWhenGameStarts
        self.dx9PatchEnabled = dx9PatchEnabled
        self.gameArguments = gameArguments
        self.dxmtMetalFXSpatial = dxmtMetalFXSpatial
        self.dxmtMetalSpatialUpscaleFactor = dxmtMetalSpatialUpscaleFactor
        self.dxmtPreferredMaxFrameRate = dxmtPreferredMaxFrameRate
        self.advertiseAVX = advertiseAVX
        self.envVariables = envVariables
        self.enableSDL = sdlEnabled
        self.disableHidraw = hidrawDisabled
        self.ue4Hack = ue4Hack
        self.mvkArgBuff = mvkArgBuff
        self.vulkanLib = vulkanLib
        self.dxvk = dxvk
        self.wineEsync = wineEsync
        self.d3dMEnableMetalFX = d3dMEnableMetalFX
        self.d3dSupportDXR = d3dSupportDXR
        self.d3dMtl4Enabled = d3dMtl4Enabled
        self.d3dMaxFPS = d3dMaxFPS
    }
    
    func set(data: GameOptionsData) {
        let defaults = GameOptions()
        self.cxGraphicsBackend = data.cxGraphicsBackend ?? defaults.cxGraphicsBackend
        self.wineMSync = data.wineMSync ?? defaults.wineMSync
        self.mtlHudEnabled = data.mtlHudEnabled ?? defaults.mtlHudEnabled
        self.dlssFrameGenerationEnabled = data.dlssFrameGenerationEnabled
            ?? defaults.dlssFrameGenerationEnabled
        self.externalQualitySettingsEnabled = data.externalQualitySettingsEnabled
            ?? defaults.externalQualitySettingsEnabled
        self.closeLauncherWhenGameStarts = data.closeLauncherWhenGameStarts
            ?? defaults.closeLauncherWhenGameStarts
        self.dx9PatchEnabled = data.dx9PatchEnabled ?? defaults.dx9PatchEnabled
        self.gameArguments = data.gameArguments ?? defaults.gameArguments
        self.dxmtMetalFXSpatial = data.dxmtMetalFXSpatial ?? defaults.dxmtMetalFXSpatial
        self.dxmtMetalSpatialUpscaleFactor = data.dxmtMetalSpatialUpscaleFactor
            ?? defaults.dxmtMetalSpatialUpscaleFactor
        self.dxmtPreferredMaxFrameRate = data.dxmtPreferredMaxFrameRate
            ?? defaults.dxmtPreferredMaxFrameRate
        self.advertiseAVX = data.advertiseAVX ?? defaults.advertiseAVX
        self.envVariables = data.envVariables ?? defaults.envVariables
        self.enableSDL = data.enableSDL ?? defaults.enableSDL
        self.disableHidraw = data.disableHidraw ?? defaults.disableHidraw
        self.ue4Hack = data.ue4Hack ?? defaults.ue4Hack
        self.mvkArgBuff = data.mvkArgBuff ?? defaults.mvkArgBuff
        self.vulkanLib = data.vulkanLib ?? defaults.vulkanLib
        self.dxvk = data.dxvk
        self.wineEsync = data.wineEsync
        self.d3dMEnableMetalFX = data.d3dMEnableMetalFX
        self.d3dSupportDXR = data.d3dSupportDXR
        self.d3dMtl4Enabled = data.d3dMtl4Enabled ?? defaults.d3dMtl4Enabled
        self.d3dMaxFPS = data.d3dMaxFPS ?? defaults.d3dMaxFPS
    }

    func importAutoConfig(data: GameOptionsData) {
        if let value = data.cxGraphicsBackend { cxGraphicsBackend = value }
        if let value = data.wineMSync { wineMSync = value }
        if let value = data.mtlHudEnabled { mtlHudEnabled = value }
        if let value = data.dlssFrameGenerationEnabled {
            dlssFrameGenerationEnabled = value
        }
        if let value = data.externalQualitySettingsEnabled {
            externalQualitySettingsEnabled = value
        }
        if let value = data.closeLauncherWhenGameStarts {
            closeLauncherWhenGameStarts = value
        }
        if let value = data.dx9PatchEnabled { dx9PatchEnabled = value }
        if let value = data.gameArguments { gameArguments = value }
        if let value = data.dxmtMetalFXSpatial { dxmtMetalFXSpatial = value }
        if let value = data.dxmtMetalSpatialUpscaleFactor {
            dxmtMetalSpatialUpscaleFactor = value
        }
        if let value = data.dxmtPreferredMaxFrameRate {
            dxmtPreferredMaxFrameRate = value
        }
        if let value = data.advertiseAVX { advertiseAVX = value }
        if let value = data.envVariables { envVariables = value }
        if let value = data.enableSDL { enableSDL = value }
        if let value = data.disableHidraw { disableHidraw = value }
        if let value = data.ue4Hack { ue4Hack = value }
        if let value = data.mvkArgBuff { mvkArgBuff = value }
        if let value = data.vulkanLib { vulkanLib = value }
        if let value = data.dxvk { dxvk = value }
        if let value = data.wineEsync { wineEsync = value }
        if let value = data.d3dMEnableMetalFX { d3dMEnableMetalFX = value }
        if let value = data.d3dSupportDXR { d3dSupportDXR = value }
        if let value = data.d3dMtl4Enabled { d3dMtl4Enabled = value }
        if let value = data.d3dMaxFPS { d3dMaxFPS = value }
    }
}

class GamesMeta: SteamACFMeta {
    var gameURL: URL?
    var libraryFolder: URL
    var isNative: Bool
    var appNames: [String]
    var nativeAppBundleIdentifier: String?
    var isFromNativeSteamLibrary: Bool?
    var id: String { libraryFolder.relativeString + appid }
    func isDownloaded() -> Bool {
        if let stateFlags = self.StateFlags.flatMap(UInt64.init) {
            return stateFlags & (1 << 2) != 0
        }
        return (self.BytesToDownload == "0" || self.BytesToDownload == self.BytesDownloaded)
    }
    
    init(appid: String, installdir: String, gameURL: URL? = nil, isNative: Bool = false, libraryFolder: URL = URL(string: "/")!, bytesDownloaded: String, BytesTodownload: String, appNames: [String] = []) {
        self.gameURL = gameURL
        self.isNative = isNative
        self.libraryFolder = libraryFolder
        self.appNames = appNames
        self.nativeAppBundleIdentifier = nil
        self.isFromNativeSteamLibrary = nil
        super.init()
        self.appid = appid
        self.installdir = installdir
        self.BytesDownloaded = bytesDownloaded
        self.BytesToDownload = BytesTodownload
        self.appNames = appNames
    }
}

struct Game: Identifiable, Codable {
    var id: String
    var isNative: Bool
    var downloadProgress: Double
    var isInstalled: Bool
    var appNames: [String] = []
    var appExeURL: URL?
    var isCustom: Bool?
    var isNativeAppImport: Bool?
    var nativeAppBundleIdentifier: String?
    var appStoreMetadataLanguage: String?
    var steamMetadataLink: SteamMetadataLink?
    var isFromNativeSteamLibrary: Bool?
    
    // taken from SteamGame
    var type: String
    var name: String
    var steamAppID: Int
    let requiredAge: String
    let isFree: Bool
    var controllerSupport: String?
    let dlc: [Int]?
    
    var detailedDescription: String
    var aboutTheGame: String
    var shortDescription: String
    let supportedLanguages: String?
    
    var headerImage: String
    let capsuleImage: String
    let capsuleImageV5: String?
    let website: String?
    
    let pcRequirements: Requirements?
    let macRequirements: Requirements?
    let linuxRequirements: Requirements?
    
    let legalNotice: String?
    var developers: [String]
    var publishers: [String]
    
    let priceOverview: PriceOverview?
    let packages: [Int]?
    let packageGroups: [PackageGroup]?
    
    var platforms: Platforms
    let metacritic: Metacritic?
    
    var categories: [Category]
    var genres: [Genre]?
    
    var screenshots: [Screenshot]?
    var movies: [Movie]?
    
    let recommendations: Recommendations?
    let achievements: Achievements?
    let releaseDate: ReleaseDate
    let supportInfo: SupportInfo?
    
    let background: String?
    let backgroundRaw: String?
    
    let contentDescriptors: ContentDescriptors?
    let ratings: [String: RatingBody]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case isNative = "is_native"
        case downloadProgress = "download_progress"
        case isInstalled = "is_installed"
        case appNames = "app_names"
        case appExeURL = "app_exe_url"
        case isCustom = "is_custom"
        case isNativeAppImport = "is_native_app_import"
        case nativeAppBundleIdentifier = "native_app_bundle_identifier"
        case appStoreMetadataLanguage = "app_store_metadata_language"
        case steamMetadataLink = "steam_metadata_link"
        case isFromNativeSteamLibrary = "is_from_native_steam_library"
        
        case type
        case name
        case steamAppID = "steam_app_id"
        case requiredAge = "required_age"
        case isFree = "is_free"
        case controllerSupport = "controller_support"
        case dlc
        
        case detailedDescription = "detailed_description"
        case aboutTheGame = "about_the_game"
        case shortDescription = "short_description"
        case supportedLanguages = "supported_languages"
        
        case headerImage = "header_image"
        case capsuleImage = "capsule_image"
        case capsuleImageV5 = "capsule_image_v5"
        case website
        
        case pcRequirements = "pc_requirements"
        case macRequirements = "mac_requirements"
        case linuxRequirements = "linux_requirements"
        
        case legalNotice = "legal_notice"
        case developers
        case publishers
        
        case priceOverview = "price_overview"
        case packages
        case packageGroups = "package_groups"
        
        case platforms
        case metacritic
        
        case categories
        case genres
        
        case screenshots
        case movies
        
        case recommendations
        case achievements
        case releaseDate = "release_date"
        case supportInfo = "support_info"
        
        case background
        case backgroundRaw = "background_raw"
        
        case contentDescriptors = "content_descriptors"
        case ratings
    }
    
    init(from: SteamGame, id: String, isNative: Bool, downloadProgress: Double, isInstalled: Bool, appNames: [String], isCustom: Bool? = false) {
        self.id = id
        self.isNative = isNative
        self.downloadProgress = downloadProgress
        self.isInstalled = isInstalled
        self.appNames = appNames
        self.isCustom = isCustom
        self.isNativeAppImport = false
        self.nativeAppBundleIdentifier = nil
        self.appStoreMetadataLanguage = nil
        self.steamMetadataLink = nil
        self.isFromNativeSteamLibrary = nil
        
        // SteamGame property
        self.type = from.type
        self.name = from.name
        self.steamAppID = from.steamAppID
        self.requiredAge = from.requiredAge
        self.isFree = from.isFree
        self.controllerSupport = from.controllerSupport
        self.dlc = from.dlc
        
        self.detailedDescription = from.detailedDescription
        self.aboutTheGame = from.aboutTheGame
        self.shortDescription = from.shortDescription
        self.supportedLanguages = from.supportedLanguages
        
        self.headerImage = from.headerImage
        self.capsuleImage = from.capsuleImage
        self.capsuleImageV5 = from.capsuleImageV5
        self.website = from.website
        
        self.pcRequirements = from.pcRequirements
        self.macRequirements = from.macRequirements
        self.linuxRequirements = from.linuxRequirements
        
        self.legalNotice = from.legalNotice
        self.developers = from.developers ?? []
        self.publishers = from.publishers ?? []
        
        self.priceOverview = from.priceOverview
        self.packages = from.packages
        self.packageGroups = from.packageGroups
        
        self.platforms = from.platforms
        self.metacritic = from.metacritic
        
        self.categories = from.categories ?? []
        self.genres = from.genres
        
        self.screenshots = from.screenshots
        self.movies = from.movies
        
        self.recommendations = from.recommendations
        self.achievements = from.achievements
        self.releaseDate = from.releaseDate
        self.supportInfo = from.supportInfo
        
        self.background = from.background
        self.backgroundRaw = from.backgroundRaw
        
        self.contentDescriptors = from.contentDescriptors
        self.ratings = from.ratings
    }
}

extension Game {
    var isSteamTool: Bool {
        type.caseInsensitiveCompare("tool") == .orderedSame || steamAppID == 228980
    }

    var isDirectNativeApplication: Bool {
        guard isNative, let appExeURL else { return false }
        return NativeApplicationBundleDetector.application(at: appExeURL) != nil
    }

    /// Whether this library entry will actually use the Windows/CrossOver path.
    /// Official macOS support alone is not enough: an installed non-native copy
    /// still uses CrossOver, while an uninstalled Mac build should not inherit
    /// an unrelated CrossOver compatibility label.
    var usesCrossOverRuntime: Bool {
        guard !isNative,
              isFromNativeSteamLibrary != true,
              platforms.windows
        else {
            return false
        }
        if isInstalled || appExeURL != nil { return true }
        return !platforms.mac
    }

    var supportsCrossOverCompatibility: Bool {
        usesCrossOverRuntime
    }

    func steamInstallDestination(
        nativeSteamAvailable: Bool,
        containerSteamAvailable: Bool
    ) -> SteamInstallDestination {
        guard steamAppID > 0, !isSteamTool else { return .unavailable }
        if platforms.mac, nativeSteamAvailable {
            return .nativeSteam
        }
        if platforms.windows, containerSteamAvailable {
            return .containerSteam
        }
        return .unavailable
    }

    func steamInstallDestination(
        nativeSteamAvailable: Bool,
        containerSteamAvailable: Bool,
        ownership: Set<SteamClientKind>
    ) -> SteamInstallDestination {
        guard steamAppID > 0, !isSteamTool else { return .unavailable }

        let nativeOwnedAndAvailable = nativeSteamAvailable
            && ownership.contains(.native)
        let containerOwnedAndAvailable = containerSteamAvailable
            && ownership.contains(.container)

        if platforms.mac, nativeOwnedAndAvailable {
            return .nativeSteam
        }
        if platforms.windows, containerOwnedAndAvailable {
            return .containerSteam
        }

        // Some local/cache-only entries do not yet have reliable platform
        // metadata. In that case ownership is a safer routing signal than an
        // empty platform set. Known platform/account mismatches remain blocked.
        if !platforms.mac && !platforms.windows {
            if nativeOwnedAndAvailable {
                return .nativeSteam
            }
            if containerOwnedAndAvailable {
                return .containerSteam
            }
        }
        return .unavailable
    }
}

extension Game {
    static let steamMock = SteamGame(
        type: "game",
        name: "Mock Game",
        steamAppID: 720,
        requiredAge: "18",
        isFree: false,
        controllerSupport: "full",
        dlc: [1111, 2222],
        detailedDescription: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua .\nUt enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. \nExcepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        aboutTheGame: "About the mock game: fast-paced, fun, and engaging.",
        shortDescription: "A short description of the mock game.",
        supportedLanguages: "English, French, German",
        headerImage: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/440/header.jpg",
        capsuleImage: "https://placehold.co/600x400/orange/white",
        capsuleImageV5: "https://placehold.co/600x400/orange/white",
        website: "https://example.com",
        pcRequirements: Requirements(minimum: "Windows 10, 8GB RAM", recommended: "Windows 11, 16GB RAM"),
        macRequirements: Requirements(minimum: "macOS 13, 8GB RAM", recommended: "macOS 14, 16GB RAM"),
        linuxRequirements: Requirements(minimum: "Ubuntu 22.04, 8GB RAM", recommended: "Ubuntu 24.04, 16GB RAM"),
        legalNotice: "All trademarks are property of their respective owners.",
        developers: ["Mock Dev Studio"],
        publishers: ["Mock Publisher"],
        priceOverview: PriceOverview(
            currency: "USD",
            initial: 1999,
            final: 999,
            discountPercent: 50,
            initialFormatted: "$19.99",
            finalFormatted: "$9.99"
        ),
        packages: [3333, 4444],
        packageGroups: [
            PackageGroup(
                name: "default",
                title: "Standard Edition",
                description: "Base game package",
                selectionText: "Select a purchase option",
                displayType: "0",
                subs: [
                    PackageSub(
                        packageID: 3333,
                        optionText: "Base Game",
                        isFreeLicense: false,
                        priceInCentsWithDiscount: 999
                    )
                ]
            )
        ],
        platforms: Platforms(windows: true, mac: true, linux: true),
        metacritic: Metacritic(score: 85, url: "https://metacritic.example.com/mockgame"),
        categories: [
            Category(id: 1, description: "Single-player"),
            Category(id: 2, description: "Online Co-op")
        ],
        genres: [
            Genre(id: "1", description: "Action"),
            Genre(id: "2", description: "Adventure")
        ],
        screenshots: [
            Screenshot(id: 1, pathThumbnail: "https://placehold.co/600x400/orange/white", pathFull: "https://placehold.co/600x400/orange/white"),
            Screenshot(id: 2, pathThumbnail: "https://placehold.co/600x400/orange/white", pathFull: "https://placehold.co/600x400/orange/white")
        ],
        movies: [
            Movie(id: 10, name: "Trailer", thumbnail: "https://example.com/trailer_thumb.jpg", dashH264: "https://video.akamai.steamstatic.com/store_trailers/440/129304/a9d97ffaf28cac468369400c12abe442a7b688b2/1749861261/dash_h264.mpd", hlsH264: "https://video.akamai.steamstatic.com/store_trailers/440/129304/a9d97ffaf28cac468369400c12abe4427b688b2/1749861261/hls_264_master.m3u8", highlight: true)
        ],
        recommendations: Recommendations(total: 12345),
        achievements: Achievements(
            total: 100,
            highlighted: [Achievement(name: "First Steps", path: "https://placehold.co/600x400/orange/white")]
        ),
        releaseDate: ReleaseDate(comingSoon: false, date: "Jan 01, 2026"),
        supportInfo: SupportInfo(url: "https://support.example.com", email: "support@example.com"),
        background: "https://placehold.co/600x400/orange/white",
        backgroundRaw: "https://placehold.co/600x400",
        contentDescriptors: ContentDescriptors(ids: [1, 2, 3], notes: "Contains mild violence"),
        ratings: [
            "esrb": RatingBody(rating: "T", requiredAge: "13", descriptors: "Violence"),
            "pegi": RatingBody(rating: "16", requiredAge: "16", descriptors: "Violence"),
            "usk": RatingBody(rating: "12", requiredAge: "12", descriptors: "Violence")
        ]
    )
    static let mock = Game(from: Game.steamMock, id: "example", isNative: true, downloadProgress: 100, isInstalled: true, appNames: ["test.exe"], isCustom: true)
    static let steamEmptyGame = SteamGame(
        type: "game",
        name: "",
        steamAppID: 0,
        requiredAge: "0",
        isFree: false,
        controllerSupport: nil,
        dlc: [],
        detailedDescription: "",
        aboutTheGame: "",
        shortDescription: "",
        supportedLanguages: nil,
        headerImage: "",
        capsuleImage: "",
        capsuleImageV5: nil,
        website: "",
        pcRequirements: nil,
        macRequirements: nil,
        linuxRequirements: nil,
        legalNotice: nil,
        developers: [],
        publishers: [],
        priceOverview: nil,
        packages: [],
        packageGroups: [],
        platforms: Platforms(windows: false, mac: true, linux: false),
        metacritic: nil,
        categories: [],
        genres: [],
        screenshots: nil,
        movies: nil,
        recommendations: nil,
        achievements: nil,
        releaseDate: ReleaseDate(comingSoon: false, date: ""),
        supportInfo: nil,
        background: nil,
        backgroundRaw: nil,
        contentDescriptors: nil,
        ratings: nil
    )
    static let emptyGame = Game(from: Game.steamEmptyGame, id: "example", isNative: true, downloadProgress: 100, isInstalled: true, appNames: ["test.exe"])
}

struct GameResponse: Codable, Sendable {
    let data: Game
}

enum SortingOptions {
    case name
    case releaseDate
    case publisher
    case developer
    case installed
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case installed
    case all
    case playableOnMac

    var id: Self { self }

    var title: String {
        switch self {
        case .installed:
            return L10n.string("Installed")
        case .all:
            return L10n.string("All Games")
        case .playableOnMac:
            return L10n.string("Mac Compatible")
        }
    }
}

nonisolated enum SteamInstallDestination: Equatable {
    case nativeSteam
    case containerSteam
    case unavailable
}

class LibraryPageGlobals: ObservableObject {
    private static let linkedSteamMetadataDefaultsKey = "linkedSteamMetadata.v1"

    @Published var gamesMeta: [GamesMeta] = []
    @Published var folders: [String] = []
    @Published var showOptions: Bool = false
    @Published var showTools: Bool = false
    @Published var filter: String = ""
    @Published var showDetailView = false
    @Published var selectedGame: Game? = nil
    @Published var showCustomGameEditor = false
    @Published var editingCustomGameID: String?
    @Published var isLaunchingGame: Bool = false
    @Published var launchErrorMessage: String?
    @Published var customAddedGames: [Game] = []
    @Published var games: [Game] = []
    @Published var ownershipByAppID: [Int: Set<SteamClientKind>] = [:]
    @Published var ownershipSessionCacheKeys: [SteamClientKind: String] = [:]
    @Published private(set) var linkedSteamMetadata: [String: SteamGame] = [:]
    @Published var sortBy: SortingOptions = SortingOptions.name
    @Published var libraryFilter: LibraryFilter = .installed
    @Published var playingID: String?
    @Published var jx3RuntimeActivity: JX3RuntimeActivity = .idle
    
    init() {
        // 剑网3模式与普通版共用 Bundle ID，因此也会共用这份已保存的
        // 手动游戏列表。剑网3模式不应先显示它们、再等待异步扫描清空。
        if !OnlineGameMode.isEnabled {
            self.loadCustomAddedGames()
        }
        self.loadLinkedSteamMetadata()
    }
    
    var allGamesCount: Int {
        allGames.count
    }
    
    var allGames: [Game] {
        // Keep the standard-edition list on disk untouched, while making the
        // online-only edition's library exclusively discovery-driven.
        if OnlineGameMode.isEnabled {
            return self.games.filter { !$0.isSteamTool }
        }
        return (self.games + self.customAddedGames.map(resolvedCustomGame)).filter {
            !$0.isSteamTool
        }
    }
    
    var filteredGames: [Game] {
        return filteredGames { game in
            game.isNative || game.platforms.mac
        }
    }

    func filteredGames(isPlayableOnMac: (Game) -> Bool) -> [Game] {
        var games = allGames
        let searchTerm = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !searchTerm.isEmpty

        if isSearching {
            games = games.filter { item in
                item.name.localizedCaseInsensitiveContains(searchTerm)
            }
        }

        games = games.filter { item in
            switch libraryFilter {
            case .installed:
                // Searching intentionally expands beyond installed games so an
                // owned title can be found and installed without changing the
                // user's default library view.
                return isSearching || item.isInstalled
            case .all:
                return true
            case .playableOnMac:
                return (isSearching || item.isInstalled) && isPlayableOnMac(item)
            }
        }

        return games.sorted { lhs, rhs in
            switch self.sortBy {
            case SortingOptions.name:
                return lhs.name.lowercased() < rhs.name.lowercased()
            case .releaseDate:
                return lhs.releaseDate.date < rhs.releaseDate.date
            case .publisher:
                if(lhs.publishers.isEmpty) && (!rhs.publishers.isEmpty) { return false }
                if(!lhs.publishers.isEmpty) && (rhs.publishers.isEmpty) { return true }
                return lhs.publishers[0].lowercased() < rhs.publishers[0].lowercased()
            case .developer:
                if(lhs.developers.isEmpty) && (!rhs.developers.isEmpty) { return false }
                if(!lhs.developers.isEmpty) && (rhs.developers.isEmpty) { return true }
                return lhs.developers[0].lowercased() < rhs.developers[0].lowercased()
            case .installed:
                return lhs.isInstalled && !rhs.isInstalled
            }
        }
    }
    
    func loadCustomAddedGames() {
        let groupDefaults = UserDefaults(suiteName: suiteName)!
        if let savedGamesData = groupDefaults.data(forKey: "customAddedGames") {
            let decoder = JSONDecoder()
            guard let savedGames = try? decoder.decode([Game].self, from: savedGamesData) else { return }
            self.customAddedGames = savedGames
        }
    }

    private func loadLinkedSteamMetadata() {
        let groupDefaults = UserDefaults(suiteName: suiteName)!
        guard let data = groupDefaults.data(forKey: Self.linkedSteamMetadataDefaultsKey),
              let savedMetadata = try? JSONDecoder().decode(
                  [String: SteamGame].self,
                  from: data
              )
        else {
            return
        }
        linkedSteamMetadata = savedMetadata
    }

    private func saveLinkedSteamMetadata() {
        let groupDefaults = UserDefaults(suiteName: suiteName)!
        guard let data = try? JSONEncoder().encode(linkedSteamMetadata) else { return }
        groupDefaults.set(data, forKey: Self.linkedSteamMetadataDefaultsKey)
    }
    
    func getCustomAddedGame(id: String) -> Game? {
        return self.customAddedGames.first(where: { $0.id == id })
    }

    func resolvedCustomGame(_ game: Game) -> Game {
        guard let link = game.steamMetadataLink,
              let metadata = linkedSteamMetadata[game.id]
        else {
            return game
        }
        return SteamMetadataResolver.resolvedGame(
            base: game,
            metadata: metadata,
            link: link
        )
    }
    
    func saveCustomAddedGames() {
        let groupDefaults = UserDefaults(suiteName: suiteName)!
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self.customAddedGames) else { return }
        groupDefaults.set(data, forKey: "customAddedGames")
    }
    
    func updateCustomAddedGames(gameData: Game) {
        var updatedGame = gameData
        updatedGame.appStoreMetadataLanguage = "manual"
        if let index = self.customAddedGames.firstIndex(where: { $0.id == updatedGame.id }) {
            console.log("game \(self.customAddedGames[index].name) is being updated")
            console.log(String(describing: updatedGame))
            self.customAddedGames[index] = updatedGame
        }
        let groupDefaults = UserDefaults(suiteName: suiteName)!
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self.customAddedGames) else { return }
        groupDefaults.set(data, forKey: "customAddedGames")
    }

    func openCustomGameEditor(for game: Game? = nil) {
        guard !OnlineGameMode.isEnabled else { return }
        editingCustomGameID = game?.isCustom == true ? game?.id : nil
        showCustomGameEditor = true
    }

    func refreshNativeAppStoreMetadata() async {
        guard isAppleAppStoreMetadataEnabled else { return }

        let language = GameMetadataLanguage.current
        var didChange = false

        for index in customAddedGames.indices {
            guard customAddedGames[index].isDirectNativeApplication,
                  customAddedGames[index].appStoreMetadataLanguage != "manual",
                  let appURL = customAddedGames[index].appExeURL
            else {
                continue
            }

            let bundleIdentifier = customAddedGames[index].nativeAppBundleIdentifier
                ?? Bundle(url: appURL)?.bundleIdentifier
            guard let bundleIdentifier,
                  let metadata = await AppleAppStoreMetadataService.shared.metadata(
                    bundleIdentifier: bundleIdentifier,
                    language: language
                  )
            else {
                continue
            }

            var game = customAddedGames[index]
            let shouldReplaceLocalizedMetadata = game.appStoreMetadataLanguage != nil
                && game.appStoreMetadataLanguage != language.cacheKey
            var didChangeGame = false
            if game.nativeAppBundleIdentifier == nil {
                game.nativeAppBundleIdentifier = bundleIdentifier
                didChangeGame = true
            }
            if shouldReplaceLocalizedMetadata
                || game.detailedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                game.detailedDescription = metadata.description
                game.aboutTheGame = metadata.description
                game.shortDescription = metadata.shortDescription
                didChangeGame = true
            }
            if (shouldReplaceLocalizedMetadata || game.developers.isEmpty), let developer = metadata.developer {
                game.developers = [developer]
                didChangeGame = true
            }
            if (shouldReplaceLocalizedMetadata || game.publishers.isEmpty), let publisher = metadata.publisher {
                game.publishers = [publisher]
                didChangeGame = true
            }
            if (shouldReplaceLocalizedMetadata || game.categories.isEmpty), let genre = metadata.primaryGenre {
                game.categories = [Category(id: 1, description: genre)]
                didChangeGame = true
            }
            if (shouldReplaceLocalizedMetadata || game.genres?.isEmpty != false), !metadata.genres.isEmpty {
                game.genres = metadata.genres.enumerated().map {
                    Genre(id: String($0.offset + 1), description: $0.element)
                }
                didChangeGame = true
            }
            // A store icon is not necessarily a suitable hero image. Keep the
            // display URL under user control and only clean up old auto-filled
            // AppIcon values from earlier versions.
            if game.headerImage.lowercased().contains("appicon") {
                game.headerImage = ""
                didChangeGame = true
            }

            if didChangeGame {
                game.appStoreMetadataLanguage = language.cacheKey
                customAddedGames[index] = game
                didChange = true
            }
        }

        if didChange {
            saveCustomAddedGames()
        }
    }

    func refreshNativeSteamMetadata(forceRefresh: Bool = false) async {
        let linkedGames = customAddedGames.filter {
            $0.isDirectNativeApplication && $0.steamMetadataLink != nil
        }
        let linkedGameIDs = Set(linkedGames.map(\.id))
        var refreshedMetadata = linkedSteamMetadata.filter {
            linkedGameIDs.contains($0.key)
        }

        for game in linkedGames {
            guard let link = game.steamMetadataLink else { continue }
            do {
                if let metadata = try await api.fetchGameInfo(
                    appID: String(link.appID),
                    forceRefresh: forceRefresh,
                    source: .steamStore
                ) {
                    refreshedMetadata[game.id] = metadata
                } else {
                    console.warn("Linked Steam metadata was not found for \(link.appID)")
                }
            } catch {
                console.warn("Linked Steam metadata refresh failed for \(link.appID)")
                console.error(String(reflecting: error))
            }
        }

        linkedSteamMetadata = refreshedMetadata
        saveLinkedSteamMetadata()
    }

    func isNativeGameApplicationImported(_ application: NativeGameApplication) -> Bool {
        let applicationPath = application.url.standardizedFileURL.path
        return customAddedGames.contains { game in
            guard game.appExeURL?.standardizedFileURL.path == applicationPath
                    || (
                        application.bundleIdentifier != nil
                            && game.nativeAppBundleIdentifier == application.bundleIdentifier
                    )
            else {
                return false
            }
            return true
        }
    }

    func importNativeGameApplications(_ applications: [NativeGameApplication]) {
        var didImport = false
        for application in applications where !isNativeGameApplicationImported(application) {
            customAddedGames.append(application.makeGame())
            didImport = true
        }
        if didImport {
            saveCustomAddedGames()
        }
    }

    func refreshNativeGameApplicationImports(with applications: [NativeGameApplication]) {
        var byPath: [String: NativeGameApplication] = [:]
        var byBundleIdentifier: [String: NativeGameApplication] = [:]

        for application in applications {
            byPath[application.id] = application
            if let bundleIdentifier = application.bundleIdentifier,
               byBundleIdentifier[bundleIdentifier] == nil {
                byBundleIdentifier[bundleIdentifier] = application
            }
        }

        var didChange = false
        for index in customAddedGames.indices where customAddedGames[index].isNativeAppImport == true {
            guard let appURL = customAddedGames[index].appExeURL else { continue }
            let currentPath = appURL.standardizedFileURL.path
            let application = byPath[currentPath]
                ?? customAddedGames[index].nativeAppBundleIdentifier.flatMap {
                    byBundleIdentifier[$0]
                }

            if let application {
                if customAddedGames[index].appExeURL != application.url
                    || customAddedGames[index].name != application.name
                    || customAddedGames[index].appNames != [application.url.lastPathComponent]
                    || !customAddedGames[index].isInstalled {
                    customAddedGames[index].appExeURL = application.url
                    customAddedGames[index].name = application.name
                    customAddedGames[index].appNames = [application.url.lastPathComponent]
                    customAddedGames[index].isInstalled = true
                    customAddedGames[index].isNative = true
                    customAddedGames[index].platforms = Platforms(
                        windows: false,
                        mac: true,
                        linux: false
                    )
                    customAddedGames[index].nativeAppBundleIdentifier = application.bundleIdentifier
                    didChange = true
                }
            } else {
                let isPresent = FileManager.default.fileExists(atPath: appURL.path)
                if customAddedGames[index].isInstalled != isPresent {
                    customAddedGames[index].isInstalled = isPresent
                    didChange = true
                }
            }
        }

        if didChange {
            saveCustomAddedGames()
        }
    }
    
    func deleteCustomAddedGame(game: Game) {
        self.customAddedGames.removeAll { $0.id == game.id }
        if selectedGame?.id == game.id {
            selectedGame = nil
            showDetailView = false
        }
        if editingCustomGameID == game.id {
            editingCustomGameID = nil
            showCustomGameEditor = false
        }
        saveCustomAddedGames()
    }
    
    func setLoader(state: Bool) {
        isLaunchingGame = state
    }
    
    func setPlayingID( _ id: String?) {
        playingID = id
    }
}

final class AppGlobals: ObservableObject {
    @Published var selectedBottle: String = ""
    @Published var cxAppPath: String?
    @Published var windowsSteamFolder: URL?
    @Published var nativeSteamInstallation: NativeSteamInstallation?
    @Published var steamIdentities: [SteamIdentity] = []
    @Published var nativeSteamSession: SteamClientSession?
    @Published var containerSteamSession: SteamClientSession?
    @Published var activeSteamIdentity: SteamIdentity?

    var steamSessions: [SteamClientSession] {
        [nativeSteamSession, containerSteamSession].compactMap { $0 }
    }

    var steamSessionsCacheKey: String {
        steamSessions.map(\.cacheKey).joined(separator: "|")
    }
    
    init(selectedBottle: String? = "", cxAppPath: String? = nil) {
        self.selectedBottle = readUsrDefOptionString(key: "selectedBottle") ?? ""
        self.cxAppPath = readUsrDefOptionString(key: "cxAppPath")
    }

    func refreshSteamIdentity(containerInstallation: ContainerSteamInstallation?) {
        let discoveryService = SteamDiscoveryService()
        let nativeInstallation = discoveryService.detectNativeSteam()
        let containerSource = containerInstallation.map { installation in
            BundledWineRuntime.ownsStandardSteamPrefix(installation.bottleURL)
                ? SteamIdentitySource.winePrefix(installation.bottleURL)
                : SteamIdentitySource.crossOverBottle(installation.bottleURL)
        }
        let containerIdentities = containerInstallation.map { installation in
            discoveryService.identities(
                in: installation,
                source: containerSource ?? .crossOverBottle(installation.bottleURL)
            )
        } ?? []
        let identity = discoveryService.preferredIdentity(
            nativeInstallation: nativeInstallation,
            containerInstallation: containerInstallation
        )
        let nativeSession = nativeInstallation.flatMap { installation in
            installation.activeUser.map {
                SteamClientSession(
                    identity: $0,
                    steamRootURL: installation.steamRootURL,
                    source: .native,
                    clientKind: .native
                )
            }
        }
        let containerSession = containerInstallation.flatMap { installation in
            containerIdentities.first.map {
                SteamClientSession(
                    identity: $0,
                    steamRootURL: installation.steamRootURL,
                    source: containerSource ?? .crossOverBottle(installation.bottleURL),
                    clientKind: .container
                )
            }
        }
        self.nativeSteamInstallation = nativeInstallation
        self.steamIdentities = containerIdentities + (nativeInstallation?.users ?? [])
        self.nativeSteamSession = nativeSession
        self.containerSteamSession = containerSession
        self.activeSteamIdentity = identity
    }
}
