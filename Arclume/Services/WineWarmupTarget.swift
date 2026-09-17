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

    static func decode(_ raw: String) -> Set<Self> {
        guard let values = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) else { return [] }
        return Set(values.compactMap(Self.init(rawValue:)))
    }

    static func encode(_ targets: Set<Self>) -> String {
        let values = allCases.filter { targets.contains($0) }.map(\.rawValue)
        return String(decoding: try! JSONEncoder().encode(values), as: UTF8.self)
    }
}
