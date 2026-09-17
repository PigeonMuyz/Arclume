import Foundation

enum LocalProgramAvailability {
    /// This is display state, not an uninstall or a permanent hide decision.
    /// Steam ownership entries remain available even without a local install.
    static func unavailableIDs(in games: [Game]) -> Set<String> {
        Set(games.filter { game in
            guard game.isCustom == true || game.isNativeAppImport == true
                    || OnlineGameMode.isJX3(game) else { return false }
            return !isAvailable(game)
        }.map(\.id))
    }

    static func isAvailable(_ game: Game) -> Bool {
        guard let entry = game.appExeURL, entry.isFileURL else { return false }
        if !game.isNative, let bottle = game.installedBottleURL,
           !hasResourceFlag(.isDirectoryKey, at: bottle) {
            return false
        }
        if entry.pathExtension.lowercased() == "lnk" {
            guard game.installedBottleURL != nil, isRegularFile(entry) else { return false }
        }
        guard let target = GameRemovalService.target(for: game), target.isFileURL else { return false }
        if game.isNative && target.pathExtension.lowercased() == "app" {
            return hasResourceFlag(.isDirectoryKey, at: target)
        }
        return isRegularFile(target)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        hasResourceFlag(.isRegularFileKey, at: url)
    }

    private static func hasResourceFlag(_ key: URLResourceKey, at url: URL) -> Bool {
        // Game stores long-lived URLs. Foundation caches resource values on
        // them, so a repeat check must explicitly discard the old stat result.
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        guard let values = try? freshURL.resourceValues(forKeys: [key]) else { return false }
        return key == .isDirectoryKey ? values.isDirectory == true : values.isRegularFile == true
    }
}
