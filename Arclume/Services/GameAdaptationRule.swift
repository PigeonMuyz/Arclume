import Foundation

nonisolated struct GameAdaptationRule: Decodable, Sendable {
    struct Installer: Decodable, Sendable {
        let filenamePrefix: String
        let engine: String
        let signature: String
    }
    struct DataEntry: Decodable, Sendable {
        let name: String
        let category: String
        let hexSuffixLength: Int?
    }
    struct Portable: Decodable, Sendable {
        let scriptPolicy: String
        let preservePaths: [String]
    }
    struct GreenPreparation: Decodable, Sendable {
        let blockedDirectories: [String]
    }
    let id: String
    let name: String
    let kind: String
    let installDirectory: String
    let executable: String
    let alternateExecutables: [String]
    let requiredFiles: [String]
    let ancestorDirectoryName: String?
    let defaultArguments: [[String]]
    let launcherID: String?
    let gameDBID: Int?
    let installer: Installer?
    let userDataDirectory: String?
    let dataEntries: [DataEntry]?
    let registryKey: String?
    let launcherRemovalEntries: [String]?
    let launcherVersionDirectories: Bool?
    let portable: Portable?
    let captureErrors: Bool?
    let greenPreparation: GreenPreparation?

    var windowsDirectory: String { "C:\\" + installDirectory.replacingOccurrences(of: "/", with: "\\") }
    func directory(in bottle: URL) -> URL { bottle.appendingPathComponent("drive_c/" + installDirectory).standardizedFileURL }

    func recognizes(_ url: URL) -> Bool {
        guard ([executable] + alternateExecutables).contains(where: { $0.lowercased() == url.lastPathComponent.lowercased() }) else { return false }
        let directory = url.deletingLastPathComponent()
        if let ancestorDirectoryName, !directory.pathComponents.contains(ancestorDirectoryName) { return false }
        guard ([url] + requiredFiles.map { directory.appendingPathComponent($0) }).allSatisfy({
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }), let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) == Data([0x4d, 0x5a])
    }

    func allows(_ url: URL, in bottle: URL) -> Bool {
        let target = url.standardizedFileURL
        let root = directory(in: bottle)
        guard target.resolvingSymlinksInPath() == target, root.resolvingSymlinksInPath() == root else { return false }
        // Launchers may keep versioned helper EXEs below their root, but never inside a game's directory.
        if kind == "launcher" {
            return target.path.hasPrefix(root.path + "/") && !target.path.hasPrefix(root.path + "/games/")
        }
        return target == root.appendingPathComponent(executable)
    }
}

