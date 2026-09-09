import Foundation

nonisolated struct InstalledProgramCandidate: Identifiable, Equatable, Sendable {
    let entry: URL
    let executable: URL
    let name: String
    let fingerprint: String
    var id: String { entry.path }
    var isShortcut: Bool { entry.pathExtension.lowercased() == "lnk" }
}

nonisolated enum InstalledProgramDiscovery {
    /// Bounded, read-only traversal: never follow symlinked user folders or game libraries.
    static func scan(bottle: URL) -> [InstalledProgramCandidate] {
        let root = bottle.appendingPathComponent("drive_c").resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return [] }
        var results: [InstalledProgramCandidate] = []
        var visited = 0
        let excluded = Set(["windows", "steamapps", "temp", "cache", "caches", "node_modules", "$recycle.bin", "endfield_data"])
        for case let url as URL in walker {
            visited += 1
            if visited > 30_000 || Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { walker.skipDescendants(); continue }
            if values.isDirectory == true {
                if excluded.contains(url.lastPathComponent.lowercased()) || walker.level > 10 { walker.skipDescendants() }
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard ext == "lnk" || ext == "exe", !isHelper(url.deletingPathExtension().lastPathComponent) else { continue }
            var executable = url.standardizedFileURL.resolvingSymlinksInPath()
            if ext == "lnk" {
                guard (values.fileSize ?? 0) <= 1_048_576,
                      let data = try? Data(contentsOf: url), let path = shortcutTarget(data),
                      path.lowercased().hasPrefix("c:\\") else { continue }
                executable = root.appendingPathComponent(String(path.dropFirst(3)).replacingOccurrences(of: "\\", with: "/"))
                    .standardizedFileURL.resolvingSymlinksInPath()
            }
            guard executable.path.hasPrefix(root.path + "/"), executable.pathExtension.lowercased() == "exe",
                  !isHelper(executable.deletingPathExtension().lastPathComponent),
                  let handle = try? FileHandle(forReadingFrom: executable) else { continue }
            let header = try? handle.read(upToCount: 2)
            try? handle.close()
            guard header == Data([0x4d, 0x5a]) else { continue }
            let targetValues = try? executable.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let stamp = "\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(targetValues?.fileSize ?? 0):\(targetValues?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            results.append(.init(entry: url, executable: executable,
                name: WindowsGameLaunchRules.isEndfield(executable) ? "明日方舟：终末地" : url.deletingPathExtension().lastPathComponent,
                fingerprint: stamp))
        }
        return results.sorted { $0.entry.path < $1.entry.path }
    }

    static func added(after before: [InstalledProgramCandidate], current: [InstalledProgramCandidate]) -> [InstalledProgramCandidate] {
        let old = Dictionary(before.map { ($0.id, $0.fingerprint) }, uniquingKeysWith: { first, _ in first })
        let changed = current.filter { old[$0.id] != $0.fingerprint }
        let shortcuts = changed.filter(\.isShortcut)
        // Desktop and Start Menu frequently contain identical links. Keep one
        // per target, but do not merge links with different names/launch intents.
        var seen = Set<String>()
        let preferred = shortcuts.isEmpty ? changed : shortcuts + changed.filter {
            !$0.isShortcut && WindowsGameLaunchRules.isEndfield($0.executable)
        }
        return preferred.filter {
            seen.insert($0.executable.path + "|" + $0.name.lowercased()).inserted
        }
    }

    private static func isHelper(_ name: String) -> Bool {
        let value = name.lowercased()
        return ["unins", "uninstall", "setup", "installer", "crash", "helper", "redist", "update", "卸载"].contains { value.contains($0) }
    }

    /// Conservative MS-SHLLINK LinkInfo reader. Unsupported PIDL-only/network
    /// links are left for manual selection, rather than guessed or executed.
    /// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/6813269d-0cc8-4be2-933f-e96e8e3412dc
    static func shortcutTarget(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ count: Int = 4) -> Int? {
            guard offset >= 0, offset <= bytes.count - count else { return nil }
            return (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
        }
        guard bytes.count >= 76, number(0) == 76,
              Array(bytes[4..<20]) == [1, 20, 2, 0, 0, 0, 0, 0, 192, 0, 0, 0, 0, 0, 0, 70],
              let flags = number(20), flags & 2 != 0, flags & 0x100 == 0 else { return nil }
        var offset = 76
        if flags & 1 != 0 {
            guard let length = number(offset, 2) else { return nil }
            offset += 2 + length
        }
        guard let size = number(offset), size >= 28, offset <= bytes.count - size,
              let headerSize = number(offset + 4), headerSize >= 28, headerSize <= size,
              let infoFlags = number(offset + 8), infoFlags & 1 != 0 else { return nil }
        func string(at relative: Int?, unicode: Bool) -> String? {
            guard let relative, relative >= headerSize, relative < size else { return nil }
            let start = offset + relative
            var end = start
            let width = unicode ? 2 : 1
            while end + width <= offset + size {
                if bytes[end] == 0 && (!unicode || bytes[end + 1] == 0) {
                    return String(data: Data(bytes[start..<end]), encoding: unicode ? .utf16LittleEndian : .windowsCP1252)
                }
                end += width
            }
            return nil
        }
        let unicodeBase = headerSize >= 36 ? string(at: number(offset + 28), unicode: true) : nil
        guard let base = unicodeBase ?? string(at: number(offset + 16), unicode: false) else { return nil }
        let suffix = (headerSize >= 36 ? string(at: number(offset + 32), unicode: true) : nil)
            ?? string(at: number(offset + 24), unicode: false) ?? ""
        if suffix.isEmpty || base.lowercased().hasSuffix(suffix.lowercased()) { return base }
        return base + (base.hasSuffix("\\") ? "" : "\\") + suffix
    }
}
