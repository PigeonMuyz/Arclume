import Combine
import CryptoKit
import Foundation

nonisolated enum ResourceDownloadError: LocalizedError {
    case unavailable, invalidCatalog, invalidDownload, busyRuntime, busyDownload
    var errorDescription: String? {
        switch self {
        case .unavailable: "此版本尚未配置组件下载服务，请联系维护者。"
        case .invalidCatalog: "组件清单无效，请重新安装 Arclume。"
        case .invalidDownload: "组件下载或校验失败，请检查网络后重试。"
        case .busyRuntime: "请先结束正在运行的 Windows 程序，再安装运行环境。"
        case .busyDownload: "正在下载组件，请稍候。"
        }
    }
}

/// URL-free pinned catalog; alternate engines must retain explicit ABI metadata.
nonisolated struct DownloadableResourceCatalog: Codable, Sendable {
    struct Component: Codable, Sendable {
        let type: String
        let name: String
        let id: String
        let version: String
        let fileName: String
        let sha256: String
        let byteCount: Int64
        let unpack: Bool
        var displayName: String {
            switch id {
            case "io.arclume.runtime.wine": "Arclume Wine"
            case "d3dmetal3": "D3DMetal 3"
            case "d3dmetal4": "D3DMetal 4"
            case "dxmt": "DXMT"
            case "gstreamer": "GStreamer"
            case "fonts": "Windows 字体"
            case "nvngx-jx3": "剑网3图形组件"
            case "compatibility-libs": "兼容组件"
            default: name
            }
        }
        var objectKey: String { "components/\(type)/\(name)/\(id)/\(version)/\(sha256)/\(fileName)" }
    }
    struct RuntimeOption: Codable, Sendable {
        struct Strategy: Codable, Sendable {
            enum Delivery: String, Codable, Sendable { case precompiled, localBuild }
            let delivery: Delivery
            let componentID: String?
            let recipeID: String?
        }
        let id: String
        let provider: String
        let strategies: [Strategy]
    }
    enum Purpose: String, Codable, Sendable { case runtime, steam, jx3 }
    /// Requirements belong to an exact engine version, never to all engines globally.
    struct Requirements: Codable, Sendable {
        let runtimeID: String
        let runtimeVersion: String
        let componentIDs: [String]
        let features: [String: [String]]
        let graphicsComponentIDs: [String]?
        let optionalComponentIDs: [String]?
    }
    let schemaVersion: Int
    let components: [Component]
    let runtimes: [ArclumeRuntimeManifest]
    let runtimeOptions: [RuntimeOption]
    let requirements: [Requirements]?

    func supportedIDs(for runtime: ArclumeRuntimeManifest) throws -> Set<String> {
        let core = try requiredIDs(for: runtime, purpose: .runtime)
        guard let requirement = requirements?.first(where: {
            $0.runtimeID == runtime.id && $0.runtimeVersion == runtime.version
        }) else { throw ResourceDownloadError.invalidCatalog }
        return core.union(requirement.features.values.flatMap { $0 })
            .union(requirement.graphicsComponentIDs ?? []).union(requirement.optionalComponentIDs ?? [])
    }

    func selectedIDs(_ selected: Set<String>, for runtime: ArclumeRuntimeManifest) throws -> Set<String> {
        let allowed = try supportedIDs(for: runtime)
        guard !selected.isEmpty, selected.isSubset(of: allowed) else { throw ResourceDownloadError.invalidCatalog }
        // Selecting one third-party component must not implicitly select Wine or every other component.
        return selected.contains(runtime.id) ? try selected.union(requiredIDs(for: runtime, purpose: .runtime)) : selected
    }

    func requiredIDs(for runtime: ArclumeRuntimeManifest, purpose: Purpose, graphicsBackend: String = "d3dmetal4") throws -> Set<String> {
        try validateCompatibility(with: runtime)
        guard let requirement = requirements?.first(where: {
            $0.runtimeID == runtime.id && $0.runtimeVersion == runtime.version
        }), let archive = components.first(where: {
            $0.fileName == runtime.archive.name && $0.sha256 == runtime.archive.sha256
        }) else { throw ResourceDownloadError.invalidCatalog }
        var ids = Set(requirement.componentIDs + (requirement.features[purpose.rawValue] ?? []) + [archive.id])
        if purpose != .runtime, let graphics = requirement.graphicsComponentIDs, !graphics.isEmpty {
            guard graphics.contains(graphicsBackend) else { throw ResourceDownloadError.invalidCatalog }
            ids.insert(graphicsBackend)
        }
        return ids
    }

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "downloadable-resources", withExtension: "json") else { throw ResourceDownloadError.invalidCatalog }
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try catalog.validate()
        try catalog.validateCompatibility(with: ArclumeRuntimeManifest.load(bundle: bundle))
        return catalog
    }
    /// Never let a catalog redirect an older App to a different engine, ABI,
    /// architecture or archive merely because that version is newer.
    func validateCompatibility(with expected: ArclumeRuntimeManifest) throws {
        guard runtimes.contains(expected) else { throw ResourceDownloadError.invalidCatalog }
    }
    func validate() throws {
        guard schemaVersion == 1, !components.isEmpty, !runtimes.isEmpty,
              Set(components.map(\.id)).count == components.count,
              Set(components.map(\.fileName)).count == components.count else { throw ResourceDownloadError.invalidCatalog }
        for item in components {
            guard [item.type, item.name, item.id, item.version, item.fileName].allSatisfy({ Self.safePath($0) && !$0.contains("/") }),
                  item.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  item.byteCount > 0, item.byteCount < 4_294_967_296 else { throw ResourceDownloadError.invalidCatalog }
        }
        for runtime in runtimes {
            try runtime.validate()
            guard components.contains(where: { $0.fileName == runtime.archive.name && $0.sha256 == runtime.archive.sha256 && !$0.unpack }) else { throw ResourceDownloadError.invalidCatalog }
        }
        guard !runtimeOptions.isEmpty, Set(runtimeOptions.map(\.id)).count == runtimeOptions.count else { throw ResourceDownloadError.invalidCatalog }
        for option in runtimeOptions {
            guard !option.provider.isEmpty, !option.strategies.isEmpty,
                  Self.safePath(option.id), !option.id.contains("/") else { throw ResourceDownloadError.invalidCatalog }
            for strategy in option.strategies {
                switch strategy.delivery {
                case .precompiled:
                    guard strategy.recipeID == nil, components.contains(where: { $0.id == strategy.componentID && $0.type == "runtime" }) else { throw ResourceDownloadError.invalidCatalog }
                case .localBuild:
                    // Reserved contract only. No build recipe is executed by this version.
                    guard strategy.componentID == nil, let recipe = strategy.recipeID, Self.safePath(recipe) else { throw ResourceDownloadError.invalidCatalog }
                }
            }
        }
        if let requirements {
            let ids = Set(components.map(\.id))
            var versions = Set<String>()
            for requirement in requirements {
                guard versions.insert("\(requirement.runtimeID)@\(requirement.runtimeVersion)").inserted,
                      runtimes.contains(where: { $0.id == requirement.runtimeID && $0.version == requirement.runtimeVersion }),
                      Set(requirement.componentIDs + requirement.features.values.flatMap { $0 } + (requirement.graphicsComponentIDs ?? []) + (requirement.optionalComponentIDs ?? [])).isSubset(of: ids),
                      requirement.features.keys.allSatisfy({ Purpose(rawValue: $0) != nil }) else {
                    throw ResourceDownloadError.invalidCatalog
                }
            }
        }
    }
    static func safePath(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("\\") && !name.hasPrefix("/") &&
        name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func downloadURL(base: String?, component: Component) throws -> URL {
        guard let base, let url = URL(string: base), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !base.contains("$(") else { throw ResourceDownloadError.unavailable }
        return url.appendingPathComponent(component.objectKey)
    }
}

