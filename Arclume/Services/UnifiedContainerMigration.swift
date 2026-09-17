import Foundation
import CryptoKit
import Darwin

/// Offline, copy/verify/switch migration. Never run Wine against a staging prefix.
/// All paths in the journal are relative to the injected support root.
nonisolated struct UnifiedContainerMigration: Sendable {
    static let legacyRoots = ["WindowsGameWinePrefixes", "OnlineGameWinePrefixes", "CXPBottles"]
    static let registryNames = ["system.reg", "user.reg", "userdef.reg"]
    let root: URL
    private let physicalRoot: String
    init(root: URL) {
        self.root = root
        if let pointer = realpath(root.path, nil) {
            physicalRoot = String(cString: pointer)
            free(pointer)
        } else { physicalRoot = root.path }
    }
    /// Normalize only the root's filesystem alias, never links inside a prefix.
    private func scopedPath(_ url: URL) -> String {
        let value = url.path
        if value == physicalRoot || value.hasPrefix(physicalRoot + "/") {
            return root.path + value.dropFirst(physicalRoot.count)
        }
        return value
    }
    private var fm: FileManager { .default }
    var destination: URL { root.appendingPathComponent("ALBottles") }
    var journalURL: URL { root.appendingPathComponent("ALBottles-migration.json") }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    struct Journal: Codable, Sendable {
        enum Phase: String, Codable { case copying, switching, complete, cleaning, finalized, rolledBack }
        let version: Int
        let id: UUID
        let sources: [String]
        var phase: Phase
    }
    struct Entry: Equatable, Sendable {
        enum Kind: Sendable { case directory, file, link }
        let kind: Kind
        let signature: String
        let bytes: Int64
    }
    struct Plan: Sendable {
        let sources: [String]
        let snapshots: [[String: Entry]]
        let files: [String: Int]
        let registries: [String: String]
        let notices: [String]
        let conflicts: [String]
        let bytes: Int64
    }

    private func fail(_ message: String) -> Failure { Failure(message: message) }
    private func exists(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path)) != nil // includes dangling symlinks
    }
    private func isLink(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeSymbolicLink
    }
    private func safe(_ url: URL) throws {
        let boundary = root.path
        guard boundary != "/", !isLink(root) else {
            throw fail("数据根目录不是独立的真实目录，未迁移。")
        }
        guard scopedPath(url).hasPrefix(boundary + "/"), !url.pathComponents.contains("..") else {
            throw fail("迁移路径越界，未修改数据。\n根目录：\(boundary)\n目标：\(url.path)")
        }
        // Walk strings: URL.deleteLastPathComponent can normalize /private/var to /var
        // partway through, which must not make an ancestor walk fail to terminate.
        var current = scopedPath(url)
        while current != boundary {
            guard current != "/", !current.isEmpty else { throw fail("迁移路径越界。") }
            guard !isLink(URL(fileURLWithPath: current)) else { throw fail("迁移路径含符号链接：\((current as NSString).lastPathComponent)") }
            current = (current as NSString).deletingLastPathComponent
        }
    }
    private func validSource(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && Self.legacyRoots.contains(String(parts[0])) &&
            !["", ".", ".."].contains(String(parts[1]))
    }
    func recoveryURL(_ journal: Journal) -> URL {
        root.appendingPathComponent("ContainerMigrationRecovery/\(journal.id.uuidString)")
    }
    func journal() throws -> Journal? {
        try safe(journalURL)
        guard exists(journalURL) else { return nil }
        let value = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard value.version == 1, !value.sources.isEmpty, value.sources.allSatisfy(validSource),
              Set(value.sources).count == value.sources.count else { throw fail("迁移记录无效，需手动检查恢复目录。") }
        try safe(recoveryURL(value))
        return value
    }
    private func save(_ journal: Journal) throws {
        try safe(journalURL)
        let data = try JSONEncoder().encode(journal)
        let archive = recoveryURL(journal).appendingPathComponent("journal.json")
        try safe(archive)
        try data.write(to: archive, options: .atomic)
        try data.write(to: journalURL, options: .atomic)
    }
    /// Only Arclume-managed roots. Third-party CrossOver bottles are not imported.
    func sources() throws -> [String] {
        var result: [String] = []
        for folder in Self.legacyRoots {
            let parent = root.appendingPathComponent(folder)
            try safe(parent)
            guard exists(parent) else { continue }
            for child in try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
                where !child.lastPathComponent.hasPrefix(".") {
                if isLink(child), child.resolvingSymlinksInPath().standardizedFileURL.path == destination.standardizedFileURL.path { continue }
                try safe(child)
                guard (try child.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { continue }
                guard Self.registryNames.allSatisfy({ exists(child.appendingPathComponent($0)) }),
                      exists(child.appendingPathComponent("drive_c")) else {
                    throw fail("旧容器不完整：\(folder)/\(child.lastPathComponent)。请先检查，未跳过其中的数据。")
                }
                result.append(folder + "/" + child.lastPathComponent)
            }
        }
        return result.sorted { a, b in
            if a == b { return false }
            if a == "WindowsGameWinePrefixes/Steam" { return true }
            if b == "WindowsGameWinePrefixes/Steam" { return false }
            return a < b
        }
    }
    func requiresMigration() throws -> Bool {
        if let record = try journal(), record.phase != .rolledBack {
            if record.phase != .finalized { return true }
            try validatePublished(record)
        }
        let legacy = try sources()
        if !legacy.isEmpty, exists(destination) {
            throw fail("ALBottles 与未迁移的旧容器同时存在。为避免覆盖，已暂停加载；请检查迁移记录。")
        }
        try safe(destination)
        return !legacy.isEmpty
    }

    private func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func snapshot(_ prefix: URL) throws -> [String: Entry] {
        try safe(prefix)
        var result: [String: Entry] = [:]
        var enumerationError: Error?
        guard let iterator = fm.enumerator(at: prefix, includingPropertiesForKeys: nil,
            errorHandler: { _, error in enumerationError = error; return false }) else { throw fail("无法读取容器。") }
        for case let url as URL in iterator {
            let path = scopedPath(url)
            let basePath = scopedPath(prefix)
            guard path.hasPrefix(basePath + "/") else { throw fail("容器枚举路径越界。") }
            let name = String(path.dropFirst(basePath.count + 1))
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as? FileAttributeType
            switch type {
            case .typeSymbolicLink:
                iterator.skipDescendants()
                result[name] = Entry(kind: .link, signature: try fm.destinationOfSymbolicLink(atPath: url.path), bytes: 0)
            case .typeDirectory:
                result[name] = Entry(kind: .directory, signature: "", bytes: 0)
            case .typeRegular:
                result[name] = Entry(kind: .file, signature: try hash(url), bytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0)
            default: throw fail("容器包含不能安全复制的特殊文件：\(name)")
            }
        }
        if let enumerationError { throw enumerationError }
        return result
    }

    func preflight(checkIdle: () throws -> Void) throws -> Plan {
        try checkIdle()
        if let record = try journal(), record.phase != .rolledBack { throw fail("请先处理已有迁移记录。") }
        try safe(destination)
        guard !exists(destination) else { throw fail("ALBottles 已存在，拒绝覆盖。") }
        let paths = try sources()
        guard !paths.isEmpty else { throw fail("没有待迁移的旧容器。") }
        let snapshots = try paths.map { try snapshot(root.appendingPathComponent($0)) }
        var files: [String: Int] = [:], spellings: [String: String] = [:]
        var notices: [String] = [], conflicts: [String] = []
        for (index, tree) in snapshots.enumerated() {
            for name in tree.keys.sorted() {
                let entry = tree[name]!
                // Disk-image device numbers are reused by macOS. A raw d:: device
                // is not a live application mapping when its paired /Volumes d:
                // mount has disappeared. Keep it only in the original backup.
                if index > 0, name.hasPrefix("dosdevices/"), name.hasSuffix("::"), entry.kind == .link,
                   entry.signature.hasPrefix("/dev/"),
                   let mount = tree[String(name.dropLast())], mount.kind == .link,
                   mount.signature.hasPrefix("/Volumes/"),
                   !fm.fileExists(atPath: root.appendingPathComponent(paths[index]).appendingPathComponent(String(name.dropLast())).path) {
                    notices.append("不导入已卸载卷的设备映射：\(name)")
                    continue
                }
                let folded = name.precomposedStringWithCanonicalMapping.lowercased()
                if let previous = spellings[folded], previous != name {
                    conflicts.append("大小写不同的同名路径：\(previous) / \(name)"); continue
                }
                spellings[folded] = name
                if let previous = files[name] {
                    guard snapshots[previous][name] != entry else { continue }
                    if Self.registryNames.contains(name) { continue }
                    let lower = name.lowercased()
                    if entry.kind == snapshots[previous][name]?.kind &&
                        (lower.hasPrefix("drive_c/windows/") || lower.contains("/inetcache/") ||
                         lower.hasSuffix(".ds_store") || name.hasPrefix(".arclume-") || name == ".update-timestamp" ||
                         Self.registryNames.contains(where: { name == $0 + ".orig" || name == $0 + ".procyon-backup" })) {
                        notices.append("保留基础容器系统/缓存文件：\(name)")
                    } else if lower.hasPrefix("dosdevices/"), entry.kind == .link,
                              snapshots[previous][name]?.kind == .link,
                              !fm.fileExists(atPath: root.appendingPathComponent(paths[index]).appendingPathComponent(name).path) {
                        notices.append("不导入失效盘符：\(name)")
                    } else {
                        conflicts.append("文件或盘符冲突：\(name)")
                    }
                } else { files[name] = index }
            }
        }
        // A link or file must never become an ancestor of another source's data.
        for name in files.keys {
            var parent = (name as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if let owner = files[parent], snapshots[owner][parent]?.kind != .directory {
                    conflicts.append("拒绝穿过链接/文件合并：\(name)")
                    break
                }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        var registries: [String: String] = [:]
        for name in Self.registryNames {
            guard snapshots.allSatisfy({ $0[name]?.kind == .file }) else { throw fail("注册表必须为普通文件。") }
            var registry = try WineMigrationRegistry(String(contentsOf: root.appendingPathComponent(paths[0]).appendingPathComponent(name), encoding: .utf8))
            for path in paths.dropFirst() {
                let incoming = try WineMigrationRegistry(String(contentsOf: root.appendingPathComponent(path).appendingPathComponent(name), encoding: .utf8))
                guard registry.architecture == incoming.architecture else {
                    throw fail("容器架构不同，不能安全合并：\(name)。")
                }
                for key in registry.merge(incoming) {
                    // Machine identities and shared Windows registrations keep the base's coherent state.
                    // Wine global overrides and third-party application settings never silently win.
                    let lower = key.lowercased()
                    if ["[system\\\\", "[control panel\\\\", "[software\\\\microsoft\\\\",
                        "[software\\\\classes\\\\", "[software\\\\wow6432node\\\\microsoft\\\\",
                        "[software\\\\wine\\\\drivers\\\\"].contains(where: lower.hasPrefix) {
                        notices.append("保留基础容器系统注册表：\(name) \(key)")
                    } else { conflicts.append("应用注册表冲突：\(name) \(key)") }
                }
            }
            registries[name] = registry.serialized
        }
        let bytes = files.reduce(Int64(0)) { $0 + snapshots[$1.value][$1.key]!.bytes }
        try checkIdle()
        return Plan(sources: paths, snapshots: snapshots, files: files, registries: registries,
                    notices: notices.sorted(), conflicts: Array(Set(conflicts)).sorted(), bytes: bytes)
    }

    /// The caller confirms the exact preflight plan; source hashes are checked again before publishing.
    func migrate(_ plan: Plan, preferencesDomain: String, checkIdle: () throws -> Void,
                 progress: @Sendable (Double, String) -> Void = { _, _ in },
                 checkpoint: (String) throws -> Void = { _ in }) throws -> Journal {
        try withLock {
            try checkIdle()
            guard plan.conflicts.isEmpty else { throw fail("存在未解决冲突，未迁移。") }
            guard try sources() == plan.sources, !exists(destination) else { throw fail("容器状态已变化，请重新检查。") }
            if let previous = try journal(), previous.phase != .rolledBack { throw fail("请先恢复上次迁移。") }
            let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
            guard let available, available > plan.bytes + 512 * 1024 * 1024 else { throw fail("磁盘空间不足：需要完整容器副本及至少 512 MB 余量。") }
            var record = Journal(version: 1, id: UUID(), sources: plan.sources, phase: .copying)
            let recovery = recoveryURL(record), stage = recovery.appendingPathComponent("staging")
            try safe(stage)
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            let prefs = UserDefaults(suiteName: preferencesDomain)?.persistentDomain(forName: preferencesDomain) ?? [:]
            let prefsData = try PropertyListSerialization.data(fromPropertyList: prefs, format: .binary, options: 0)
            try prefsData.write(to: recovery.appendingPathComponent("preferences.plist"), options: .atomic)
            try Data(preferencesDomain.utf8).write(to: recovery.appendingPathComponent("preferences-domain.txt"), options: .atomic)
            try save(record)
            progress(0, "正在准备安全副本…")
            try checkpoint("copying")
            // Directories first. copyItem preserves files, permissions and links without following links.
            let orderedFiles = plan.files.keys.sorted(by: { ($0.split(separator: "/").count, $0) < ($1.split(separator: "/").count, $1) })
            for (index, name) in orderedFiles.enumerated() {
                let owner = plan.files[name]!, entry = plan.snapshots[owner][name]!
                let from = root.appendingPathComponent(plan.sources[owner]).appendingPathComponent(name)
                let to = stage.appendingPathComponent(name)
                try safe(to)
                if entry.kind == .directory { try fm.createDirectory(at: to, withIntermediateDirectories: false) }
                else { try fm.copyItem(at: from, to: to) }
                if index % 100 == 0 { progress(0.55 * Double(index + 1) / Double(orderedFiles.count), "正在合并应用文件…") }
            }
            // Verify every copied byte/link before modifying registry files.
            progress(0.6, "正在校验迁移副本…")
            let copied = try snapshot(stage)
            for (name, owner) in plan.files where copied[name] != plan.snapshots[owner][name] {
                throw fail("复制校验失败：\(name)。旧容器未修改。")
            }
            for (name, text) in plan.registries {
                try Data(text.utf8).write(to: stage.appendingPathComponent(name), options: .atomic)
                guard try String(contentsOf: stage.appendingPathComponent(name), encoding: .utf8) == text else { throw fail("注册表写入校验失败。") }
            }
            progress(0.75, "正在同步系统配置…")
            try Data(record.id.uuidString.utf8).write(to: stage.appendingPathComponent(".arclume-migration-id"), options: .atomic)
            try Data((plan.notices + plan.conflicts).joined(separator: "\n").utf8)
                .write(to: recovery.appendingPathComponent("merge-report.txt"), options: .atomic)
            for (i, path) in plan.sources.enumerated() {
                progress(0.8 + 0.1 * Double(i) / Double(plan.sources.count), "正在复核原容器…")
                guard try snapshot(root.appendingPathComponent(path)) == plan.snapshots[i] else {
                    throw fail("源容器在检查后发生变化，已取消切换。请退出 Windows 应用后恢复并重试。")
                }
            }
            try checkIdle()
            record.phase = .switching
            try save(record) // write-ahead journal: rollback does not depend on a successful next write
            try checkpoint("switching")
            progress(0.95, "正在切换到 ALBottles…")
            try fm.moveItem(at: stage, to: destination)
            try checkpoint("published")
            for (i, source) in plan.sources.enumerated() {
                let original = root.appendingPathComponent(source)
                try fm.moveItem(at: original, to: recovery.appendingPathComponent("original-\(i)"))
                try checkpoint("moved-\(i)")
                try fm.createSymbolicLink(at: original, withDestinationURL: destination)
            }
            try rewritePreferences(prefs, domain: preferencesDomain, journal: record)
            try checkpoint("preferences")
            record.phase = .complete
            try save(record)
            try validatePublished(record)
            progress(1, "迁移完成")
            return record
        }
    }

    func rollback(preferencesDomain: String, checkIdle: () throws -> Void) throws {
        try withLock {
            try checkIdle()
            guard var record = try journal(), record.phase != .rolledBack else { return }
            guard record.phase != .cleaning && record.phase != .finalized else {
                throw fail("升级已提交，不能恢复旧副本；请继续完成升级。")
            }
            let recovery = recoveryURL(record)
            // Check all targets before changing anything, including after an interrupted rollback.
            for (i, source) in record.sources.enumerated() {
                let original = root.appendingPathComponent(source), backup = recovery.appendingPathComponent("original-\(i)")
                try safe(original.deletingLastPathComponent())
                try safe(backup)
                if isLink(original) {
                    guard try fm.destinationOfSymbolicLink(atPath: original.path) == destination.path, exists(backup) else { throw fail("旧路径被修改，不能自动恢复：\(source)") }
                } else if exists(backup) && exists(original) { throw fail("恢复目标已被占用：\(source)") }
                else if !exists(backup) && !exists(original) { throw fail("原容器及恢复副本均缺失：\(source)") }
            }
            if exists(destination) { try validateMarker(record) }
            let domainFile = recovery.appendingPathComponent("preferences-domain.txt")
            let preferencesFile = recovery.appendingPathComponent("preferences.plist")
            try safe(domainFile); try safe(preferencesFile)
            guard try String(contentsOf: domainFile, encoding: .utf8) == preferencesDomain,
                  let prefs = try PropertyListSerialization.propertyList(from: Data(contentsOf: preferencesFile), format: nil) as? [String: Any] else {
                throw fail("偏好恢复副本无效，未恢复。")
            }
            for (i, source) in record.sources.enumerated().reversed() {
                let original = root.appendingPathComponent(source), backup = recovery.appendingPathComponent("original-\(i)")
                if isLink(original) { try fm.removeItem(at: original) } // only the verified alias, never its destination
                if exists(backup) { try fm.moveItem(at: backup, to: original) }
            }
            if exists(destination) {
                try fm.moveItem(at: destination, to: recovery.appendingPathComponent("unactivated-\(UUID().uuidString)"))
            }
            UserDefaults(suiteName: preferencesDomain)?.setPersistentDomain(prefs, forName: preferencesDomain)
            record.phase = .rolledBack
            try save(record)
        }
    }

    private func validateMarker(_ record: Journal) throws {
        let marker = destination.appendingPathComponent(".arclume-migration-id")
        try safe(marker)
        guard try String(contentsOf: marker, encoding: .utf8) == record.id.uuidString else { throw fail("ALBottles 不属于本次迁移，拒绝移动。") }
    }
    private func validatePublished(_ record: Journal) throws {
        try validateMarker(record)
        for (i, source) in record.sources.enumerated() {
            let url = root.appendingPathComponent(source)
            try safe(url.deletingLastPathComponent())
            guard isLink(url), try fm.destinationOfSymbolicLink(atPath: url.path) == destination.path else {
                throw fail("迁移记录与旧路径不一致，已停止操作。")
            }
            if record.phase == .complete {
                let backup = recoveryURL(record).appendingPathComponent("original-\(i)")
                try safe(backup)
                guard exists(backup) else { throw fail("迁移恢复副本缺失，已停止操作。") }
            }
        }
    }

    /// Once cleaning is durably recorded, only resume cleanup; never roll back partial backups.
    /// Keep the tiny journal/report, but no duplicate containers or preference snapshots.
    func finalize(preferencesDomain: String, checkIdle: () throws -> Void,
                  checkpoint: (String) throws -> Void = { _ in }) throws -> Journal {
        try withLock {
            try checkIdle()
            guard var record = try journal(), [.complete, .cleaning, .finalized].contains(record.phase) else {
                throw fail("迁移尚未校验完成，不能清理。")
            }
            try validatePublished(record)
            if record.phase == .finalized { return record }
            let recovery = recoveryURL(record)
            let targets = record.sources.indices.map { recovery.appendingPathComponent("original-\($0)") } +
                ["preferences.plist", "preferences-domain.txt"].map { recovery.appendingPathComponent($0) }
            for target in targets { try safe(target) }
            if record.phase == .complete {
                let domainFile = recovery.appendingPathComponent("preferences-domain.txt")
                guard try String(contentsOf: domainFile, encoding: .utf8) == preferencesDomain else {
                    throw fail("偏好域不匹配，未清理副本。")
                }
                try refreshLibraryBookmarks(domain: preferencesDomain)
                record.phase = .cleaning
                try save(record)
            }
            try checkpoint("cleaning")
            for (index, target) in targets.enumerated() {
                try safe(target)
                if exists(target) { try fm.removeItem(at: target) }
                try checkpoint("cleaned-\(index)")
            }
            record.phase = .finalized
            try save(record)
            return record
        }
    }

    private func refreshLibraryBookmarks(domain: String) throws {
        guard let defaults = UserDefaults(suiteName: domain) else { throw fail("无法读取游戏库设置。") }
        let bookmarks = defaults.array(forKey: "steamLibraryBookmarks") as? [Data] ?? []
        let updated = try bookmarks.map { data -> Data in
            var stale = false
            let resolved = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
            // File-ID bookmarks may stop resolving after the source directory moves.
            // Read their stored path through Foundation, never patch opaque bookmark bytes.
            let stored = URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: data)?.path.map { URL(fileURLWithPath: $0) }
            guard let original = [resolved, stored].compactMap({ $0 }).first(where: {
                canonicalURL($0).path != $0.path
            }) else {
                return data // Preserve unrelated/unavailable external library bookmarks.
            }
            let canonical = canonicalURL(original)
            guard fm.fileExists(atPath: canonical.path) else { throw fail("迁移后的游戏库缺失，未清理副本。") }
            return try canonical.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        if updated != bookmarks {
            defaults.set(updated, forKey: "steamLibraryBookmarks")
            guard defaults.synchronize() else { throw fail("游戏库设置未保存，未清理副本。") }
        }
    }
    private func withLock<T>(_ body: () throws -> T) throws -> T {
        let path = root.appendingPathComponent(".ALBottles-migration.lock")
        try safe(path)
        let descriptor = open(path.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw fail("无法锁定迁移目录。") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw fail("另一个 Arclume 正在迁移。") }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    func canonicalURL(_ url: URL) -> URL {
        guard let record = try? journal(), [.complete, .cleaning, .finalized].contains(record.phase) else { return url }
        let paths = record.sources.map { root.appendingPathComponent($0) } +
            record.sources.indices.map { recoveryURL(record).appendingPathComponent("original-\($0)") }
        let path = scopedPath(url)
        for old in paths where path == old.path || path.hasPrefix(old.path + "/") {
            return URL(fileURLWithPath: destination.path + path.dropFirst(old.path.count))
        }
        return url
    }
    private func rewritePreferences(_ preferences: [String: Any], domain: String, journal: Journal) throws {
        let oldURLs = journal.sources.map { root.appendingPathComponent($0) }
        func replace(_ string: String) -> String {
            for url in oldURLs {
                for (old, new) in [(url.path, destination.path), (url.absoluteString, destination.absoluteString)] {
                    if string == old || string.hasPrefix(old + "/") { return new + string.dropFirst(old.count) }
                    if string.hasPrefix("GameOptions." + old + "/") {
                        return "GameOptions." + new + string.dropFirst("GameOptions.".count + old.count)
                    }
                }
            }
            return string
        }
        func convert(_ value: Any) throws -> Any {
            if let string = value as? String { return replace(string) }
            if let array = value as? [Any] { return try array.map(convert) }
            if let dictionary = value as? [String: Any] {
                var result: [String: Any] = [:]
                for (key, value) in dictionary {
                    let updated = replace(key), converted = try convert(value)
                    if let previous = result[updated], !NSDictionary(dictionary: ["v": previous]).isEqual(to: ["v": converted]) {
                        throw fail("合并后的应用偏好键冲突，需恢复后检查：\(updated)")
                    }
                    result[updated] = converted
                }
                return result
            }
            if let data = value as? Data, let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
                return try JSONSerialization.data(withJSONObject: convert(json), options: [.fragmentsAllowed, .sortedKeys])
            }
            return value // opaque bookmarks are not rewritten; canonicalURL handles their resolved URLs
        }
        let updated = try convert(preferences) as! [String: Any]
        UserDefaults(suiteName: domain)?.setPersistentDomain(updated, forName: domain)
    }
}

/// Lossless section/value merge for Wine REGISTRY Version 2 (including multiline hex values).
nonisolated struct WineMigrationRegistry {
    struct Section { var header: String; var lines: [String] }
    var preamble: [String] = []
    var keys: [String] = []
    var sections: [String: Section] = [:]
    var architecture: String? { preamble.first { $0.hasPrefix("#arch=") } }

    init(_ text: String) throws {
        guard text.hasPrefix("WINE REGISTRY Version 2") else {
            throw UnifiedContainerMigration.Failure(message: "不支持的 Wine 注册表格式。")
        }
        var active: String?
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("[") {
                guard let end = line.range(of: "]", options: .backwards) else { throw UnifiedContainerMigration.Failure(message: "注册表节损坏。") }
                let key = String(line[...end.lowerBound]).lowercased()
                guard sections[key] == nil else { throw UnifiedContainerMigration.Failure(message: "注册表包含重复节。") }
                active = key; keys.append(key); sections[key] = Section(header: line, lines: [])
            } else if let active { sections[active]!.lines.append(line) }
            else { preamble.append(line) }
        }
        guard architecture != nil else { throw UnifiedContainerMigration.Failure(message: "注册表缺少架构标记。") }
        for section in sections.values {
            let names = values(section).map(\.0)
            guard Set(names).count == names.count else {
                throw UnifiedContainerMigration.Failure(message: "注册表包含重复值，不能安全合并。")
            }
        }
    }
    private func values(_ section: Section) -> [(String, [String])] {
        var result: [(String, [String])] = []
        for line in section.lines {
            if let range = line.range(of: #"^(\"(?:[^\"\\]|\\.)*\"|@)="#, options: .regularExpression) {
                result.append((String(line[range].dropLast()).lowercased(), [line]))
            } else if !result.isEmpty { result[result.count - 1].1.append(line) }
        }
        return result
    }
    mutating func merge(_ incoming: Self) -> [String] {
        var conflicts: [String] = []
        for key in incoming.keys {
            guard var target = sections[key] else { keys.append(key); sections[key] = incoming.sections[key]; continue }
            let old = values(target)
            for (name, lines) in values(incoming.sections[key]!) {
                if let existing = old.first(where: { $0.0 == name }) {
                    if existing.1.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) != lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) {
                        conflicts.append(key + ":" + name)
                    }
                } else { target.lines.append(contentsOf: lines) }
            }
            sections[key] = target
        }
        return conflicts
    }
    var serialized: String {
        (preamble + keys.flatMap { [sections[$0]!.header] + sections[$0]!.lines + [""] }).joined(separator: "\n")
    }
}
