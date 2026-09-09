import AppKit
import Foundation

nonisolated struct GameRemovalPlan: Equatable, Sendable {
    let directory: URL
    let executable: URL
    let bottle: URL
    let bytes: Int64
    let launcher: URL?
}

nonisolated enum GameRemovalError: LocalizedError {
    case unsupported, unsafePath, running, changed
    var errorDescription: String? {
        switch self {
        case .unsupported: "暂不能可靠确认此游戏的独立安装目录。请使用原启动器卸载，或仅从游戏库隐藏。"
        case .unsafePath: "目录边界或符号链接检查未通过，未删除任何文件。"
        case .running: "游戏或关联启动器仍在运行，请先正常退出后重试。"
        case .changed: "安装内容或关联游戏已变化，请关闭此窗口后重新预览。"
        }
    }
}

nonisolated enum GameRemovalService {
    static func target(for game: Game) -> URL? {
        guard let entry = game.appExeURL else { return nil }
        guard entry.pathExtension.lowercased() == "lnk", let bottle = game.installedBottleURL else { return entry }
        guard let size = try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
              let data = try? Data(contentsOf: entry), let path = InstalledProgramDiscovery.shortcutTarget(data),
              path.lowercased().hasPrefix("c:\\") else { return nil }
        let root = bottle.appendingPathComponent("drive_c").standardizedFileURL.resolvingSymlinksInPath()
        let target = root.appendingPathComponent(String(path.dropFirst(3)).replacingOccurrences(of: "\\", with: "/"))
            .standardizedFileURL.resolvingSymlinksInPath()
        return target.path.hasPrefix(root.path + "/") ? target : nil
    }

    static func identity(executable: URL, bottle: URL?) -> String {
        (bottle?.standardizedFileURL.resolvingSymlinksInPath().path ?? "") + "|" + executable.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func plan(executable: URL, bottle: URL, ownedBottles: [URL], linkedExecutables: [URL]) throws -> GameRemovalPlan {
        guard ownedBottles.contains(where: { $0.standardizedFileURL == bottle.standardizedFileURL }) else { throw GameRemovalError.unsafePath }
        let directory = executable.deletingLastPathComponent().standardizedFileURL
        let root = bottle.appendingPathComponent("drive_c").standardizedFileURL.resolvingSymlinksInPath()
        guard directory.path.hasPrefix(root.path + "/"),
              directory.resolvingSymlinksInPath() == directory,
              executable.resolvingSymlinksInPath() == executable.standardizedFileURL else { throw GameRemovalError.unsafePath }
        if let portable = try PortableSoftwareService.removalPlan(executable: executable, bottle: bottle) { return portable }
        guard let rule = GameAdaptationRules.matching(executable), rule.kind == "game", rule.allows(executable, in: bottle),
              let launcherID = rule.launcherID, let launcherRule = GameAdaptationRules.rule(id: launcherID) else {
            throw GameRemovalError.unsupported
        }
        let launcher = launcherRule.directory(in: bottle)
        let children = try FileManager.default.contentsOfDirectory(at: directory.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let otherContent = children.contains { $0.standardizedFileURL != directory }
        let otherLinks = linkedExecutables.contains {
            let path = $0.standardizedFileURL.path
            return path.hasPrefix(launcher.path + "/games/") && !path.hasPrefix(directory.path + "/")
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) else { throw GameRemovalError.unsafePath }
        var bytes: Int64 = 0
        for case let url as URL in walker {
            if Task.isCancelled { throw CancellationError() }
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { throw GameRemovalError.unsafePath }
            if values.isRegularFile == true { bytes += Int64(values.fileAllocatedSize ?? 0) }
        }
        return GameRemovalPlan(directory: directory, executable: executable, bottle: bottle, bytes: bytes,
            launcher: !otherContent && !otherLinks ? launcher : nil)
    }

    static func requireStopped() throws {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw GameRemovalError.running }
        let names = String(decoding: data, as: UTF8.self).lowercased()
        let managedNames = GameAdaptationRules.all.flatMap { [$0.executable] + $0.alternateExecutables }
        guard !managedNames.isEmpty, !managedNames.contains(where: { names.contains($0.lowercased()) }) else { throw GameRemovalError.running }
    }

    /// Revalidates immediately before moving only the reviewed directory to Trash.
    static func trashGame(_ plan: GameRemovalPlan, linkedExecutables: [URL]) throws {
        try requireStopped()
        if plan.directory.path.hasPrefix(plan.bottle.appendingPathComponent("drive_c/PortableApps").path + "/") {
            try GameAssociatedDataService.requireRegistryIdle()
        }
        let current = try self.plan(executable: plan.executable, bottle: plan.bottle,
            ownedBottles: [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL], linkedExecutables: linkedExecutables)
        guard current == plan else { throw GameRemovalError.changed }
        try FileManager.default.trashItem(at: plan.directory, resultingItemURL: nil)
    }

}
