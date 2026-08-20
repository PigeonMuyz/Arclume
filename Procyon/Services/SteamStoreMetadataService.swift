//
//  SteamStoreMetadataService.swift
//  Procyon
//

import Foundation

nonisolated enum SteamStoreMetadataError: LocalizedError {
    case invalidAppID(String)
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAppID(let appID):
            return L10n.format("Invalid Steam app ID: %@", appID)
        case .invalidResponse:
            return L10n.string("Steam Store returned an invalid response.")
        case .httpStatus(let statusCode):
            return L10n.format("Steam Store returned HTTP %@.", String(statusCode))
        }
    }
}

nonisolated enum SteamStoreAppDetailsDecoder {
    static func decodeGame(from data: Data, appID: String) throws -> SteamGame? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envelope = root[appID] as? [String: Any],
              envelope["success"] as? Bool == true,
              var game = envelope["data"] as? [String: Any]
        else {
            return nil
        }

        if let requiredAge = game["required_age"] as? NSNumber {
            game["required_age"] = requiredAge.stringValue
        } else if game["required_age"] == nil || game["required_age"] is NSNull {
            game["required_age"] = "0"
        }

        for key in ["pc_requirements", "mac_requirements", "linux_requirements"] {
            if let value = game[key], !(value is [String: Any]), !(value is NSNull) {
                game.removeValue(forKey: key)
            }
        }

        if var packageGroups = game["package_groups"] as? [[String: Any]] {
            for index in packageGroups.indices {
                if let displayType = packageGroups[index]["display_type"] as? NSNumber {
                    packageGroups[index]["display_type"] = displayType.stringValue
                }
            }
            game["package_groups"] = packageGroups
        }

        game["type"] = game["type"] ?? "game"
        game["name"] = game["name"] ?? "Steam App \(appID)"
        game["steam_appid"] = game["steam_appid"] ?? Int(appID) ?? 0
        game["is_free"] = game["is_free"] ?? false
        game["detailed_description"] = game["detailed_description"] ?? ""
        game["about_the_game"] = game["about_the_game"] ?? ""
        game["short_description"] = game["short_description"] ?? ""
        game["header_image"] = game["header_image"] ?? ""
        game["capsule_image"] = game["capsule_image"] ?? ""
        game["platforms"] = game["platforms"] ?? [
            "windows": false,
            "mac": false,
            "linux": false,
        ]
        game["release_date"] = game["release_date"] ?? [
            "coming_soon": false,
            "date": "",
        ]

        let normalizedData = try JSONSerialization.data(withJSONObject: game)
        return try JSONDecoder().decode(SteamGame.self, from: normalizedData)
    }
}

private actor SteamStoreRequestLimiter {
    private var lastRequestDate: Date?

    func waitForTurn(minimumInterval: Duration) async throws {
        if let lastRequestDate {
            let elapsed = Date().timeIntervalSince(lastRequestDate)
            let minimumSeconds = Double(minimumInterval.components.seconds)
                + Double(minimumInterval.components.attoseconds) / 1_000_000_000_000_000_000
            if elapsed < minimumSeconds {
                try await Task.sleep(for: .seconds(minimumSeconds - elapsed))
            }
        }
        lastRequestDate = Date()
    }
}

nonisolated final class SteamStoreMetadataService: @unchecked Sendable {
    static let shared = SteamStoreMetadataService()

    private let session: URLSession
    private let limiter = SteamStoreRequestLimiter()
    private let minimumRequestInterval: Duration

    init(
        session: URLSession = .shared,
        minimumRequestInterval: Duration = .milliseconds(250)
    ) {
        self.session = session
        self.minimumRequestInterval = minimumRequestInterval
    }

    func metadata(appID: String, language: String) async throws -> SteamGame? {
        guard Int(appID).map({ $0 > 0 }) == true else {
            throw SteamStoreMetadataError.invalidAppID(appID)
        }
        guard var components = URLComponents(
            string: "https://store.steampowered.com/api/appdetails"
        ) else {
            throw SteamStoreMetadataError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "appids", value: appID),
            URLQueryItem(name: "l", value: language),
        ]
        guard let url = components.url else {
            throw SteamStoreMetadataError.invalidResponse
        }

        var lastError: Error?
        for attempt in 0..<2 {
            try await limiter.waitForTurn(minimumInterval: minimumRequestInterval)
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw SteamStoreMetadataError.invalidResponse
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw SteamStoreMetadataError.httpStatus(httpResponse.statusCode)
                }
                return try SteamStoreAppDetailsDecoder.decodeGame(
                    from: data,
                    appID: appID
                )
            } catch {
                lastError = error
                guard attempt == 0, Self.isRetryable(error) else { throw error }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw lastError ?? SteamStoreMetadataError.invalidResponse
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let error = error as? SteamStoreMetadataError,
           case .httpStatus(let statusCode) = error {
            return statusCode == 429 || (500..<600).contains(statusCode)
        }
        return (error as? URLError) != nil
    }
}