nonisolated enum DownloadedResourceFiles {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arclume/DownloadedResources", isDirectory: true)
    }
    static func directory(_ item: DownloadableResourceCatalog.Component, root: URL = root) -> URL {
        root.appendingPathComponent(item.sha256, isDirectory: true)
    }
    static func ready(_ item: DownloadableResourceCatalog.Component, root: URL = root) -> Bool {
        let directory = directory(item, root: root)
        let marker = try? String(contentsOf: directory.appendingPathComponent(".complete"), encoding: .utf8)
        return marker == item.sha256 && FileManager.default.fileExists(atPath:
            directory.appendingPathComponent(item.unpack ? "Libs" : item.fileName).path)
    }
    static func resourceURL(named name: String) -> URL? {
        guard DownloadableResourceCatalog.safePath(name), let catalog = try? DownloadableResourceCatalog.load() else { return nil }
        for item in catalog.components where ready(item) {
            let candidate = directory(item).appendingPathComponent(item.unpack ? "Libs/\(name)" : name)
            if (item.unpack || name == item.fileName), FileManager.default.fileExists(atPath: candidate.path) {
                guard candidate.resolvingSymlinksInPath().path.hasPrefix(directory(item).resolvingSymlinksInPath().path + "/") else { return nil }
                return candidate
            }
        }
        return nil
    }
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func install(_ archive: URL, item: DownloadableResourceCatalog.Component, root: URL = root) throws {
        let fm = FileManager.default
        let bytes = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard bytes.map(Int64.init) == item.byteCount, try hash(archive) == item.sha256 else { throw ResourceDownloadError.invalidDownload }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".download-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        if item.unpack {
            try SafeArchiveExtractor.extract(archive, to: staging)
            guard fm.fileExists(atPath: staging.appendingPathComponent("Libs").path) else { throw ResourceDownloadError.invalidDownload }
        } else {
            try fm.copyItem(at: archive, to: staging.appendingPathComponent(item.fileName))
        }
        try item.sha256.write(to: staging.appendingPathComponent(".complete"), atomically: true, encoding: .utf8)
        let destination = directory(item, root: root)
        if ready(item, root: root) { return }
        if fm.fileExists(atPath: destination.path) {
            try fm.moveItem(at: destination, to: root.appendingPathComponent(".incomplete-\(UUID().uuidString)"))
        }
        try fm.moveItem(at: staging, to: destination)
    }
}

