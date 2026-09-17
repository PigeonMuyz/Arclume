import Foundation

enum LibraryProgramLocation {
    /// Opening a directory is read-only; never create a missing installation.
    static func directory(for game: Game, steamSnapshot: SteamInstallSnapshot? = nil) -> URL? {
        if let snapshot = steamSnapshot,
           let steamApps = snapshot.steamAppsDirectory,
           let name = snapshot.installDirectory, !name.isEmpty {
            let common = steamApps.appendingPathComponent("common").standardizedFileURL
            let directory = common.appendingPathComponent(name).standardizedFileURL
            if directory.path.hasPrefix(common.path + "/"), isDirectory(directory) {
                return directory
            }
        }
        if game.appExeURL?.pathExtension.lowercased() == "lnk", game.installedBottleURL == nil { return nil }
        guard let target = GameRemovalService.target(for: game), target.isFileURL,
              FileManager.default.fileExists(atPath: target.path) else { return nil }
        // For native apps, show the containing folder, not the bundle internals.
        let directory = target.pathExtension.lowercased() == "app" || !isDirectory(target)
            ? target.deletingLastPathComponent() : target
        return isDirectory(directory) ? directory : nil
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

enum StandardLibraryJX3 {
    /// Retain the stable JX3 identity and launch route, but persist ordinary
    /// library edits/metadata and use the actual owning bottle for hiding.
    static func entry(discovered: Game, existing: Game?, bottle: URL,
                      runtimeKind: String, crossOverPath: String?, hidden: [String]) -> Game? {
        guard let executable = discovered.appExeURL,
              !hidden.contains(GameRemovalService.identity(executable: executable, bottle: bottle)),
              !hidden.contains(GameRemovalService.identity(executable: executable, bottle: nil)) else { return nil }
        var game = existing ?? discovered
        game.id = discovered.id
        game.isCustom = true
        game.isNative = false
        game.isInstalled = true
        game.appExeURL = executable
        game.appNames = discovered.appNames
        game.installedBottleURL = bottle
        game.installedRuntimeKind = runtimeKind
        game.installedCrossOverPath = runtimeKind == StandardGameRuntimeKind.crossOver.rawValue ? crossOverPath : nil
        return game
    }
}