nonisolated enum GameAdaptationRules {
    struct ProcessName: Decodable, Sendable {
        let executable: String
        let name: String
        let ruleID: String?
        let ancestorDirectoryName: String?
    }
    struct Document: Decodable { let schemaVersion: Int; let rules: [GameAdaptationRule]; let processNames: [ProcessName]? }

    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains(":")
            && !path.unicodeScalars.contains(where: { $0.value < 32 })
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func decode(_ data: Data) throws -> [GameAdaptationRule] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1, Set(document.rules.map(\.id)).count == document.rules.count else { throw GameRemovalError.unsupported }
        for entry in document.processNames ?? [] {
            guard safeRelativePath(entry.executable), !entry.executable.contains("/"), entry.executable.lowercased().hasSuffix(".exe"),
                  !entry.name.isEmpty, entry.name.utf8.count <= 128, !entry.name.unicodeScalars.contains(where: { $0.value < 32 }),
                  entry.ruleID.map({ id in document.rules.contains { $0.id == id } }) ?? true,
                  entry.ancestorDirectoryName.map({ safeRelativePath($0) && !$0.contains("/") }) ?? true,
                  entry.ruleID != nil || entry.ancestorDirectoryName != nil else { throw GameRemovalError.unsupported }
        }
        for rule in document.rules {
            guard !rule.id.isEmpty, ["game", "launcher", "application"].contains(rule.kind),
                  safeRelativePath(rule.installDirectory), rule.installDirectory.split(separator: "/").count >= 2,
                  safeRelativePath(rule.executable), !rule.executable.contains("/"),
                  rule.requiredFiles.allSatisfy(safeRelativePath),
                  rule.alternateExecutables.allSatisfy({ safeRelativePath($0) && !$0.contains("/") }),
                  rule.userDataDirectory.map(safeRelativePath) ?? true,
                  rule.defaultArguments.allSatisfy({ !$0.isEmpty && $0.allSatisfy { !$0.contains("\n") && !$0.contains("\0") } }),
                  rule.dataEntries?.allSatisfy({ safeRelativePath($0.name) && !$0.name.contains("/") && GameDataCategory(rawValue: $0.category) != nil && $0.category != "registry" && ($0.hexSuffixLength == nil || $0.hexSuffixLength == 32) }) ?? true,
                  rule.registryKey.map({ $0.hasPrefix(#"Software\\"#) && $0.components(separatedBy: #"\\"#).count >= 3 && !$0.contains("\n") && !$0.contains("[") && !$0.contains("]") }) ?? true
            else { throw GameRemovalError.unsupported }
            if let entries = rule.launcherRemovalEntries {
                guard rule.kind == "launcher", entries.allSatisfy({ safeRelativePath($0) && !$0.contains("/") && $0.lowercased() != "games" }) else { throw GameRemovalError.unsupported }
            }
            if let installer = rule.installer {
                guard installer.engine == "nsis", !installer.filenamePrefix.isEmpty, installer.signature == "NullsoftInst" else { throw GameRemovalError.unsupported }
            }
            if let portable = rule.portable {
                guard rule.kind == "application", rule.launcherID == nil, rule.installer == nil,
                      rule.installDirectory.hasPrefix("PortableApps/"), rule.installDirectory.split(separator: "/").count == 2,
                      portable.scriptPolicy == "skip", !rule.requiredFiles.isEmpty,
                      portable.preservePaths.allSatisfy({ safeRelativePath($0) && !$0.contains("/") && $0 != rule.executable && !$0.hasPrefix(".arclume-") }),
                      Set(portable.preservePaths.map { $0.lowercased() }).count == portable.preservePaths.count
                else { throw GameRemovalError.unsupported }
            }
            if let green = rule.greenPreparation {
                let paths = green.blockedDirectories
                guard rule.portable != nil, rule.userDataDirectory != nil, !paths.isEmpty, paths.count <= 64,
                      paths.allSatisfy({ PortableArchiveReader.safePath($0) && $0.split(separator: "/").count >= 2 }),
                      Set(paths.map { $0.lowercased() }).count == paths.count,
                      !paths.contains(where: { path in paths.contains { $0 != path && $0.lowercased().hasPrefix(path.lowercased() + "/") } })
                else { throw GameRemovalError.unsupported }
            }
        }
        for rule in document.rules {
            if let id = rule.launcherID {
                guard let launcher = document.rules.first(where: { $0.id == id && $0.kind == "launcher" }),
                      rule.installDirectory.hasPrefix(launcher.installDirectory + "/games/") else { throw GameRemovalError.unsupported }
            }
        }
        return document.rules
    }

    // Shipped/reviewed resources only; no downloaded rules or executable scripts.
    private static let sources: [URL] = {
        let bundle = Bundle.main
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: "GameAdaptations") ?? [])
            + (bundle.urls(forResourcesWithExtension: "json", subdirectory: "Resources/GameAdaptations") ?? [])
        return urls.isEmpty ? [bundle.url(forResource: "hypergryph", withExtension: "json")].compactMap { $0 } : urls
    }()
    static let all: [GameAdaptationRule] = {
        do {
            let rules = try Set(sources).sorted { $0.path < $1.path }.flatMap { try decode(Data(contentsOf: $0)) }
            guard Set(rules.map(\.id)).count == rules.count else { return [] }
            return rules
        } catch { return [] }
    }()

    static let processNames: [ProcessName] = {
        do {
            return try Set(sources).sorted { $0.path < $1.path }.flatMap { url -> [ProcessName] in
                let data = try Data(contentsOf: url)
                _ = try decode(data)
                return try JSONDecoder().decode(Document.self, from: data).processNames ?? []
            }
        } catch { return [] }
    }()

    static func processName(for executable: URL, bottle: URL) -> String? {
        let target = executable.standardizedFileURL
        guard target.path.hasPrefix(bottle.appendingPathComponent("drive_c").standardizedFileURL.path + "/"),
              target.resolvingSymlinksInPath().path == target.path, PortableSoftwareService.isExecutable(target) else { return nil }
        let matches = processNames.filter { entry in
            guard entry.executable.caseInsensitiveCompare(target.lastPathComponent) == .orderedSame else { return false }
            if let ancestor = entry.ancestorDirectoryName, !target.deletingLastPathComponent().pathComponents.contains(ancestor) { return false }
            if let id = entry.ruleID {
                guard let rule = rule(id: id), rule.recognizes(target), rule.allows(target, in: bottle) else { return false }
            }
            return true
        }
        return matches.count == 1 ? matches[0].name : nil
    }

    /// WINEPRELOADERAPPNAME is consumed/unset by Wine's loader, unlike the legacy global Dock override.
    static func processEnvironment(_ original: [String: String], executable: URL? = nil, bottle: URL? = nil) -> [String: String] {
        var environment = original
        environment.removeValue(forKey: "PROCYON_WINE_DOCK_NAME")
        environment.removeValue(forKey: "WINEPRELOADERAPPNAME")
        if let executable, let bottle, let name = processName(for: executable, bottle: bottle) {
            environment["WINEPRELOADERAPPNAME"] = name
        }
        return environment
    }

    static func rule(id: String) -> GameAdaptationRule? { all.first { $0.id == id } }
    static func matching(_ executable: URL) -> GameAdaptationRule? { all.first { $0.recognizes(executable) } }
    static func validate(_ executable: URL, bottle: URL) throws {
        guard !all.isEmpty else {
            throw NSError(domain: "Arclume.Adaptation", code: 3, userInfo: [NSLocalizedDescriptionKey: "内置游戏适配规则缺失或无效，请重新构建或安装 Arclume；未启动程序。"])
        }
        if let rule = matching(executable), !rule.allows(executable, in: bottle) {
            throw NSError(domain: "Arclume.Adaptation", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "\(rule.name) 的安装目录已固定为 \(rule.windowsDirectory)。当前入口不在该目录，未启动或移动任何文件；请在原启动器中选择规定目录后重新扫描。"])
        }
    }
}
