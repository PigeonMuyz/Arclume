import Foundation

nonisolated enum WineWarmupTarget: String, CaseIterable, Identifiable, Sendable {
    case steam, games

    var id: String { rawValue }
    var title: String {
        switch self {
        case .steam: "Steam / Windows 应用"
        case .games: "Games / 剑网3"
        }
    }

    @MainActor var prefix: URL {
        switch self {
        case .steam: BundledWineRuntime.standardSteamPrefixURL
        case .games: BundledWineRuntime.prefixURL
        }
    }

    /// Count real, distinct managed containers rather than legacy target aliases.
    @MainActor static var available: [Self] {
        guard !ArclumeTestEnvironment.isTesting else { return [] }
        let prefixes = Dictionary(uniqueKeysWithValues: allCases.compactMap { target in
            BundledWineRuntime.isValidPrefix(at: target.prefix) ? (target, target.prefix) : nil
        })
        return uniqueTargets(prefixes: prefixes)
    }

    static func uniqueTargets(prefixes: [Self: URL]) -> [Self] {
        var paths = Set<String>()
        return allCases.filter { target in
            guard let prefix = prefixes[target] else { return false }
            return paths.insert(prefix.resolvingSymlinksInPath().standardizedFileURL.path).inserted
        }
    }

    static func effectiveSelection(selected: Set<Self>, available: [Self]) -> Set<Self> {
        if available.count == 1 { return Set(available) }
        return selected.intersection(available)
    }

    static func decode(_ raw: String) -> Set<Self> {
        guard let values = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) else { return [] }
        return Set(values.compactMap(Self.init(rawValue:)))
    }

    static func encode(_ targets: Set<Self>) -> String {
        let values = allCases.filter { targets.contains($0) }.map(\.rawValue)
        return String(decoding: try! JSONEncoder().encode(values), as: UTF8.self)
    }
}
