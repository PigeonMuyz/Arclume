import Foundation

nonisolated enum LauncherIconSource {
    /// Search only the known installation, and bound traversal for large game depots.
    static func resolve(explicit: URL?, directory: URL?, native: Bool, names: [String]) -> URL? {
        let fm = FileManager.default
        if let explicit, fm.fileExists(atPath: explicit.path),
           native ? NativeApplicationBundleDetector.application(at: explicit) != nil : explicit.pathExtension.lowercased() == "exe" {
            return explicit
        }
        guard let directory else { return nil }
        if native, NativeApplicationBundleDetector.application(at: directory) != nil { return directory }
        guard let walker = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        let expected = Set(names.map { $0.lowercased() })
        var candidates: [URL] = []
        var visited = 0
        for case let url as URL in walker {
            visited += 1
            if visited > 2000 || Task.isCancelled { break }
            if walker.level > 4 { walker.skipDescendants(); continue }
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                walker.skipDescendants(); continue
            }
            if native {
                guard url.pathExtension.lowercased() == "app", NativeApplicationBundleDetector.application(at: url) != nil else { continue }
            } else {
                guard url.pathExtension.lowercased() == "exe", expected.contains(url.lastPathComponent.lowercased()) else { continue }
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                guard !["unins", "setup", "install", "crash", "redist", "helper"].contains(where: { name.contains($0) }) else { continue }
            }
            candidates.append(url)
        }
        return candidates.sorted {
            let leftKnown = expected.contains($0.lastPathComponent.lowercased())
            let rightKnown = expected.contains($1.lastPathComponent.lowercased())
            if leftKnown != rightKnown { return leftKnown }
            if $0.pathComponents.count != $1.pathComponents.count { return $0.pathComponents.count < $1.pathComponents.count }
            return $0.path < $1.path
        }.first
    }

    static func nativeIconFile(at bundle: URL) -> URL? {
        // Extensionless Steam macOS bundles otherwise appear as generic folders in NSWorkspace.
        let roots = [bundle.appendingPathComponent("Contents"), bundle]
        for root in roots {
            guard let data = try? Data(contentsOf: root.appendingPathComponent("Info.plist")),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let name = plist["CFBundleIconFile"] as? String, !name.isEmpty else { continue }
            let filename = (name as NSString).pathExtension.isEmpty ? name + ".icns" : name
            for resources in [root.appendingPathComponent("Resources"), root] {
                let file = resources.appendingPathComponent(filename).standardizedFileURL
                guard file.path.hasPrefix(resources.standardizedFileURL.path + "/") else { continue }
                if FileManager.default.fileExists(atPath: file.path) { return file }
            }
        }
        return nil
    }
}
