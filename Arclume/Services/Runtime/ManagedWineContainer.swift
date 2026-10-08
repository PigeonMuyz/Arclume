import Foundation

/// A container owns a prefix; a runtime is only the engine used to prepare it.
/// ALBottles remains a virtual, backwards-compatible record until multi-container
/// game launching and migration are enabled.
nonisolated struct ManagedWineContainer: Codable, Identifiable, Equatable, Sendable {
    static let defaultID = "albottles"
    let id: String
    var name: String
    let provider: WineRuntimeProvider

    var isDefault: Bool { id == Self.defaultID }
    func prefixURL(root: URL) -> URL {
        isDefault ? root.appendingPathComponent("ALBottles", isDirectory: true)
            : root.appendingPathComponent("Containers", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }
}

nonisolated enum ManagedContainerError: LocalizedError {
    case invalidCatalog, invalidName, duplicateName, unknownContainer, runtimeUnavailable, assignmentDisabled, initializationTimedOut
    var errorDescription: String? {
        switch self {
        case .invalidCatalog: "无法读取容器列表，原有数据未改变。"
        case .invalidName: "请输入 1–40 个字符的容器名称。"
        case .duplicateName: "已有同名容器，请使用其他名称。"
        case .unknownContainer: "找不到此容器，原有数据未改变。"
        case .runtimeUnavailable: "请先在运行环境中准备所选运行时及所需图形组件。"
        case .assignmentDisabled: "游戏指定容器暂未开放，迁移适配完成后可用。"
        case .initializationTimedOut: "容器初始化超时，已停止本次初始化。请结束容器运行后重试。"
        }
    }
}

// UserDefaults is thread-safe; the additional shared lock serializes the
// read-modify-write catalog operations across repository instances.
nonisolated struct ManagedWineContainerRepository: @unchecked Sendable {
    static let defaultsKey = "managed-wine-containers.v1"
    private static let lock = NSLock()
    let defaults: UserDefaults
    let root: URL

    private struct Catalog: Codable {
        let schemaVersion: Int
        var containers: [ManagedWineContainer]
    }

    func containers() throws -> [ManagedWineContainer] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return [defaultContainer] + (try read()).containers
    }

    private var defaultContainer: ManagedWineContainer {
        .init(id: ManagedWineContainer.defaultID, name: "默认容器", provider: .selected(in: defaults))
    }

    @discardableResult
    func create(name: String, provider: WineRuntimeProvider) throws -> ManagedWineContainer {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var catalog = try read()
        let name = try normalizedName(name, existing: [defaultContainer] + catalog.containers)
        let item = ManagedWineContainer(id: UUID().uuidString.lowercased(), name: name, provider: provider)
        catalog.containers.append(item)
        try save(catalog)
        // Creating a record does not create, copy or initialize a Wine prefix.
        return item
    }

    func rename(id: String, name: String) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var catalog = try read()
        guard let index = catalog.containers.firstIndex(where: { $0.id == id }) else {
            throw ManagedContainerError.unknownContainer
        }
        catalog.containers[index].name = try normalizedName(name,
            existing: [defaultContainer] + catalog.containers.filter { $0.id != id })
        try save(catalog)
    }

    func container(id: String) throws -> ManagedWineContainer {
        guard let item = try containers().first(where: { $0.id == id }) else {
            throw ManagedContainerError.unknownContainer
        }
        return item
    }

    /// Only new managed containers can be initialized from this surface. Never
    /// reinterpret an arbitrary folder or touch an existing invalid prefix.
    func initializationTarget(id: String) throws -> ManagedWineContainer {
        let item = try container(id: id)
        guard !item.isDefault else { throw ManagedContainerError.unknownContainer }
        let target = item.prefixURL(root: root)
        // Resolving a non-existent leaf does not reliably expose a symlink in
        // its ancestors. Inspect each managed boundary explicitly as well.
        for boundary in [root, root.appendingPathComponent("Containers"), target] {
            if (try? FileManager.default.attributesOfItem(atPath: boundary.path)[.type]) as? FileAttributeType == .typeSymbolicLink {
                throw ManagedContainerError.unknownContainer
            }
        }
        guard target.resolvingSymlinksInPath().standardizedFileURL.path == target.standardizedFileURL.path,
              root.resolvingSymlinksInPath().standardizedFileURL.path == root.standardizedFileURL.path else {
            throw ManagedContainerError.unknownContainer
        }
        return item
    }

    private func read() throws -> Catalog {
        guard defaults.object(forKey: Self.defaultsKey) != nil else {
            return Catalog(schemaVersion: 1, containers: [])
        }
        guard let data = defaults.data(forKey: Self.defaultsKey), data.count < 1_048_576,
              let value = try? JSONDecoder().decode(Catalog.self, from: data), value.schemaVersion == 1,
              Set(value.containers.map(\.id)).count == value.containers.count,
              Set(value.containers.map { $0.name.lowercased() }).count == value.containers.count,
              value.containers.allSatisfy({ UUID(uuidString: $0.id) != nil && $0.id == $0.id.lowercased()
                  && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 40 }) else {
            throw ManagedContainerError.invalidCatalog
        }
        return value
    }

    private func save(_ catalog: Catalog) throws {
        let data = try JSONEncoder().encode(catalog)
        guard data.count < 1_048_576 else { throw ManagedContainerError.invalidCatalog }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func normalizedName(_ raw: String, existing: [ManagedWineContainer]) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ManagedContainerError.invalidName
        }
        guard !existing.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ManagedContainerError.duplicateName
        }
        return name
    }
}

nonisolated enum GameContainerAssignmentPolicy {
    static let isEnabled = false

    static func containerID(for game: Game, in containers: [ManagedWineContainer], root: URL) -> String? {
        guard !game.isNative, let prefix = game.installedBottleURL else { return nil }
        return containers.first { $0.prefixURL(root: root).resolvingSymlinksInPath().standardizedFileURL.path
            == prefix.resolvingSymlinksInPath().standardizedFileURL.path }?.id
    }

    /// Keep the service gated too: a disabled picker must not be the only thing
    /// protecting executable paths, stored ownership and game data from changes.
    static func validateAssignment() throws {
        throw ManagedContainerError.assignmentDisabled
    }
}