@MainActor
final class DownloadableResourceStore: ObservableObject {
    static let shared = DownloadableResourceStore()
    @Published var selectedProvider = WineRuntimeProvider.selected
    @Published private(set) var activeProvider = WineRuntimeProvider.selected
    @Published private(set) var buildLog: URL?
    @Published private(set) var buildEnvironment: NefinitaBuildService.EnvironmentReport?
    @Published private(set) var isBusy = false
    @Published private(set) var isSwitchingRuntime = false
    @Published private(set) var progress: Double?
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    @Published private(set) var transferDetail: String?
    @Published private(set) var requestedIDs: Set<String> = []
    @Published private var revision = 0
    private let catalog = try? DownloadableResourceCatalog.load()
    private let expectedRuntime = try? ArclumeRuntimeManifest.load()
    private var downloadGeneration = UUID()
    private var acceptingTransferProgress = false
    private let nefinitaReady: () -> Bool
    init(nefinitaReady: @escaping () -> Bool = { NefinitaRuntime.isReady() }) {
        self.nefinitaReady = nefinitaReady
    }
    #if DEBUG
    @Published var demonstrationStatus: ResourceSetupStatus?
    var demonstrationFailsOnce = false
    #endif
    var status: ResourceSetupStatus { status(for: .runtime) }
    var components: [DownloadableResourceCatalog.Component] {
        guard let catalog, let expectedRuntime, let ids = try? catalog.supportedIDs(for: expectedRuntime) else { return [] }
        return catalog.components.filter {
            selectedProvider == .nefinita ? Self.nefinitaComponentIDs.contains($0.id) : ids.contains($0.id)
        }
    }
    private static let nefinitaComponentIDs: Set<String> = ["fonts", "d3dmetal3", "d3dmetal4", "nvngx-jx3"]
    var preparationTitle: String { selectedProvider == .nefinita && !nefinitaReady() ? "编译 Nefinita" : status.actionTitle }
    func checkBuildEnvironment() async { buildEnvironment = await NefinitaBuildService.inspectEnvironment() }

