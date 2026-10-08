import Foundation
import Darwin

nonisolated enum PortableGreenPreparation {
    struct Plan: Sendable {
        let executable: URL
        let bottle: URL
        let ruleID: String
        let targets: [URL]
    }
    struct Record: Codable, Sendable {
        let relativePath: String
        let backup: String
        let hadOriginal: Bool
    }
    struct Journal: Codable, Sendable {
        let ruleID: String
        let records: [Record]
    }
    struct Result: Sendable {
        var changed = 0
        var recovery: URL?
        var error: String?
    }
    static let marker = "com.arclume.green-ad-block"

    static func plan(executable: URL, bottle: URL, ownedBottles: [URL]) throws -> Plan {
        guard ownedBottles.contains(where: { $0.standardizedFileURL.path == bottle.standardizedFileURL.path }),
              let rule = GameAdaptationRules.matching(executable), rule.allows(executable, in: bottle),
              let preparation = rule.greenPreparation, let dataDirectory = rule.userDataDirectory else { throw GameRemovalError.unsupported }
        let users = bottle.appendingPathComponent("drive_c/users").standardizedFileURL
        guard users.resolvingSymlinksInPath().path == users.path else { throw PortableArchiveReader.failure("Windows 用户目录包含重定向，未应用适配：\(users.path)") }
        var targets: [URL] = []
        for entry in try FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            // Directory enumeration may spell /var as /private/var; retain the verified root spelling.
            let user = users.appendingPathComponent(entry.lastPathComponent)
            let values = try user.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if ["public", "default", "default user", "all users"].contains(user.lastPathComponent.lowercased()) { continue }
            guard values.isSymbolicLink != true, values.isDirectory == true,
                  FileManager.default.fileExists(atPath: user.appendingPathComponent("AppData").path) else { continue }
            for path in preparation.blockedDirectories {
                let target = user.appendingPathComponent(dataDirectory).appendingPathComponent(path, isDirectory: false).standardizedFileURL
                try validate(target, bottle: bottle)
                targets.append(target)
            }
        }
        guard !targets.isEmpty, targets.count <= 512 else { throw PortableArchiveReader.failure("Windows 用户目录为空或目标数量超限，未应用适配。") }
        return .init(executable: executable, bottle: bottle, ruleID: rule.id, targets: targets.sorted { $0.path < $1.path })
    }

    static func validate(_ url: URL, bottle: URL) throws {
        guard url.path.hasPrefix(bottle.appendingPathComponent("drive_c/users").standardizedFileURL.path + "/"),
              url.resolvingSymlinksInPath().path == url.path else { throw PortableArchiveReader.failure("适配路径越界或包含重定向：\(url.path) → \(url.resolvingSymlinksInPath().path)") }
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw GameRemovalError.unsafePath }
            if values.isDirectory == true { try PortableSoftwareService.checkedTree(url) }
        }
    }

    static func isBlocker(_ url: URL, ruleID: String) -> Bool {
        // The same path changes from directory to file; never reuse URL resource-value caches.
        let current = URL(fileURLWithPath: url.path, isDirectory: false)
        guard let values = try? current.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == 0 else { return false }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = getxattr(url.path, marker, &bytes, bytes.count, 0, XATTR_NOFOLLOW)
        return count > 0 && String(decoding: bytes.prefix(count), as: UTF8.self) == ruleID
    }

    static func latestRecovery(_ plan: Plan) -> URL? {
        let base = plan.bottle.appendingPathComponent("drive_c/.arclume-green-recovery").standardizedFileURL
        guard base.resolvingSymlinksInPath().path == base.path,
              let children = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return children.map { base.appendingPathComponent($0.lastPathComponent) }.filter { child in
            guard UUID(uuidString: child.lastPathComponent) != nil,
                  child.resolvingSymlinksInPath().path == child.path,
                  !FileManager.default.fileExists(atPath: child.appendingPathComponent("restored").path) else { return false }
            let file = child.appendingPathComponent("recovery.json")
            guard file.resolvingSymlinksInPath().path == file.path,
                  let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true, let size = values.fileSize, size < 256 * 1024,
                  let data = try? Data(contentsOf: file), let journal = try? JSONDecoder().decode(Journal.self, from: data) else { return false }
            return journal.ruleID == plan.ruleID
        }.max {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
    }

    static func apply(_ plan: Plan, ownedBottles: [URL], requireIdle: () throws -> Void = GameAssociatedDataService.requireRegistryIdle) -> Result {
        var result = Result()
        do {
            let ticket = try ArclumeWineStopService.launchTicket()
            try ArclumeWineStopService.withLaunchTicket(ticket) {
                try requireIdle()
                let current = try self.plan(executable: plan.executable, bottle: plan.bottle, ownedBottles: ownedBottles)
                guard current.ruleID == plan.ruleID, current.targets.map(\.path) == plan.targets.map(\.path) else { throw GameRemovalError.changed }
                let pending = plan.targets.filter { !isBlocker($0, ruleID: plan.ruleID) }
                guard !pending.isEmpty else { return }
                let base = plan.bottle.appendingPathComponent("drive_c/.arclume-green-recovery").standardizedFileURL
                guard base.resolvingSymlinksInPath().path == base.path else { throw GameRemovalError.unsafePath }
                let recovery = base.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                result.recovery = recovery
                let records = pending.enumerated().map { index, target in
                    Record(relativePath: String(target.path.dropFirst(plan.bottle.standardizedFileURL.path.count + 1)),
                        backup: "original-\(index)", hadOriginal: FileManager.default.fileExists(atPath: target.path))
                }
                // Journal precedes mutations, so even a partial operation is recoverable.
                try JSONEncoder().encode(Journal(ruleID: plan.ruleID, records: records))
                    .write(to: recovery.appendingPathComponent("recovery.json"), options: .atomic)
                for (index, target) in pending.enumerated() {
                    try requireIdle()
                    try validate(target, bottle: plan.bottle)
                    let record = records[index]
                    if record.hadOriginal {
                        try FileManager.default.moveItem(at: target, to: recovery.appendingPathComponent(record.backup))
                    } else if FileManager.default.fileExists(atPath: target.path) { throw GameRemovalError.changed }
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let descriptor = open(target.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
                    guard descriptor >= 0 else { throw GameRemovalError.unsafePath }
                    close(descriptor)
                    let value = Data(plan.ruleID.utf8)
                    let status = value.withUnsafeBytes { setxattr(target.path, marker, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }
                    guard status == 0 else {
                        try? FileManager.default.removeItem(at: target)
                        throw PortableArchiveReader.failure("无法标记广告占位文件；原内容已保留在恢复目录。")
                    }
                    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: target.path)
                    result.changed += 1
                }
            }
        } catch { result.error = error.localizedDescription }
        return result
    }

    static func restore(_ recovery: URL, bottle: URL, ownedBottles: [URL], requireIdle: () throws -> Void = GameAssociatedDataService.requireRegistryIdle) throws {
        guard ownedBottles.contains(where: { $0.standardizedFileURL.path == bottle.standardizedFileURL.path }),
              recovery.deletingLastPathComponent().path == bottle.appendingPathComponent("drive_c/.arclume-green-recovery").path,
              recovery.resolvingSymlinksInPath().path == recovery.path else { throw GameRemovalError.unsafePath }
        try PortableSoftwareService.checkedTree(recovery)
        let journalFile = recovery.appendingPathComponent("recovery.json")
        guard (try journalFile.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max < 256 * 1024 else { throw GameRemovalError.unsafePath }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalFile))
        guard let rule = GameAdaptationRules.rule(id: journal.ruleID), let preparation = rule.greenPreparation,
              let dataDirectory = rule.userDataDirectory, journal.records.count <= 512 else { throw GameRemovalError.unsupported }
        let ticket = try ArclumeWineStopService.launchTicket()
        try ArclumeWineStopService.withLaunchTicket(ticket) {
            try requireIdle()
            for record in journal.records {
                guard GameAdaptationRules.safeRelativePath(record.relativePath),
                      record.relativePath.hasPrefix("drive_c/users/"),
                      preparation.blockedDirectories.contains(where: { record.relativePath.hasSuffix("/" + dataDirectory + "/" + $0) }),
                      GameAdaptationRules.safeRelativePath(record.backup), !record.backup.contains("/") else { throw GameRemovalError.unsafePath }
                let target = bottle.appendingPathComponent(record.relativePath).standardizedFileURL
                try validate(target, bottle: bottle)
                let backup = recovery.appendingPathComponent(record.backup)
                if record.hadOriginal, !FileManager.default.fileExists(atPath: backup.path) { continue }
                if FileManager.default.fileExists(atPath: target.path) {
                    guard isBlocker(target, ruleID: journal.ruleID) else { throw GameRemovalError.changed }
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                    try FileManager.default.removeItem(at: target)
                }
                if record.hadOriginal { try FileManager.default.moveItem(at: backup, to: target) }
            }
            try Data().write(to: recovery.appendingPathComponent("restored"), options: .atomic)
        }
    }
}
