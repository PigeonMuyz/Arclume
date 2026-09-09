import Foundation
import Darwin

nonisolated struct PortableChoice: Identifiable, Sendable {
    let id: String
    let name: String
    let root: URL
    let executable: String
    let installDirectory: String
    let ruleID: String?
    let preservePaths: [String]
}

nonisolated struct PortablePackage: Sendable {
    let staging: URL
    let choices: [PortableChoice]
}

nonisolated struct PortableReceipt: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let ruleID: String?
    let name: String
    let executable: String
    let installDirectory: String
    let generation: UUID
}

nonisolated struct PortableInstallPreview: Sendable {
    let choice: PortableChoice
    let bottle: URL
    let destination: URL
    let previous: PortableReceipt?
    var isUpdate: Bool { previous != nil }
}

nonisolated enum PortableSoftwareService {
    static let receiptName = ".arclume-portable.json"
    static let fail = PortableArchiveReader.failure

    static func prepare(_ archive: URL) throws -> PortablePackage {
        let staging = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("Arclume-Portable-\(UUID().uuidString)")
        try PortableArchiveReader.extract(archive, to: staging)
        do { return try inspect(staging) }
        catch { try? FileManager.default.removeItem(at: staging); throw error }
    }

    static func inspect(_ staging: URL) throws -> PortablePackage {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: staging, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw GameRemovalError.unsafePath }
        var executables: [URL] = []
        for case let discovered as URL in walker {
            try Task.checkCancellation()
            let url = discovered.standardizedFileURL
            guard url.resolvingSymlinksInPath().path == url.path else {
                throw GameRemovalError.unsafePath
            }
            if url.pathExtension.lowercased() == "exe", isExecutable(url) { executables.append(url) }
        }
        let matches: [PortableChoice] = executables.flatMap { exe in
            GameAdaptationRules.all.filter { $0.portable != nil && $0.recognizes(exe) }.map { rule in
                PortableChoice(id: exe.path, name: rule.name, root: exe.deletingLastPathComponent(),
                    executable: exe.lastPathComponent, installDirectory: rule.installDirectory,
                    ruleID: rule.id, preservePaths: rule.portable!.preservePaths)
            }
        }
        if !matches.isEmpty { return .init(staging: staging, choices: matches.sorted { $0.id < $1.id }) }
        guard !executables.isEmpty else { throw fail("压缩包中没有有效的 Windows EXE 程序。") }
        // Unknown packages retain their complete tree, stripping only a sole wrapper directory.
        var root = staging
        while true {
            let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            guard children.count == 1, try children[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { break }
            root = children[0].standardizedFileURL
        }
        let directory = "PortableApps/Custom-\(UUID().uuidString)"
        return .init(staging: staging, choices: executables.sorted { $0.path < $1.path }.map { exe in
            .init(id: exe.path, name: exe.deletingPathExtension().lastPathComponent, root: root,
                executable: String(exe.path.dropFirst(root.path.count + 1)), installDirectory: directory,
                ruleID: nil, preservePaths: [])
        })
    }

    static func isExecutable(_ url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) == Data([0x4d, 0x5a])
    }

    static func readReceipt(at root: URL) throws -> PortableReceipt {
        let file = root.appendingPathComponent(receiptName)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard file.resolvingSymlinksInPath().path == file.path,
              values.isRegularFile == true, values.fileSize ?? Int.max < 16_384 else { throw GameRemovalError.unsafePath }
        let receipt = try JSONDecoder().decode(PortableReceipt.self, from: Data(contentsOf: file))
        guard receipt.schemaVersion == 1, PortableArchiveReader.safePath(receipt.executable),
              receipt.installDirectory.hasPrefix("PortableApps/"),
              receipt.installDirectory.split(separator: "/").count == 2,
              GameAdaptationRules.safeRelativePath(receipt.installDirectory) else { throw GameRemovalError.unsafePath }
        return receipt
    }

    static func preview(_ choice: PortableChoice, bottle: URL, ownedBottles: [URL]) throws -> PortableInstallPreview {
        guard ownedBottles.contains(where: { $0.standardizedFileURL.path == bottle.standardizedFileURL.path }), bottle.standardizedFileURL.path == bottle.resolvingSymlinksInPath().path,
              (try bottle.appendingPathComponent("drive_c").resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true,
              GameAdaptationRules.safeRelativePath(choice.installDirectory),
              choice.installDirectory.hasPrefix("PortableApps/"), choice.installDirectory.split(separator: "/").count == 2,
              PortableArchiveReader.safePath(choice.executable),
              isExecutable(choice.root.appendingPathComponent(choice.executable)) else { throw GameRemovalError.unsafePath }
        let destination = bottle.appendingPathComponent("drive_c/" + choice.installDirectory)
        guard destination.resolvingSymlinksInPath().path == destination.path else { throw GameRemovalError.unsafePath }
        var previous: PortableReceipt?
        if FileManager.default.fileExists(atPath: destination.path) {
            guard let receipt = try? readReceipt(at: destination), receipt.ruleID == choice.ruleID,
                  receipt.executable == choice.executable, receipt.installDirectory == choice.installDirectory,
                  isExecutable(destination.appendingPathComponent(receipt.executable)) else {
                throw fail("目标目录已有非 Arclume 导入或不匹配的程序，未覆盖。")
            }
            previous = receipt
        }
        return .init(choice: choice, bottle: bottle, destination: destination, previous: previous)
    }

    /// A sibling transaction directory remains as the recovery copy after an atomic update.
    /// No user AppData or Wine registry is modified. Unknown old local files remain recoverable.
    static func install(_ preview: PortableInstallPreview, ownedBottles: [URL],
                        requireIdle: () throws -> Void = GameAssociatedDataService.requireRegistryIdle,
                        exchange: (URL, URL) throws -> Void = atomicExchange) throws -> (InstalledProgramCandidate, URL?) {
        try requireIdle()
        let current = try self.preview(preview.choice, bottle: preview.bottle, ownedBottles: ownedBottles)
        guard current.previous == preview.previous else { throw GameRemovalError.changed }
        let choice = preview.choice, destination = preview.destination
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let transaction = parent.appendingPathComponent(".arclume-recovery-\(UUID().uuidString)")
        try fm.createDirectory(at: transaction, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let staged = transaction.appendingPathComponent("previous")
        var installed = false
        defer { if !installed { try? fm.removeItem(at: transaction) } }
        try checkedTree(choice.root)
        try fm.copyItem(at: choice.root, to: staged)
        if preview.isUpdate {
            try checkedTree(destination)
            for path in choice.preservePaths {
                guard PortableArchiveReader.safePath(path), !path.contains("/") else { throw GameRemovalError.unsafePath }
                let old = destination.appendingPathComponent(path), replacement = staged.appendingPathComponent(path)
                if fm.fileExists(atPath: old.path) {
                    if fm.fileExists(atPath: replacement.path) { try fm.removeItem(at: replacement) }
                    try fm.copyItem(at: old, to: replacement)
                }
            }
        }
        guard isExecutable(staged.appendingPathComponent(choice.executable)) else { throw GameRemovalError.changed }
        let receipt = PortableReceipt(schemaVersion: 1, ruleID: choice.ruleID, name: choice.name,
            executable: choice.executable, installDirectory: choice.installDirectory, generation: UUID())
        try JSONEncoder().encode(receipt).write(to: staged.appendingPathComponent(receiptName), options: .atomic)
        let ticket = try ArclumeWineStopService.launchTicket()
        try ArclumeWineStopService.withLaunchTicket(ticket) {
            try requireIdle()
            let final = try self.preview(choice, bottle: preview.bottle, ownedBottles: ownedBottles)
            guard final.previous == preview.previous else { throw GameRemovalError.changed }
            if preview.isUpdate {
                // RENAME_SWAP either swaps both names, or leaves the old installation untouched.
                try exchange(staged, destination)
            } else {
                try fm.moveItem(at: staged, to: destination)
            }
        }
        installed = true
        if !preview.isUpdate { try? fm.removeItem(at: transaction) }
        let exe = destination.appendingPathComponent(choice.executable)
        return (.init(entry: exe, executable: exe, name: choice.name, fingerprint: receipt.generation.uuidString),
                preview.isUpdate ? transaction : nil)
    }

    static func atomicExchange(_ staged: URL, _ destination: URL) throws {
        guard renameatx_np(AT_FDCWD, staged.path, AT_FDCWD, destination.path, UInt32(RENAME_SWAP)) == 0 else {
            throw fail("无法原子替换软件，旧版本未改动。请检查磁盘空间和文件系统。")
        }
    }

    static func checkedTree(_ root: URL) throws {
        var enumerationError: Error?
        guard root.resolvingSymlinksInPath().path == root.path,
              let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                errorHandler: { _, error in enumerationError = error; return false }) else { throw GameRemovalError.unsafePath }
        for case let discovered as URL in walker {
            try Task.checkCancellation()
            let url = discovered.standardizedFileURL
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true,
                  url.resolvingSymlinksInPath().path == url.path else { throw GameRemovalError.unsafePath }
        }
        if let enumerationError { throw enumerationError }
    }

    static func removalPlan(executable: URL, bottle: URL) throws -> GameRemovalPlan? {
        let parent = bottle.appendingPathComponent("drive_c/PortableApps")
        guard executable.path.hasPrefix(parent.path + "/") else { return nil }
        let relative = String(executable.path.dropFirst(parent.path.count + 1))
        guard let leaf = relative.split(separator: "/").first, !leaf.hasPrefix(".") else { throw GameRemovalError.unsafePath }
        let root = parent.appendingPathComponent(String(leaf))
        let receipt = try readReceipt(at: root)
        guard receipt.installDirectory == "PortableApps/" + leaf,
              root.appendingPathComponent(receipt.executable) == executable,
              isExecutable(executable) else { throw GameRemovalError.unsafePath }
        try checkedTree(root)
        return .init(directory: root, executable: executable, bottle: bottle,
            bytes: try GameAssociatedDataService.checkedBytes(root, within: bottle), launcher: nil)
    }
}
