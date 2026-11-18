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
    /// Hide only the installer's plain alias for an already-present JX3 launcher.
    /// Saved entries and shortcuts remain untouched, including distinct launch intents.
    static func removingDuplicateShortcuts(from games: [Game]) -> [Game] {
        let launchers = Set(games.compactMap { game -> String? in
            guard game.id == OnlineGameMode.jx3GameID, game.isInstalled, !game.isNative,
                  let bottle = game.installedBottleURL, let executable = game.appExeURL,
                  executable.pathExtension.lowercased() == "exe", LocalProgramAvailability.isAvailable(game) else { return nil }
            return GameRemovalService.identity(executable: executable, bottle: bottle)
        })
        guard !launchers.isEmpty else { return games }
        return games.filter { game in
            guard game.id != OnlineGameMode.jx3GameID, game.isCustom == true, !game.isNative,
                  let entry = game.appExeURL, entry.pathExtension.lowercased() == "lnk",
                  entry.deletingPathExtension().lastPathComponent == "剑网3系列启动器",
                  let bottle = game.installedBottleURL, let target = GameRemovalService.target(for: game),
                  launchers.contains(GameRemovalService.identity(executable: target, bottle: bottle)),
                  let size = try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
                  let data = try? Data(contentsOf: entry),
                  hasDefaultShortcutIntent(data, target: target, bottle: bottle) else { return true }
            return false
        }
    }

    /// MS-SHLLINK StringData follows the optional target ID list and LinkInfo.
    /// Installer links can set HasArguments while storing only a terminating NUL.
    private static func hasDefaultShortcutIntent(_ data: Data, target: URL, bottle: URL) -> Bool {
        let bytes = [UInt8](data)
        func number(_ offset: Int, count: Int = 4) -> Int? {
            guard offset >= 0, offset <= bytes.count - count else { return nil }
            return (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
        }
        guard let flags = number(20), flags & (0x200 | 0x2000 | 0x20000) == 0,
              number(60) == 1 else { return false }
        var offset = 76
        if flags & 1 != 0 {
            guard let size = number(offset, count: 2) else { return false }
            offset += 2 + size
        }
        if flags & 2 != 0 {
            guard let size = number(offset), size >= 28, offset <= bytes.count - size else { return false }
            offset += size
        }
        var strings: [Int: String] = [:]
        let width = flags & 0x80 != 0 ? 2 : 1
        for field in [4, 8, 16, 32, 64] where flags & field != 0 {
            guard let count = number(offset, count: 2) else { return false }
            offset += 2
            let length = count * width
            guard offset <= bytes.count - length,
                  let value = String(data: Data(bytes[offset..<(offset + length)]),
                    encoding: width == 2 ? .utf16LittleEndian : .windowsCP1252) else { return false }
            strings[field] = value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
            offset += length
        }
        guard strings[32, default: ""].isEmpty else { return false }
        if let working = strings[16], !working.isEmpty {
            guard working.lowercased().hasPrefix("c:\\") else { return false }
            let root = bottle.appendingPathComponent("drive_c").standardizedFileURL.resolvingSymlinksInPath()
            let directory = root.appendingPathComponent(String(working.dropFirst(3)).replacingOccurrences(of: "\\", with: "/"))
                .standardizedFileURL.resolvingSymlinksInPath()
            guard directory == target.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() else { return false }
        }
        return true
    }

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
