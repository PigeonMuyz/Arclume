import Foundation

nonisolated enum GameDataCategory: String, CaseIterable, Sendable {
    case logs, local, login, registry
    var title: String {
        switch self {
        case .logs: "日志与已识别缓存"
        case .local: "本地数据与设置（可能含本地进度）"
        case .login: "游戏内登录数据（需重新登录）"
        case .registry: "注册表中的游戏设置（需退出所有 Wine 程序）"
        }
    }
}

nonisolated struct GameDataItem: Identifiable, Equatable, Sendable {
    let url: URL
    let category: GameDataCategory
    let bytes: Int64
    let registrySection: String?
    var registryKey: String? = nil
    var id: String { url.path + "|" + category.rawValue + "|" + (registryKey ?? "") }
    var displayPath: String {
        category == .registry ? url.path + " → HKCU\\" + (registryKey ?? "").replacingOccurrences(of: #"\\"#, with: #"\"#) : url.path
    }
}

nonisolated struct GameCleanupResult: Sendable {
    var bodyRemoved = false
    var completed: [String] = []
    var recoveryURL: URL?
    var recoveryURLs: [URL] = []
    var removedGameDirectories: [URL] = []
    var error: String?
}

/// Only verified Endfield-owned paths. Unknown sibling SDK data is deliberately excluded.
nonisolated enum GameAssociatedDataService {
    static func category(for name: String, rule: GameAdaptationRule) -> GameDataCategory? {
        for entry in rule.dataEntries ?? [] {
            if let count = entry.hexSuffixLength, name.hasPrefix(entry.name) {
                let suffix = name.dropFirst(entry.name.count)
                if suffix.count == count && suffix.allSatisfy({ $0.isASCII && $0.isHexDigit }) { return GameDataCategory(rawValue: entry.category) }
            } else if name == entry.name { return GameDataCategory(rawValue: entry.category) }
        }
        return nil
    }

    static func checkedBytes(_ url: URL, within root: URL) throws -> Int64 {
        let normalized = url.standardizedFileURL
        guard normalized.path.hasPrefix(root.standardizedFileURL.path + "/"),
              normalized.resolvingSymlinksInPath().path == normalized.path else { throw GameRemovalError.unsafePath }
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileAllocatedSizeKey]
        func size(_ file: URL) throws -> Int64 {
            let values = try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw GameRemovalError.unsafePath }
            return values.isRegularFile == true ? Int64(values.fileAllocatedSize ?? 0) : 0
        }
        var total = try size(normalized)
        if try normalized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            var enumerationError: Error?
            guard let walker = FileManager.default.enumerator(at: normalized, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in
                enumerationError = error; return false
            }) else { throw GameRemovalError.unsafePath }
            for case let child as URL in walker {
                try Task.checkCancellation()
                total += try size(child)
            }
            if let enumerationError { throw enumerationError }
        }
        return total
    }

    /// Preserves every byte outside the exact section, including neighboring game/launcher keys.
    static func splitRegistry(_ text: String, registryKey: String) throws -> (remaining: String, selected: String) {
        guard !registryKey.isEmpty, text.hasPrefix("WINE REGISTRY Version 2"), !text.contains("\r") else { throw GameRemovalError.unsupported }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var remaining: [String] = [], selected: [String] = []
        var selecting = false
        for line in lines {
            if line.hasPrefix("[") {
                guard let closing = line.firstIndex(of: "]") else { throw GameRemovalError.unsupported }
                let key = String(line[line.index(after: line.startIndex)..<closing])
                selecting = key == registryKey || key.hasPrefix(registryKey + #"\\"#)
            }
            if selecting { selected.append(String(line)) } else { remaining.append(String(line)) }
        }
        return (remaining.joined(separator: "\n"), selected.joined(separator: "\n"))
    }

    static func scan(_ plan: GameRemovalPlan) throws -> [GameDataItem] {
        guard let rule = GameAdaptationRules.matching(plan.executable),
              let dataDirectory = rule.userDataDirectory else { return [] }
        let bottle = plan.bottle.standardizedFileURL
        let users = bottle.appendingPathComponent("drive_c/users")
        var items: [GameDataItem] = []
        if FileManager.default.fileExists(atPath: users.path) {
            guard users.resolvingSymlinksInPath().path == users.path else { throw GameRemovalError.unsafePath }
            for user in try FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil) {
                let root = user.appendingPathComponent(dataDirectory).standardizedFileURL
                guard FileManager.default.fileExists(atPath: root.path) else { continue }
                guard root.resolvingSymlinksInPath().path == root.path else { throw GameRemovalError.unsafePath }
                for child in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                    guard let category = category(for: child.lastPathComponent, rule: rule) else { continue }
                    items.append(GameDataItem(url: child, category: category,
                        bytes: try checkedBytes(child, within: bottle), registrySection: nil))
                }
            }
        }
        let registry = bottle.appendingPathComponent("user.reg")
        if let registryKey = rule.registryKey, FileManager.default.fileExists(atPath: registry.path) {
            _ = try checkedBytes(registry, within: bottle)
            let section = try splitRegistry(String(contentsOf: registry, encoding: .utf8), registryKey: registryKey).selected
            if !section.isEmpty {
                items.append(GameDataItem(url: registry, category: .registry, bytes: Int64(section.utf8.count), registrySection: section, registryKey: registryKey))
            }
        }
        return items.sorted { $0.id < $1.id }
    }

    static func requireRegistryIdle() throws {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        process.standardOutput = pipe
        try process.run()
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).lowercased()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              !names.contains("wine"), !names.contains(".exe") else { throw GameRemovalError.running }
    }

    /// Called only after the selected-key recovery fragment has been saved.
    static func replaceRegistryFile(_ url: URL, expected: Data, replacement: Data) throws {
        guard url.standardizedFileURL.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
              try Data(contentsOf: url) == expected else { throw GameRemovalError.changed }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".arclume-registry-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: replacement, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard try Data(contentsOf: url) == expected else { throw GameRemovalError.changed }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary, options: .usingNewMetadataOnly)
    }

    static func clean(_ plan: GameRemovalPlan, preview: [GameDataItem], selected: Set<String>, removeBody: Bool,
                      linkedExecutables: [URL]) -> GameCleanupResult {
        var result = GameCleanupResult()
        do {
            try GameRemovalService.requireStopped()
            let currentPlan = try GameRemovalService.plan(executable: plan.executable, bottle: plan.bottle,
                ownedBottles: [BundledWineRuntime.standardSteamPrefixURL, BundledWineRuntime.prefixURL], linkedExecutables: linkedExecutables)
            guard currentPlan == plan else { throw GameRemovalError.changed }
            let chosen = preview.filter { selected.contains($0.id) }
            guard chosen.count == selected.count else { throw GameRemovalError.changed }
            let current = try scan(plan)
            guard chosen.allSatisfy({ current.contains($0) }) else { throw GameRemovalError.changed }
            if chosen.contains(where: { $0.category == .registry }) { try requireRegistryIdle() }
            if removeBody {
                try GameRemovalService.trashGame(plan, linkedExecutables: linkedExecutables)
                result.bodyRemoved = true
                result.removedGameDirectories.append(plan.directory)
                result.completed.append(plan.directory.path)
            }
            for item in chosen {
                try GameRemovalService.requireStopped()
                if item.category == .registry {
                    try requireRegistryIdle()
                    _ = try checkedBytes(item.url, within: plan.bottle)
                    let original = try Data(contentsOf: item.url)
                    guard let text = String(data: original, encoding: .utf8) else { throw GameRemovalError.unsupported }
                    guard let registryKey = item.registryKey else { throw GameRemovalError.changed }
                    let split = try splitRegistry(text, registryKey: registryKey)
                    guard split.selected == item.registrySection else { throw GameRemovalError.changed }
                    let recovery = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Arclume/RemovalRecovery/\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let fragment = recovery.appendingPathComponent("game-user.reg.fragment")
                    try Data((split.selected + "\n").utf8).write(to: fragment, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fragment.path)
                    result.recoveryURL = fragment
                    try replaceRegistryFile(item.url, expected: original, replacement: Data(split.remaining.utf8))
                } else {
                    guard try checkedBytes(item.url, within: plan.bottle) == item.bytes else { throw GameRemovalError.changed }
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                }
                result.completed.append(item.displayPath)
            }
        } catch { result.error = error.localizedDescription }
        return result
    }
}
