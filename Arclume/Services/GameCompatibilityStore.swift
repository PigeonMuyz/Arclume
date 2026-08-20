//
//  GameCompatibilityStore.swift
//  Procyon
//

import Foundation
import Combine

final class GameCompatibilityStore: ObservableObject {
    @Published private(set) var profiles: [Int: GameCompatibilityProfile]
    @Published private(set) var customProfiles: [String: GameCompatibilityProfile]

    private let defaults: UserDefaults
    private let storageKey: String
    private let customStorageKey: String

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: suiteName),
        storageKey: String = "gameCompatibilityProfiles.v1",
        customStorageKey: String = "gameCompatibilityProfiles.custom.v1"
    ) {
        self.defaults = defaults ?? .standard
        self.storageKey = storageKey
        self.customStorageKey = customStorageKey
        self.profiles = Self.loadProfiles(from: self.defaults, key: storageKey)
        self.customProfiles = Self.loadCustomProfiles(from: self.defaults, key: customStorageKey)
    }

    func profile(for appID: Int) -> GameCompatibilityProfile {
        profiles[appID] ?? .defaultProfile
    }

    func profile(for game: Game) -> GameCompatibilityProfile {
        game.steamAppID > 0
            ? profile(for: game.steamAppID)
            : customProfiles[game.id] ?? .defaultProfile
    }

    func setCrossOverStatus(_ status: CrossOverCompatibility, for appID: Int) {
        guard appID > 0 else { return }
        var profile = profile(for: appID)
        profile.crossOverStatus = status
        update(profile, for: appID)
    }

    func setCrossOverStatus(_ status: CrossOverCompatibility, for game: Game) {
        guard game.steamAppID <= 0 else {
            setCrossOverStatus(status, for: game.steamAppID)
            return
        }
        var profile = profile(for: game)
        profile.crossOverStatus = status
        update(profile, forCustomGameID: game.id)
    }

    func setGPTK4BetaEnabled(_ isEnabled: Bool, for appID: Int) {
        guard appID > 0 else { return }
        var profile = profile(for: appID)
        profile.gptk4BetaEnabled = isEnabled
        update(profile, for: appID)
    }

    func setGPTK4BetaEnabled(_ isEnabled: Bool, for game: Game) {
        guard game.steamAppID <= 0 else {
            setGPTK4BetaEnabled(isEnabled, for: game.steamAppID)
            return
        }
        var profile = profile(for: game)
        profile.gptk4BetaEnabled = isEnabled
        update(profile, forCustomGameID: game.id)
    }

    func updateCrossOverMacRequirements(
        minimum: String,
        recommended: String,
        for appID: Int
    ) {
        guard appID > 0 else { return }
        var profile = profile(for: appID)
        let requirements = CrossOverMacRequirements(
            minimum: minimum.trimmingCharacters(in: .whitespacesAndNewlines),
            recommended: recommended.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        profile.crossOverMacRequirements = requirements.isEmpty ? nil : requirements
        update(profile, for: appID)
    }

    func updateCrossOverMacRequirements(
        minimum: String,
        recommended: String,
        for game: Game
    ) {
        guard game.steamAppID <= 0 else {
            updateCrossOverMacRequirements(minimum: minimum, recommended: recommended, for: game.steamAppID)
            return
        }
        var profile = profile(for: game)
        let requirements = CrossOverMacRequirements(
            minimum: minimum.trimmingCharacters(in: .whitespacesAndNewlines),
            recommended: recommended.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        profile.crossOverMacRequirements = requirements.isEmpty ? nil : requirements
        update(profile, forCustomGameID: game.id)
    }

    func clearCrossOverMacRequirements(for appID: Int) {
        guard appID > 0 else { return }
        var profile = profile(for: appID)
        profile.crossOverMacRequirements = nil
        update(profile, for: appID)
    }

    func clearCrossOverMacRequirements(for game: Game) {
        guard game.steamAppID <= 0 else {
            clearCrossOverMacRequirements(for: game.steamAppID)
            return
        }
        var profile = profile(for: game)
        profile.crossOverMacRequirements = nil
        update(profile, forCustomGameID: game.id)
    }

    func isPlayableOnMac(_ game: Game) -> Bool {
        if game.id == OnlineGameMode.jx3GameID && game.type == "launcher" {
            return true
        }
        return game.isNative
            || game.platforms.mac
            || (
                game.supportsCrossOverCompatibility
                    && profile(for: game).crossOverStatus == .supported
            )
    }

    func applyRuntimePreferences(for appID: Int, to options: GameOptions) {
        guard profile(for: appID).gptk4BetaEnabled else { return }
        options.cxGraphicsBackend = "d3dmetal4"
        options.d3dMtl4Enabled = true
    }

    func applyRuntimePreferences(for game: Game, to options: GameOptions) {
        guard profile(for: game).gptk4BetaEnabled else { return }
        options.cxGraphicsBackend = "d3dmetal4"
        options.d3dMtl4Enabled = true
    }

    private func update(_ profile: GameCompatibilityProfile, for appID: Int) {
        if profile == .defaultProfile {
            profiles.removeValue(forKey: appID)
        } else {
            profiles[appID] = profile
        }
        persist()
    }

    private func update(_ profile: GameCompatibilityProfile, forCustomGameID id: String) {
        if profile == .defaultProfile {
            customProfiles.removeValue(forKey: id)
        } else {
            customProfiles[id] = profile
        }
        persist()
    }

    private func persist() {
        let storedProfiles = Dictionary(
            uniqueKeysWithValues: profiles.map { (String($0.key), $0.value) }
        )
        guard let data = try? JSONEncoder().encode(storedProfiles) else { return }
        defaults.set(data, forKey: storageKey)
        guard let customData = try? JSONEncoder().encode(customProfiles) else { return }
        defaults.set(customData, forKey: customStorageKey)
    }

    private static func loadProfiles(
        from defaults: UserDefaults,
        key: String
    ) -> [Int: GameCompatibilityProfile] {
        guard
            let data = defaults.data(forKey: key),
            let storedProfiles = try? JSONDecoder().decode(
                [String: GameCompatibilityProfile].self,
                from: data
            )
        else {
            return [:]
        }

        return storedProfiles.reduce(into: [:]) { profiles, item in
            guard let appID = Int(item.key), appID > 0 else { return }
            profiles[appID] = item.value
        }
    }

    private static func loadCustomProfiles(
        from defaults: UserDefaults,
        key: String
    ) -> [String: GameCompatibilityProfile] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: GameCompatibilityProfile].self, from: data)) ?? [:]
    }
}
