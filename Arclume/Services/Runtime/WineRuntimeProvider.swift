import Foundation

/// Delivery choice is separate from the legacy bundledWine/CrossOver launch enum.
nonisolated enum WineRuntimeProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case arclume, nefinita

    static let defaultsKey = "wine-runtime-provider"
    var id: String { rawValue }
    var title: String { self == .arclume ? "Arclume Runtime" : "Nefinita" }
    var deliveryTitle: String { self == .arclume ? "下载编译好的 Arclume Runtime" : "在本机编译 Nefinita" }

    static func selected(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .arclume
    }
    static var selected: Self { selected(in: UserDefaults(suiteName: suiteName) ?? .standard) }
    static var managedPrefixes: [URL] { [selected.prefixURL()] }

    func prefixURL(root: URL? = nil) -> URL {
        // The provider selects an engine, never a different game/data directory.
        (root ?? ARCLUME_SUPPORT_FOLDER_URL).appendingPathComponent("ALBottles", isDirectory: true)
    }

    static func provider(for prefix: URL, root: URL? = nil, defaults: UserDefaults? = nil) -> Self? {
        let provider = defaults.map { selected(in: $0) } ?? selected
        guard provider.prefixURL(root: root).resolvingSymlinksInPath().standardizedFileURL == prefix.resolvingSymlinksInPath().standardizedFileURL else { return nil }
        return provider
    }

    static func runtimeURL(for prefix: URL) -> URL {
        provider(for: prefix) == .nefinita ? NefinitaRuntime.installationURL : BundledWineRuntime.installationURL
    }

    static func ensureRuntime(for prefix: URL) throws -> URL {
        guard let provider = provider(for: prefix) else { throw BundledWineRuntimeError.invalidPrefix }
        if provider == .arclume { return try BundledWineRuntime.ensureInstalled() }
        guard NefinitaRuntime.isReady() else { throw NefinitaBuildError.notBuilt }
        return NefinitaRuntime.installationURL
    }

    /// Invalidate queued launches and keep new launches blocked until the selection
    /// is persisted. Only the engine preference changes; no wineboot or prefix writes.
    static func commitSelection(_ provider: Self, in defaults: UserDefaults,
                                runtimeReady: () throws -> Bool,
                                processesIdle: () throws -> Bool) throws {
        guard selected(in: defaults) != provider else { return }
        try ArclumeWineStopService.withRuntimeMaintenance {
            guard try runtimeReady() else { throw NefinitaBuildError.notBuilt }
            guard try processesIdle() else { throw ResourceDownloadError.busyRuntime }
            defaults.set(provider.rawValue, forKey: defaultsKey)
        }
    }
}

nonisolated enum NefinitaBuildError: LocalizedError {
    case sourceUnavailable, invalidRecipe, missingTools([String]), failed(String), invalidRuntime, notBuilt
    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: "暂时无法获取 Nefinita 构建材料。请稍后重试；若持续失败，请联系维护者确认构建材料已公开发布。"
        case .invalidRecipe: "源码或构建脚本与当前支持的 Nefinita 版本不一致，未执行。"
        case .missingTools(let names): "尚缺构建环境：\(names.joined(separator: "、"))。安装后可重新检查。"
        case .failed(let phase): "\(phase)失败。请查看构建日志，原运行时与容器未改变。"
        case .invalidRuntime: "Nefinita 构建产物不完整或版本不匹配，未启用。"
        case .notBuilt: "请先在“运行环境”中完成 Nefinita 本机编译。"
        }
    }
}

nonisolated struct NefinitaBuildRecipe: Decodable, Sendable {
    let schemaVersion: Int
    let provider: String
    let revision: String
    let version: String
    let files: [String: String]

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "nefinita-build-recipe", withExtension: "json") else {
            throw NefinitaBuildError.invalidRecipe
        }
        let recipe = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard recipe.schemaVersion == 1, recipe.provider == "Nefinita", recipe.version == NefinitaRuntime.version,
              recipe.revision == NefinitaRuntime.revision, recipe.files.count == 13,
              recipe.files.allSatisfy({ DownloadableResourceCatalog.safePath($0.key) && $0.value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }) else {
            throw NefinitaBuildError.invalidRecipe
        }
        return recipe
    }

    func validateSource(_ directory: URL) throws -> URL {
        let fm = FileManager.default
        let root = fm.fileExists(atPath: directory.appendingPathComponent("runtime.env").path)
            ? directory : directory.appendingPathComponent("runtime", isDirectory: true)
        for (path, expectedHash) in files {
            let file = root.appendingPathComponent(path)
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
                  (try? DownloadedResourceFiles.hash(file)) == expectedHash else { throw NefinitaBuildError.invalidRecipe }
        }
        return root
    }
}
