import Foundation

/// Presentation-only order. Filtered-out games retain their places and newcomers append.
nonisolated enum LauncherLibraryOrder {
    static func decode(_ value: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? []
    }

    static func encode(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func reconciled(saved: [String], available: [String]) -> [String] {
        let valid = Set(available)
        var seen = Set<String>()
        return (saved + available).filter { valid.contains($0) && seen.insert($0).inserted }
    }

    static func moving(_ source: String, before target: String, in ids: [String]) -> [String] {
        moving(source, relativeTo: target, after: false, in: ids)
    }

    static func moving(_ source: String, relativeTo target: String, after: Bool, in ids: [String]) -> [String] {
        guard source != target, ids.contains(source), ids.contains(target) else { return ids }
        var result = ids.filter { $0 != source }
        guard let index = result.firstIndex(of: target) else { return ids }
        result.insert(source, at: index + (after ? 1 : 0))
        return result
    }
}
