import Foundation

enum BundledRuntimePolicy {
    static let retiredMessage = "此游戏关联的是旧 CrossOver 容器，需要重新配置为 Arclume Wine。原容器与游戏文件已保留，不会自动迁移。"

    /// Changes only app preferences. Never creates, copies or migrates a prefix.
    static func adopt(defaults: UserDefaults, selectedBottle: String, online: Bool) -> String {
        if let url = OnlineGameDiscovery.selectedBottleURL(from: selectedBottle),
           !BundledWineRuntime.ownsPrefix(url), !BundledWineRuntime.ownsStandardSteamPrefix(url) {
            let key = online ? "online-game-runtime-crossover-bottle" : "standard-game-runtime-crossover-bottle"
            if defaults.string(forKey: key) == nil { defaults.set(url.absoluteString, forKey: key) }
        }
        defaults.set(StandardGameRuntimeKind.bundledWine.rawValue, forKey: StandardGameRuntimeKind.defaultsKey)
        defaults.set(OnlineGameRuntimeKind.bundledWine.rawValue, forKey: OnlineGameRuntimeKind.defaultsKey)
        let bottle = online ? BundledWineRuntime.prefixURL : BundledWineRuntime.standardSteamPrefixURL
        defaults.set(bottle.absoluteString, forKey: "selectedBottle")
        return bottle.absoluteString
    }

    static func needsReconfiguration(_ game: Game) -> Bool {
        guard !game.isNative else { return false }
        if game.installedRuntimeKind == StandardGameRuntimeKind.crossOver.rawValue { return true }
        guard let bottle = game.installedBottleURL else {
            guard let executable = game.appExeURL else { return false }
            return ![BundledWineRuntime.prefixURL, BundledWineRuntime.standardSteamPrefixURL].contains {
                executable.standardizedFileURL.path.hasPrefix($0.appendingPathComponent("drive_c").standardizedFileURL.path + "/")
            }
        }
        return !BundledWineRuntime.ownsPrefix(bottle) && !BundledWineRuntime.ownsStandardSteamPrefix(bottle)
    }
}