    func activateSelection() async throws {
        guard !isSwitchingRuntime else { throw ResourceDownloadError.busyRuntime }
        guard status.isReady else { throw NefinitaBuildError.notBuilt }
        guard selectedProvider != activeProvider else { return }
        let provider = selectedProvider
        isSwitchingRuntime = true
        defer { isSwitchingRuntime = false }
        try await Task.detached(priority: .userInitiated) {
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let root = BundledWineRuntime.installationURL.deletingLastPathComponent().resolvingSymlinksInPath().path
            try WineRuntimeProvider.commitSelection(provider, in: defaults, runtimeReady: {
                provider == .nefinita ? NefinitaRuntime.isReady() : BundledWineRuntime.isCurrentRuntime()
            }, processesIdle: {
                try ArclumeWineStopService.snapshot(root: root).isEmpty
            })
        }.value
        activeProvider = provider
    }
    func componentReady(_ item: DownloadableResourceCatalog.Component) -> Bool {
        #if DEBUG
        if let demonstrationStatus {
            if item.type == "runtime" { return demonstrationStatus.runtime == .ready }
            return demonstrationStatus.isReady
        }
        #endif
        if item.type == "runtime", item.id == expectedRuntime?.id,
           item.version == expectedRuntime?.version { return BundledWineRuntime.isCurrentRuntime() }
        return DownloadedResourceFiles.ready(item)
    }
    func requiredIDs(for purpose: DownloadableResourceCatalog.Purpose) -> Set<String> {
        if selectedProvider == .nefinita {
            return purpose == .runtime ? [] : ["fonts", OnlineGameMode.defaultGraphicsBackend]
        }
        guard let catalog, let expectedRuntime else { return [] }
        return (try? catalog.requiredIDs(for: expectedRuntime, purpose: purpose,
            graphicsBackend: OnlineGameMode.defaultGraphicsBackend)) ?? []
    }
    func confirmationMessage(purpose: DownloadableResourceCatalog.Purpose = .runtime, componentIDs: Set<String>? = nil) -> String {
        if selectedProvider == .nefinita && componentIDs == nil && !nefinitaReady() {
            return "将在本机下载源码和依赖并编译 Nefinita，可能需要较长时间，请保持电源连接。构建完成后可切换运行时，继续使用同一个 ALBottles 容器中的游戏和数据。切换前请结束容器中的 Windows 程序。"
        }
        let selected = componentIDs ?? requiredIDs(for: purpose)
        let ids = expectedRuntime.flatMap { runtime in try? catalog?.selectedIDs(selected, for: runtime) } ?? selected
        let pending = components.filter { ids.contains($0.id) && !componentReady($0) }
        let bytes = pending.filter { !DownloadedResourceFiles.ready($0) }.reduce(Int64(0)) { $0 + $1.byteCount }
        let names = pending.map(\.displayName).joined(separator: "、")
        return "\(names.isEmpty ? "准备所选组件" : names)\n预计下载 \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))。支持时启用分段加速，最多 3 路并发。已完成的组件不会重复下载。"
    }
    func status(for purpose: DownloadableResourceCatalog.Purpose) -> ResourceSetupStatus {
        #if DEBUG
        if let demonstrationStatus { return demonstrationStatus }
        #endif
        if selectedProvider == .nefinita {
            let ids = requiredIDs(for: purpose)
            let items = components.filter { ids.contains($0.id) }
            let missing = items.filter { !componentReady($0) }
            return ResourceSetupStatus(runtime: nefinitaReady() ? .ready : .missing,
                targetVersion: NefinitaRuntime.version, missingComponents: missing.map(\.displayName),
                componentCount: items.count, downloadBytes: missing.reduce(0) { $0 + $1.byteCount },
                catalogAvailable: catalog != nil && ids.isSubset(of: Set(items.map(\.id))),
                noticeID: "nefinita-\(NefinitaRuntime.revision)-\(purpose.rawValue)")
        }
        let version = (try? ArclumeRuntimeManifest.load().version) ?? "未知版本"
        let installed = BundledWineRuntime.installedRuntimeVersion(at: BundledWineRuntime.installationURL)
        let runtime: ResourceSetupStatus.Runtime
        if BundledWineRuntime.isCurrentRuntime() { runtime = .ready }
        else if BundledWineRuntime.isValidRuntime() { runtime = .update(installed: installed) }
        else if FileManager.default.fileExists(atPath: BundledWineRuntime.installationURL.path) { runtime = .repair }
        else if BundledWineRuntime.hasMigratableLegacyInstallation() { runtime = .update(installed: BundledWineRuntime.pendingLegacyRuntimeVersion()) }
        else { runtime = .missing }
        let ids = try? catalog?.requiredIDs(for: ArclumeRuntimeManifest.load(), purpose: purpose,
            graphicsBackend: OnlineGameMode.defaultGraphicsBackend)
        let components = catalog?.components.filter { $0.type != "runtime" && (ids?.contains($0.id) ?? false) } ?? []
        let missing = components.filter { !DownloadedResourceFiles.ready($0) }
        let pending = catalog?.components.filter { (ids?.contains($0.id) ?? false) && !componentReady($0) && !DownloadedResourceFiles.ready($0) } ?? []
        return ResourceSetupStatus(runtime: runtime, targetVersion: version,
            missingComponents: missing.map(\.displayName), componentCount: components.count,
            downloadBytes: pending.reduce(0) { $0 + $1.byteCount }, catalogAvailable: catalog != nil && ids != nil,
            noticeID: catalog?.components.filter { ids?.contains($0.id) ?? false }.map { "\($0.id):\($0.sha256)" }.sorted().joined(separator: "|") ?? "catalog-unavailable-v1")
    }
    var isReady: Bool { status.isReady }
    func refresh() { revision += 1 }
    /// Explicit setup/settings actions only; launch and resource lookup stay offline.
    func download(purpose: DownloadableResourceCatalog.Purpose = .runtime, componentIDs: Set<String>? = nil) async throws {
        guard !isBusy, !isSwitchingRuntime else { throw ResourceDownloadError.busyDownload }
        isBusy = true; error = nil; progress = 0; transferDetail = nil
        let generation = UUID()
        downloadGeneration = generation
        acceptingTransferProgress = true
        defer { isBusy = false; requestedIDs = []; acceptingTransferProgress = false; revision += 1 }
        do {
            #if DEBUG
            if let demonstrationStatus {
                for (value, label) in [(0.2, "正在下载运行环境及组件…"), (0.65, "正在校验组件…"), (0.9, "正在升级运行时…")] {
                    progress = value; message = label
                    try await Task.sleep(for: .milliseconds(650))
                }
                if demonstrationFailsOnce {
                    demonstrationFailsOnce = false
                    throw ResourceDownloadError.invalidDownload
                }
                self.demonstrationStatus = ResourceSetupStatus(runtime: .ready, targetVersion: demonstrationStatus.targetVersion,
                    missingComponents: [], componentCount: demonstrationStatus.componentCount, downloadBytes: 0,
                    catalogAvailable: true, noticeID: demonstrationStatus.noticeID)
                progress = 1; message = "运行环境及组件已就绪"
                return
            }
            #endif
            guard !ArclumeTestEnvironment.isTesting else { throw ResourceDownloadError.unavailable }
            let provider = selectedProvider
            if provider == .nefinita && componentIDs == nil && !NefinitaRuntime.isReady() {
                message = "检查 Nefinita 构建环境…"
                try await NefinitaBuildService().build { value, label, log in
                    Task { @MainActor [weak self] in
                        guard let self, self.isBusy, self.downloadGeneration == generation else { return }
                        self.progress = value; self.message = label; self.buildLog = log
                    }
                }
            }
            let catalog = try DownloadableResourceCatalog.load()
            let expected = try ArclumeRuntimeManifest.load()
            let selected = componentIDs ?? requiredIDs(for: purpose)
            let ids: Set<String>
            if provider == .nefinita {
                guard selected.isSubset(of: Self.nefinitaComponentIDs) else { throw ResourceDownloadError.invalidCatalog }
                ids = selected
            } else { ids = try catalog.selectedIDs(selected, for: expected) }
            requestedIDs = ids
            let pending = catalog.components.filter { ids.contains($0.id) && !componentReady($0) && !DownloadedResourceFiles.ready($0) }
            message = "正在准备下载…"
            try await ComponentDownloadCoordinator().run(items: pending,
                baseURL: Bundle.main.object(forInfoDictionaryKey: "ArclumeResourceBaseURL") as? String) { snapshot in
                Task { @MainActor [weak self] in
                    guard let self, self.isBusy, self.acceptingTransferProgress, self.downloadGeneration == generation else { return }
                    self.progress = max(self.progress ?? 0, snapshot.totalBytes > 0 ? min(0.95, Double(snapshot.downloadedBytes) / Double(snapshot.totalBytes) * 0.95) : 0.95)
                    self.message = "下载并准备组件（\(snapshot.completedCount)/\(snapshot.totalCount)）"
                    self.transferDetail = "\(ByteCountFormatter.string(fromByteCount: snapshot.downloadedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: snapshot.totalBytes, countStyle: .file)) · \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.bytesPerSecond), countStyle: .file))/s"
                }
            }
            acceptingTransferProgress = false
            try Task.checkCancellation()
            if provider == .arclume && ids.contains(expected.id) {
                message = "正在安装 Arclume Wine…"
                try await Task.detached(priority: .utility) {
                    if !BundledWineRuntime.isCurrentRuntime() {
                        try ArclumeWineStopService.withRuntimeMaintenance {
                            guard try ArclumeWineStopService.snapshot(root: BundledWineRuntime.installationURL.resolvingSymlinksInPath().path).isEmpty else { throw ResourceDownloadError.busyRuntime }
                            _ = try BundledWineRuntime.ensureInstalled()
                        }
                    }
                }.value
            }
            if componentIDs == nil { try await activateSelection() }
            progress = 1; message = "所选组件已就绪"; transferDetail = nil
        } catch {
            if let buildError = error as? NefinitaBuildError {
                self.error = buildError.localizedDescription
                throw buildError
            }
            // Transport errors may embed endpoint addresses; never display them verbatim.
            let safeError = (error as? ResourceDownloadError) ?? .invalidDownload
            self.error = safeError.localizedDescription
            throw safeError
        }
    }
}
