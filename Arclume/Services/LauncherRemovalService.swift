import Foundation

nonisolated struct LauncherRemovalPlan: Equatable, Sendable {
    struct Entry: Equatable, Sendable { let url: URL; let bytes: Int64 }
    let executable: URL
    let bottle: URL
    let directory: URL
    let entries: [Entry]
    let games: [GameRemovalPlan]
    let unknownGames: [URL]
    let retainedEntries: [URL]
    var hasGames: Bool { !games.isEmpty || !unknownGames.isEmpty }
    var canRemoveGames: Bool { !games.isEmpty && unknownGames.isEmpty }
}

nonisolated enum LauncherRemovalService {
    /// Kept separate for fixture testing. Production calls only after validating the owned prefix and plan.
    static func trashEntries(_ plan: LauncherRemovalPlan, completed: inout [String],
                             move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        for entry in plan.entries {
            guard try GameAssociatedDataService.checkedBytes(entry.url, within: plan.bottle) == entry.bytes else { throw GameRemovalError.changed }
        }
        for entry in plan.entries {
            guard try GameAssociatedDataService.checkedBytes(entry.url, within: plan.bottle) == entry.bytes else { throw GameRemovalError.changed }
            try move(entry.url)
            completed.append(entry.url.path)
        }
    }

    static func plan(executable: URL, bottle: URL, ownedBottles: [URL], linkedExecutables: [URL]) throws -> LauncherRemovalPlan {
        guard ownedBottles.contains(where: { $0.standardizedFileURL == bottle.standardizedFileURL }),
              let rule = GameAdaptationRules.matching(executable), rule.kind == "launcher", rule.allows(executable, in: bottle),
              let ownedNames = rule.launcherRemovalEntries else { throw GameRemovalError.unsupported }
        let root = rule.directory(in: bottle)
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).map(\.standardizedFileURL)
        let gamesRoot = root.appendingPathComponent("games").standardizedFileURL
        var games: [GameRemovalPlan] = []
        var unknown = Set<URL>()
        if FileManager.default.fileExists(atPath: gamesRoot.path) {
            guard gamesRoot.resolvingSymlinksInPath().path == gamesRoot.path else { throw GameRemovalError.unsafePath }
            for child in try FileManager.default.contentsOfDirectory(at: gamesRoot, includingPropertiesForKeys: nil).map(\.standardizedFileURL) {
                if let gameRule = GameAdaptationRules.all.first(where: { $0.launcherID == rule.id && $0.directory(in: bottle) == child }),
                   let gamePlan = try? GameRemovalService.plan(executable: child.appendingPathComponent(gameRule.executable), bottle: bottle, ownedBottles: ownedBottles, linkedExecutables: linkedExecutables) {
                    games.append(gamePlan)
                } else { unknown.insert(child) }
            }
        }
        // Include entries missing from the library and also warn about known linked games elsewhere.
        for target in linkedExecutables {
            if let linkedRule = GameAdaptationRules.matching(target), linkedRule.launcherID == rule.id,
               target.standardizedFileURL.path.hasPrefix(bottle.standardizedFileURL.path + "/"),
               !games.contains(where: { $0.executable.standardizedFileURL == target.standardizedFileURL }) {
                unknown.insert(target.deletingLastPathComponent().standardizedFileURL)
            }
        }
        var entries: [LauncherRemovalPlan.Entry] = [], retained: [URL] = []
        for child in children where child.path != gamesRoot.path {
            let parts = child.lastPathComponent.split(separator: ".", omittingEmptySubsequences: false)
            let isVersion = rule.launcherVersionDirectories == true && (2...4).contains(parts.count)
                && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
                && rule.alternateExecutables.contains { rule.recognizes(child.appendingPathComponent($0)) }
            if ownedNames.contains(child.lastPathComponent) || isVersion {
                guard !unknown.contains(where: { $0.path == child.path || $0.path.hasPrefix(child.path + "/") }) else { throw GameRemovalError.unsafePath }
                entries.append(.init(url: child, bytes: try GameAssociatedDataService.checkedBytes(child, within: bottle)))
            } else { retained.append(child) }
        }
        guard !entries.isEmpty else { throw GameRemovalError.unsupported }
        return LauncherRemovalPlan(executable: executable, bottle: bottle, directory: root,
            entries: entries.sorted { $0.url.path < $1.url.path }, games: games.sorted { $0.directory.path < $1.directory.path },
            unknownGames: unknown.sorted { $0.path < $1.path }, retainedEntries: retained.sorted { $0.path < $1.path })
    }

    static func clean(_ preview: LauncherRemovalPlan, removeGames: Bool, removeAllData: Bool,
                      data: [String: [GameDataItem]], linkedExecutables: [URL]) -> GameCleanupResult {
        var result = GameCleanupResult()
        do {
            try GameRemovalService.requireStopped()
            let owned = [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL]
            let current = try plan(executable: preview.executable, bottle: preview.bottle, ownedBottles: owned, linkedExecutables: linkedExecutables)
            guard current == preview, !removeGames || current.canRemoveGames else { throw GameRemovalError.changed }
            if removeGames && removeAllData {
                for game in current.games {
                    guard try GameAssociatedDataService.scan(game) == data[game.directory.path] else { throw GameRemovalError.changed }
                }
                if data.values.joined().contains(where: { $0.category == .registry }) { try GameAssociatedDataService.requireRegistryIdle() }
            }
            if removeGames {
                for game in current.games {
                    // Removing a sibling may change whether its launcher can be removed; refresh that derived field.
                    let fresh = try GameRemovalService.plan(executable: game.executable, bottle: game.bottle, ownedBottles: owned, linkedExecutables: linkedExecutables)
                    guard fresh.directory == game.directory, fresh.bytes == game.bytes else { throw GameRemovalError.changed }
                    let items = data[game.directory.path] ?? []
                    let outcome = GameAssociatedDataService.clean(fresh, preview: items,
                        selected: removeAllData ? Set(items.map(\.id)) : [], removeBody: true, linkedExecutables: linkedExecutables)
                    result.completed += outcome.completed
                    result.removedGameDirectories += outcome.removedGameDirectories
                    if let recovery = outcome.recoveryURL { result.recoveryURLs.append(recovery) }
                    if let error = outcome.error { result.error = error; return result }
                }
            }
            try GameRemovalService.requireStopped()
            try trashEntries(current, completed: &result.completed)
            result.bodyRemoved = true
            // Never trash the launcher root: it may still contain games, unknown data or new downloads.
        } catch { result.error = error.localizedDescription }
        return result
    }
}
