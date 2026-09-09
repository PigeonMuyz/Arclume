import Foundation

/// Read-only recognition and conservative launch defaults for verified games.
/// Does not change the prefix, graphics backend, or in-game preferences.
nonisolated enum WindowsGameLaunchRules {
    static func isEndfield(_ executable: URL) -> Bool {
        GameAdaptationRules.rule(id: "endfield")?.recognizes(executable) == true
    }

    static func arguments(for executable: URL, userArguments: [String]) -> [String] {
        guard let rule = GameAdaptationRules.matching(executable) else { return userArguments }
        let defaults = rule.defaultArguments
        let supplied = Set(userArguments.map { $0.lowercased().split(separator: "=", maxSplits: 1).first.map(String.init) ?? "" })
        return defaults.filter {
            !supplied.contains(String($0[0].split(separator: "=", maxSplits: 1)[0]))
        }.flatMap { $0 } + userArguments
    }

    /// Probe the official default location before the bounded general scan,
    /// so large game data trees cannot exhaust its entry budget first.
    static func discover(in bottle: URL) -> [InstalledProgramCandidate] {
        let root = bottle.appendingPathComponent("drive_c").standardizedFileURL.resolvingSymlinksInPath()
        let defaults = GameAdaptationRules.all.filter { $0.kind == "game" }.map {
            $0.directory(in: bottle).appendingPathComponent($0.executable)
        }
        let scanned = InstalledProgramDiscovery.scan(bottle: bottle).map(\.executable)
        var seen = Set<String>()
        return (defaults + scanned).compactMap { executable in
            let target = executable.standardizedFileURL.resolvingSymlinksInPath()
            guard target.path.hasPrefix(root.path + "/"), let rule = GameAdaptationRules.matching(target), rule.kind == "game", rule.allows(target, in: bottle),
                  seen.insert(target.path).inserted else { return nil }
            let values = try? target.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return InstalledProgramCandidate(entry: target, executable: target, name: rule.name,
                fingerprint: "\(values?.fileSize ?? 0):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
    }
}
