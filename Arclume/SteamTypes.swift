//
//  Requirements.swift
//  Procyon
//
//  Created by Italo Mandara on 02/02/2026.
//

nonisolated struct Requirements: Codable {
    let minimum: String?
    let recommended: String?
}

nonisolated struct PriceOverview: Codable {
    let currency: String
    let initial: Int
    let final: Int
    let discountPercent: Int
    let initialFormatted: String
    let finalFormatted: String

    enum CodingKeys: String, CodingKey {
        case currency, initial, final
        case discountPercent = "discount_percent"
        case initialFormatted = "initial_formatted"
        case finalFormatted = "final_formatted"
    }
}

nonisolated struct PackageGroup: Codable {
    let name: String
    let title: String
    let description: String
    let selectionText: String
    let displayType: String
    let subs: [PackageSub]

    enum CodingKeys: String, CodingKey {
        case name, title, description
        case selectionText = "selection_text"
        case displayType = "display_type"
        case subs
    }
}

nonisolated struct PackageSub: Codable {
    let packageID: Int
    let optionText: String
    let isFreeLicense: Bool
    let priceInCentsWithDiscount: Int

    enum CodingKeys: String, CodingKey {
        case packageID = "packageid"
        case optionText = "option_text"
        case isFreeLicense = "is_free_license"
        case priceInCentsWithDiscount = "price_in_cents_with_discount"
    }
}

nonisolated struct Platforms: Codable {
    var windows: Bool
    var mac: Bool
    var linux: Bool
}

nonisolated struct Screenshot: Codable {
    let id: Int
    let pathThumbnail: String
    let pathFull: String

    enum CodingKeys: String, CodingKey {
        case id
        case pathThumbnail = "path_thumbnail"
        case pathFull = "path_full"
    }
}

nonisolated struct Movie: Codable {
    let id: Int
    let name: String
    let thumbnail: String
    let dashH264: String?
    let hlsH264: String?
    let highlight: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, thumbnail, highlight
        case dashH264 = "dash_h264"
        case hlsH264 = "hls_h264"
    }
}

nonisolated struct Category: Codable {
    let id: Int
    let description: String
}

nonisolated struct Genre: Codable {
    let id: String
    let description: String
}

nonisolated struct Metacritic: Codable {
    let score: Int?
    let url: String?
}

nonisolated struct Recommendations: Codable {
    let total: Int
}

nonisolated struct ReleaseDate: Codable {
    let comingSoon: Bool
    let date: String

    enum CodingKeys: String, CodingKey {
        case comingSoon = "coming_soon"
        case date
    }
}

nonisolated struct Achievements: Codable {
    let total: Int
    let highlighted: [Achievement]
}

nonisolated struct Achievement: Codable {
    let name: String
    let path: String
}

nonisolated struct SupportInfo: Codable {
    let url: String?
    let email: String?
}

nonisolated struct ContentDescriptors: Codable {
    let ids: [Int]
    let notes: String?
}

nonisolated struct Ratings: Codable {
    let esrb: RatingBody?
    let pegi: RatingBody?
    let usk: RatingBody?
}

nonisolated struct RatingBody: Codable {
    let rating: String?
    let requiredAge: String?
    let descriptors: String?

    enum CodingKeys: String, CodingKey {
        case rating
        case requiredAge = "required_age"
        case descriptors
    }
}

nonisolated struct SteamOwnedGame: Codable {
    let appID: Int
    let playtimeForever: Int?
    let playtimeWindowsForever: Int?
    let playtimeMacForever: Int?
    let playtimeLinuxForever: Int?
    let playtimeDeckForever: Int?
    let rtimeLastPlayed: Int?
    let playtimeDisconnected: Int?

    enum CodingKeys: String, CodingKey {
        case appID = "appid"
        case playtimeForever = "playtime_forever"
        case playtimeWindowsForever = "playtime_windows_forever"
        case playtimeMacForever = "playtime_mac_forever"
        case playtimeLinuxForever = "playtime_linux_forever"
        case playtimeDeckForever = "playtime_deck_forever"
        case rtimeLastPlayed = "rtime_last_played"
        case playtimeDisconnected = "playtime_disconnected"
    }
}

nonisolated struct SteamOwnedGames: Codable {
    let gameCount: Int
    let games: [SteamOwnedGame]
    
    enum CodingKeys: String, CodingKey {
        case gameCount = "game_count"
        case games
    }
}

