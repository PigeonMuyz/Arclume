import Foundation

actor JX3GPUProfileStore {
    static let shared = JX3GPUProfileStore()

    nonisolated struct Snapshot: Sendable {
        let selected: JX3GPUProfile?
        let imported: [JX3GPUProfile]
        let pending: Bool
    }

    nonisolated private struct State: Codable {
        var schemaVersion = 1
        var original: Data
        var selected: JX3GPUProfile?
        var imported: [JX3GPUProfile]
        var pending: Bool
    }

    private func stateURL(for config: URL) -> URL {
        config.deletingLastPathComponent().appendingPathComponent("arclume-gpu-profile-state.json")
    }

    private func readState(for config: URL) throws -> State? {
        let url = stateURL(for: config)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try JX3GPUConfigDocument.readData(at: url, maximumBytes: 2_000_000)
            guard data.count < 2_000_000 else { throw JX3GPUProfileError.corruptState }
            let state = try JSONDecoder().decode(State.self, from: data)
            guard state.schemaVersion == 1, state.imported.count <= 20 else { throw JX3GPUProfileError.corruptState }
            _ = try JX3GPUConfigDocument(data: state.original)
            try state.selected?.validate()
            for profile in state.imported { try profile.validate() }
            return state
        } catch { throw JX3GPUProfileError.corruptState }
    }

    func snapshot(at config: URL) throws -> Snapshot {
        let state = try readState(for: config)
        return Snapshot(selected: state?.selected, imported: state?.imported ?? [], pending: state?.pending ?? false)
    }

    private func configData(at config: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: config.path) else { throw JX3GPUProfileError.missingConfig }
        let data = try JX3GPUConfigDocument.readData(at: config)
        _ = try JX3GPUConfigDocument(data: data)
        return data
    }

    func importAndApply(from source: URL, at config: URL) throws -> Snapshot {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let profile = try JX3GPUProfile.read(from: JX3GPUConfigDocument.readData(at: source))
        return try apply(profile, at: config, remember: true)
    }

    @discardableResult
    func apply(_ profile: JX3GPUProfile, at config: URL, remember: Bool = false) throws -> Snapshot {
        try profile.validate()
        let current = try configData(at: config)
        var state = try readState(for: config) ?? State(original: current, selected: nil, imported: [], pending: false)
        if state.selected == nil && !state.pending { state.original = current }
        if remember && !state.imported.contains(where: { $0.id == profile.id }) {
            guard state.imported.count < 20 else { throw JX3GPUProfileError.tooManyProfiles }
            state.imported.append(profile)
        }
        state.selected = profile
        try commit(&state, current: current, at: config)
        return try snapshot(at: config)
    }

    @discardableResult
    func restore(at config: URL) throws -> Snapshot {
        guard var state = try readState(for: config) else { return try snapshot(at: config) }
        guard state.selected != nil || state.pending else { return try snapshot(at: config) }
        let current = try configData(at: config)
        state.selected = nil
        try commit(&state, current: current, at: config)
        return try snapshot(at: config)
    }

    /// Called before launch. A pending restore is replayed, never replaced by an old spoof.
    func reapply(at config: URL) throws {
        guard var state = try readState(for: config), state.selected != nil || state.pending else { return }
        try commit(&state, current: configData(at: config), at: config)
    }

    private func commit(_ state: inout State, current: Data, at config: URL) throws {
        let original = try JX3GPUConfigDocument(data: state.original)
        let originalFields = original.values.filter {
            let parts = $0.key.split(separator: ".", maxSplits: 1).map(String.init)
            return parts.count == 2 && JX3GPUProfile.owns(parts[0], parts[1])
        }
        // Missing keys in the next profile must not retain values from the previous GPU.
        let fields = state.selected?.fields ?? originalFields
        let document = try JX3GPUConfigDocument(data: current)
        let removeEmptyDevice = state.selected == nil && !original.hasSection("device")
        var replacement = try document.replacingGPUFields(with: fields, removeEmptyDevice: removeEmptyDevice)
        // If nothing except our fields changed, restore the exact original bytes.
        if state.selected == nil {
            let originalWithoutGPU = try original.replacingGPUFields(with: [:])
            let currentWithoutGPU = try document.replacingGPUFields(with: [:], removeEmptyDevice: removeEmptyDevice)
            if originalWithoutGPU == currentWithoutGPU { replacement = state.original }
        }
        guard try JX3GPUConfigDocument.readData(at: config) == current else { throw JX3GPUProfileError.concurrentChange }
        state.pending = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Save recovery information before touching the game file; interrupted writes
        // can be completed by Retry/Restore or at the next launch.
        try encoder.encode(state).write(to: stateURL(for: config), options: .atomic)
        guard try JX3GPUConfigDocument.readData(at: config) == current else { throw JX3GPUProfileError.concurrentChange }
        if replacement != current { try replacement.write(to: config, options: .atomic) }
        state.pending = false
        try encoder.encode(state).write(to: stateURL(for: config), options: .atomic)
    }
}