nonisolated struct SteamGame: Codable {
    let type: String
    let name: String
    let steamAppID: Int
    let requiredAge: String
    let isFree: Bool
    let controllerSupport: String?
    let dlc: [Int]?

    let detailedDescription: String
    let aboutTheGame: String
    let shortDescription: String
    let supportedLanguages: String?

    let headerImage: String
    let capsuleImage: String
    let capsuleImageV5: String?
    let website: String?

    let pcRequirements: Requirements?
    let macRequirements: Requirements?
    let linuxRequirements: Requirements?

    let legalNotice: String?
    let developers: [String]?
    let publishers: [String]?

    let priceOverview: PriceOverview?
    let packages: [Int]?
    let packageGroups: [PackageGroup]?

    let platforms: Platforms
    let metacritic: Metacritic?

    let categories: [Category]?
    let genres: [Genre]?

    let screenshots: [Screenshot]?
    let movies: [Movie]?

    let recommendations: Recommendations?
    let achievements: Achievements?
    let releaseDate: ReleaseDate
    let supportInfo: SupportInfo?

    let background: String?
    let backgroundRaw: String?

    let contentDescriptors: ContentDescriptors?
    let ratings: [String: RatingBody]?

    enum CodingKeys: String, CodingKey {
        case type, name
        case steamAppID = "steam_appid"
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
        case capsuleImageV5 = "capsule_imagev5"
        case website
        case pcRequirements = "pc_requirements"
        case macRequirements = "mac_requirements"
        case linuxRequirements = "linux_requirements"
        case legalNotice = "legal_notice"
        case developers, publishers
        case priceOverview = "price_overview"
        case packages
        case packageGroups = "package_groups"
        case platforms, metacritic, categories, genres
        case screenshots, movies
        case recommendations, achievements
        case releaseDate = "release_date"
        case supportInfo = "support_info"
        case background
        case backgroundRaw = "background_raw"
        case contentDescriptors = "content_descriptors"
        case ratings
    }
}

nonisolated struct InstalledDepot {
    var manifest: String
    var size: String
}

class SteamACFMeta {
    var appid: String = ""
    var universe: String?
    var LauncherPath: String?
    var name: String?
    var StateFlags: String?
    var installdir: String = "/"
    var LastUpdated: String?
    var LastPlayed: String?
    var SizeOnDisk: String?
    var StagingSize: String?
    var buildid: String?
    var LastOwner: String?
    var DownloadType: String?
    var UpdateResult: String?
    var BytesToDownload: String?
    var BytesDownloaded: String?
    var BytesToStage: String?
    var BytesStaged: String?
    var TargetBuildID: String?
    var AutoUpdateBehavior: String?
    var AllowOtherDownloadsWhileRunning: String?
    var ScheduledAutoUpdate: String?
    var InstalledDepots: [String: InstalledDepot]?
    var UserConfig: [String: String]?
    var MountedConfig: [String: String]?
}

struct UserInfo: Codable {
    let steamID: String
    let communityVisibilityState: Int
    let profileState: Int
    let personaName: String
    let profileURL: String
    let avatar: String
    let avatarMedium: String
    let avatarFull: String
    let avatarHash: String
    let lastLogOff: Int?
    let personaState: Int
    let primaryClanID: String
    let timeCreated: Int
    let personaStateFlags: Int
    let locCountryCode: String?
    let locStateCode: String?

    enum CodingKeys: String, CodingKey {
        case steamID = "steamid"
        case communityVisibilityState = "communityvisibilitystate"
        case profileState = "profilestate"
        case personaName = "personaname"
        case profileURL = "profileurl"
        case avatar
        case avatarMedium = "avatarmedium"
        case avatarFull = "avatarfull"
        case avatarHash = "avatarhash"
        case lastLogOff = "lastlogoff"
        case personaState = "personastate"
        case primaryClanID = "primaryclanid"
        case timeCreated = "timecreated"
        case personaStateFlags = "personastateflags"
        case locCountryCode = "loccountrycode"
        case locStateCode = "locstatecode"
    }
}

struct UserInfoResponse: Codable {
    let data: [UserInfo]
}

nonisolated struct GameOptionsDataResponse: Codable {
    let data: GameOptionsData
}
