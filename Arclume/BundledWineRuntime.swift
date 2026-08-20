//
//  BundledWineRuntime.swift
//  Procyon
//

import CryptoKit
import Foundation

/// The online-game setup flow stores its runtime choice separately from the
/// general CrossOver preference, so choosing bundled Wine never replaces a
/// user's existing CrossOver installation.
enum OnlineGameRuntimeKind: String, CaseIterable, Identifiable, Sendable {
    case crossOver
    case bundledWine

    static let defaultsKey = "online-game-runtime-kind"
    private static let crossOverBottleDefaultsKey =
        "online-game-runtime-crossover-bottle"
    private static let bundledWineBottleDefaultsKey =
        "online-game-runtime-bundled-wine-bottle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crossOver: "CrossOver"
        case .bundledWine: "内置 Wine"
        }
    }

    var launcherTitle: String {
        switch self {
        case .crossOver: "CrossOver Patched"
        case .bundledWine: "Arclume Wine"
        }
    }

    static let launcherRuntimeOptions: DropdownOptions = Self.allCases.map {
        (id: $0.rawValue, label: $0.launcherTitle)
    }

    var detail: String {
        switch self {
        case .crossOver:
            "使用你选择的 CrossOver.app；Arclume 只为它配置随 App 附带的依赖。"
        case .bundledWine:
            "使用 Arclume 内置的自编译 Wine，首次会解压到应用支持目录并建立独立 Games 容器。"
        }
    }

    private static var persistentDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func resolvedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        defaults ?? persistentDefaults
    }

    static func selected(in defaults: UserDefaults? = nil) -> Self {
        let defaults = resolvedDefaults(defaults)
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let runtime = Self(rawValue: rawValue)
        else {
            // Preserve existing completed CrossOver configurations on upgrade.
            return .crossOver
        }
        return runtime
    }

    static func hasExplicitSelection(in defaults: UserDefaults? = nil) -> Bool {
        let defaults = resolvedDefaults(defaults)
        return defaults.string(forKey: defaultsKey) != nil
    }

    /// Selecting a generic `.app` must not reach the patcher: it assumes the
    /// CrossOver runtime layout and would otherwise fail after the copy step.
    static func isValidCrossOverApplication(at appURL: URL) -> Bool {
        let wineURL = appURL.appendingPathComponent(
            "Contents/SharedSupport/CrossOver/bin/wine"
        )
        return FileManager.default.isExecutableFile(atPath: wineURL.path)
    }

    static func select(_ runtime: Self, in defaults: UserDefaults? = nil) {
        let defaults = resolvedDefaults(defaults)
        defaults.set(runtime.rawValue, forKey: defaultsKey)
    }

    static func configuredBottleURL(
        for runtime: Self,
        in defaults: UserDefaults? = nil
    ) -> URL? {
        let defaults = resolvedDefaults(defaults)
        let key = bottleDefaultsKey(for: runtime)
        guard let path = defaults.string(forKey: key) else { return nil }
        return OnlineGameDiscovery.selectedBottleURL(from: path)
    }

    static func recordBottle(
        _ bottleURL: URL,
        for runtime: Self,
        in defaults: UserDefaults? = nil
    ) {
        let defaults = resolvedDefaults(defaults)
        defaults.set(
            bottleURL.standardizedFileURL.absoluteString,
            forKey: bottleDefaultsKey(for: runtime)
        )
    }

    /// Existing online-mode users only had a single `selectedBottle` value.
    /// Preserve that completed CrossOver setup on upgrade, but never treat an
    /// ordinary Steam Bottle as a JX3 runtime configuration.
    @discardableResult
    static func migrateLegacyCrossOverConfigurationIfNeeded(
        crossOverPath: String?,
        selectedBottle: String,
        in defaults: UserDefaults? = nil
    ) -> Bool {
        let defaults = resolvedDefaults(defaults)
        guard !hasExplicitSelection(in: defaults),
              let crossOverPath,
              FileManager.default.fileExists(atPath: crossOverPath),
              let bottleURL = OnlineGameDiscovery.selectedBottleURL(from: selectedBottle),
              FileManager.default.fileExists(atPath: bottleURL.path),
              bottleURL.lastPathComponent.caseInsensitiveCompare(
                  OnlineGameMode.defaultBottleName
              ) == .orderedSame,
              OnlineGameDiscovery.jx3Installation(in: bottleURL).isDetected
        else {
            return false
        }

        recordBottle(bottleURL, for: .crossOver, in: defaults)
        select(.crossOver, in: defaults)
        return true
    }

    static func migrateLegacyCrossOverConfigurationIfNeeded(
        appGlobals: AppGlobals,
        in defaults: UserDefaults? = nil
    ) {
        _ = migrateLegacyCrossOverConfigurationIfNeeded(
            crossOverPath: appGlobals.cxAppPath,
            selectedBottle: appGlobals.selectedBottle,
            in: defaults
        )
    }

    static func readyBottleURL(
        for runtime: Self,
        appGlobals: AppGlobals,
        in defaults: UserDefaults? = nil
    ) -> URL? {
        guard let bottleURL = configuredBottleURL(for: runtime, in: defaults),
              FileManager.default.fileExists(atPath: bottleURL.path),
              bottleURL.lastPathComponent.caseInsensitiveCompare(
                  OnlineGameMode.defaultBottleName
              ) == .orderedSame,
              OnlineGameDiscovery.jx3Installation(in: bottleURL).isDetected
        else {
            return nil
        }

        switch runtime {
        case .crossOver:
            guard let crossOverPath = appGlobals.cxAppPath,
                  isValidCrossOverApplication(
                    at: URL(fileURLWithPath: crossOverPath)
                  )
            else {
                return nil
            }
        case .bundledWine:
            guard BundledWineRuntime.ownsPrefix(bottleURL),
                  BundledWineRuntime.isValidPrefix(at: bottleURL),
                  BundledWineRuntime.isCurrentRuntime()
            else {
                return nil
            }
        }
        return bottleURL
    }

    /// Records the outgoing runtime first, then makes the target runtime the
    /// single active bottle. Neither prefix is moved, copied, or deleted.
    static func activate(
        _ runtime: Self,
        with bottleURL: URL,
        appGlobals: AppGlobals,
        in defaults: UserDefaults? = nil
    ) {
        let defaults = resolvedDefaults(defaults)
        if let currentBottleURL = OnlineGameDiscovery.selectedBottleURL(
            from: appGlobals.selectedBottle
        ), FileManager.default.fileExists(atPath: currentBottleURL.path),
           currentBottleURL.lastPathComponent.caseInsensitiveCompare(
               OnlineGameMode.defaultBottleName
           ) == .orderedSame,
           OnlineGameDiscovery.jx3Installation(in: currentBottleURL).isDetected {
            recordBottle(currentBottleURL, for: selected(in: defaults), in: defaults)
        }
        recordBottle(bottleURL, for: runtime, in: defaults)
        select(runtime, in: defaults)
        let activePath = bottleURL.standardizedFileURL.absoluteString
        appGlobals.selectedBottle = activePath
        persistUsrDefOptionString(key: "selectedBottle", value: activePath)
    }

    static func restoreActiveBottleIfAvailable(
        appGlobals: AppGlobals,
        in defaults: UserDefaults? = nil
    ) {
        guard let bottleURL = configuredBottleURL(for: selected(in: defaults), in: defaults),
              FileManager.default.fileExists(atPath: bottleURL.path)
        else {
            return
        }
        let activePath = bottleURL.standardizedFileURL.absoluteString
        appGlobals.selectedBottle = activePath
        persistUsrDefOptionString(key: "selectedBottle", value: activePath)
    }

    private static func bottleDefaultsKey(for runtime: Self) -> String {
        switch runtime {
        case .crossOver: crossOverBottleDefaultsKey
        case .bundledWine: bundledWineBottleDefaultsKey
        }
    }
}

enum BundledWineRuntimeError: LocalizedError {
    case missingArchive
    case missingManifest
    case invalidRuntime
    case runtimeVersionMismatch(String?)
    case archiveChecksumMismatch
    case invalidPrefix
    case extractionFailed(Int32)
    case prefixInitializationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingArchive:
            "本版本未包含 Arclume Wine。请在“设置 > 更新”中下载 Runtime，或使用 with-runtime 安装包。"
        case .missingManifest:
            "App 内未找到 Arclume Wine Runtime Manifest。"
        case .invalidRuntime:
            "内置 Wine 运行时不完整，无法启动。"
        case .runtimeVersionMismatch(let installedVersion):
            if let installedVersion {
                "内置 Wine 版本 \(installedVersion) 与当前 App 不匹配。"
            } else {
                "内置 Wine 缺少版本标记，无法确认其是否与当前 App 匹配。"
            }
        case .archiveChecksumMismatch:
            "内置 Wine 运行时归档校验失败。请重新安装 App 后再试。"
        case .invalidPrefix:
            "内置 Wine 的 Games 容器不完整。请勿手动删除其中的注册表文件。"
        case .extractionFailed(let status):
            "无法解压内置 Wine 运行时（退出状态 \(status)）。"
        case .prefixInitializationFailed(let status):
            "初始化内置 Wine 前缀失败（退出状态 \(status)）。详细诊断日志已保存。"
        }
    }
}

/// Keeps the bundled runtime immutable after extraction. D3DMetal remains in
/// the existing versioned archives and is selected by prepending its Wine
/// module directory to WINEDLLPATH, so switching D3DMetal 3/4 never mutates
/// this runtime or CrossOver.
enum BundledWineRuntime {
    typealias ProgressHandler = @Sendable (_ fraction: Double, _ label: String) -> Void

    struct LaunchConfiguration {
        let wineURL: URL
        let runtimeURL: URL
        let environment: [String: String]
    }

    /// Fallbacks only make diagnostics and file locations stable when a
    /// damaged App bundle is missing its manifest. Installation itself always
    /// loads and validates the Manifest before touching Application Support.
    nonisolated private static let fallbackManifest = ArclumeRuntimeManifest(
        schemaVersion: 1,
        id: "io.arclume.runtime.wine",
        displayName: "Arclume Wine",
        version: "未知版本",
        channel: "stable",
        runtimeABI: 1,
        prefixABI: "arclume-jx3-prefix-1",
        architecture: "x86_64",
        minimumMacOS: "26.0",
        legacyInstallRoots: [],
        legacyInstallMarkers: [],
        archive: .init(
            name: "arclume-wine-runtime.tar.xz",
            sha256: String(repeating: "0", count: 64),
            rootDirectory: "arclume-wine-runtime-x86_64"
        )
    )
    nonisolated static let versionMarkerFileName = ".arclume-runtime-version"
    nonisolated static let dockApplicationName = "剑网3旗舰版"

    nonisolated static var manifest: ArclumeRuntimeManifest {
        (try? requiredRuntimeManifest()) ?? fallbackManifest
    }

    nonisolated static var archiveName: String { manifest.archive.name }
    nonisolated static var archiveRootName: String { manifest.archive.rootDirectory }

    /// Kept outside the disposable staging prefix so a failed first-run can be
    /// diagnosed after the staging directory is cleaned up.
    nonisolated static var prefixInitializationLogURL: URL {
        prefixInitializationDiagnosticsDirectoryURL
            .appendingPathComponent("内置 Wine 初始化.log", isDirectory: false)
    }

    /// A self-contained location the Debug build can hand to a tester. It is
    /// intentionally outside the disposable staging prefix, so an init crash
    /// cannot remove the evidence needed to diagnose it.
    nonisolated static var prefixInitializationDiagnosticsDirectoryURL: URL {
        ArclumeGameLogStore.directoryURL
    }

    private static let installationLock = NSLock()

    nonisolated static var installationURL: URL {
        ARCLUME_SUPPORT_FOLDER_URL
            .appendingPathComponent("OnlineGameRuntimes", isDirectory: true)
            .appendingPathComponent(archiveRootName, isDirectory: true)
    }

    nonisolated static var prefixURL: URL {
        ARCLUME_SUPPORT_FOLDER_URL
            .appendingPathComponent("OnlineGameWinePrefixes", isDirectory: true)
            .appendingPathComponent(OnlineGameMode.defaultBottleName, isDirectory: true)
    }

    nonisolated static var runtimeVersion: String {
        manifest.version
    }

    nonisolated static func ownsPrefix(_ bottleURL: URL) -> Bool {
        bottleURL.standardizedFileURL.path == prefixURL.standardizedFileURL.path
    }

    nonisolated static func isValidRuntime(at runtimeURL: URL = installationURL) -> Bool {
        let fileManager = FileManager.default
        let wineURL = runtimeURL.appendingPathComponent("lib/wine/x86_64-unix/wine")
        let wineServerURL = runtimeURL.appendingPathComponent("bin/wineserver")
        let ntdllURL = runtimeURL.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so")
        let wineInfURL = runtimeURL.appendingPathComponent("share/wine/wine.inf")
        let dxvkURL = runtimeURL.appendingPathComponent("dxvk/x64/dxgi.dll")
        return fileManager.isExecutableFile(atPath: wineURL.path)
            && fileManager.isExecutableFile(atPath: wineServerURL.path)
            && fileManager.fileExists(atPath: ntdllURL.path)
            && fileManager.fileExists(atPath: wineInfURL.path)
            && fileManager.fileExists(atPath: dxvkURL.path)
    }

    nonisolated static func installedRuntimeVersion(at runtimeURL: URL) -> String? {
        let markerURL = runtimeURL.appendingPathComponent(versionMarkerFileName)
        guard let value = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated static func isCurrentRuntime(
        at runtimeURL: URL = installationURL,
        expectedVersion: String? = nil
    ) -> Bool {
        guard isValidRuntime(at: runtimeURL) else { return false }
        let expected = expectedVersion ?? (try? requiredRuntimeManifest().version)
        return expected != nil && installedRuntimeVersion(at: runtimeURL) == expected
    }

    /// Indicates that the runtime can be updated in place without rebuilding
    /// the existing Games container. This deliberately requires both sides to
    /// be valid: a damaged runtime or prefix must still go through repair.
    nonisolated static func requiresRuntimeUpdate(
        runtimeURL: URL,
        prefixURL: URL,
        expectedVersion: String? = nil
    ) -> Bool {
        isValidRuntime(at: runtimeURL)
            && isValidPrefix(at: prefixURL)
            && !isCurrentRuntime(
                at: runtimeURL,
                expectedVersion: expectedVersion
            )
    }

    /// The final Procyon runtime was installed under a different directory
    /// name. Treat it as an update candidate so existing users see the short
    /// Runtime-updater sheet instead of first-run onboarding.
    nonisolated static func hasMigratableLegacyInstallation() -> Bool {
        guard let manifest = try? requiredRuntimeManifest(),
              !FileManager.default.fileExists(atPath: installationURL.path)
        else {
            return false
        }
        return recognizedLegacyInstallation(manifest: manifest) != nil
    }

    nonisolated static func pendingLegacyRuntimeVersion() -> String? {
        guard let manifest = try? requiredRuntimeManifest(),
              let legacyURL = recognizedLegacyInstallation(manifest: manifest)
        else {
            return nil
        }
        let markerURL = legacyURL.appendingPathComponent(
            ".procyon-runtime-version",
            isDirectory: false
        )
        return (try? String(contentsOf: markerURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func isValidPrefix(at bottleURL: URL = prefixURL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: bottleURL.appendingPathComponent("drive_c").path)
            && fileManager.fileExists(atPath: bottleURL.appendingPathComponent("system.reg").path)
            && fileManager.fileExists(atPath: bottleURL.appendingPathComponent("user.reg").path)
            && fileManager.fileExists(atPath: bottleURL.appendingPathComponent("cxbottle.conf").path)
    }

    /// Expands the signed, compressed runtime only into Procyon's private
    /// Application Support directory. A failed extraction stays in staging and
    /// never replaces a previously valid runtime.
    @discardableResult
    nonisolated static func ensureInstalled() throws -> URL {
        try ensureInstalled(progress: nil)
    }

    @discardableResult
    nonisolated static func ensureInstalled(
        progress: ProgressHandler?
    ) throws -> URL {
        progress?(0.02, "正在检查内置 Wine 运行时…")
        installationLock.lock()
        defer { installationLock.unlock() }
        let manifest = try requiredRuntimeManifest()
        let expectedVersion = manifest.version
        try migrateLegacyInstallationIfNeeded(manifest: manifest)

        if FileManager.default.fileExists(atPath: installationURL.path) {
            guard isValidRuntime() else { throw BundledWineRuntimeError.invalidRuntime }
            if isCurrentRuntime(expectedVersion: expectedVersion) {
                progress?(1, "内置 Wine \(expectedVersion) 已就绪")
                return installationURL
            }
            progress?(0.05, "正在更新内置 Wine \(expectedVersion)…")
        }

        guard let archiveURL = BundledOnlineGameResources.resourceURL(
            named: manifest.archive.name
        ) else {
            throw BundledWineRuntimeError.missingArchive
        }
        guard try archiveSHA256(at: archiveURL) == manifest.archive.sha256 else {
            throw BundledWineRuntimeError.archiveChecksumMismatch
        }

        let fileManager = FileManager.default
        let parentURL = installationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        progress?(0.06, "正在分析 Wine 运行时归档…")
        let archiveEntryCount = try archiveEntryCount(in: archiveURL)

        let stagingURL = parentURL.appendingPathComponent(
            ".\(manifest.archive.rootDirectory)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }
        try extractRuntimeArchive(
            archiveURL,
            into: stagingURL,
            totalEntries: archiveEntryCount,
            progress: progress
        )

        let extractedRuntimeURL = stagingURL.appendingPathComponent(
            manifest.archive.rootDirectory,
            isDirectory: true
        )
        progress?(0.94, "正在校验解压后的 Wine 运行时…")
        guard isCurrentRuntime(
            at: extractedRuntimeURL,
            expectedVersion: expectedVersion
        ) else {
            throw BundledWineRuntimeError.runtimeVersionMismatch(
                installedRuntimeVersion(at: extractedRuntimeURL)
            )
        }
        try replaceInstalledRuntime(
            with: extractedRuntimeURL,
            fileManager: fileManager
        )
        progress?(1, "内置 Wine \(expectedVersion) 已准备完成")
        return installationURL
    }

    /// A downloadable Runtime may replace Wine without moving the Games
    /// container only when its ABI contract matches the one bundled with the
    /// current App. Keep this narrow: accepting a different prefix ABI could
    /// make an existing game prefix silently unusable.
    nonisolated static func supportsDownloadedRuntimeManifest(
        _ downloadedManifest: ArclumeRuntimeManifest
    ) -> Bool {
        guard let bundledManifest = try? requiredRuntimeManifest() else {
            return false
        }
        return downloadedManifest.id == bundledManifest.id
            && downloadedManifest.runtimeABI == bundledManifest.runtimeABI
            && downloadedManifest.prefixABI == bundledManifest.prefixABI
            && downloadedManifest.architecture == bundledManifest.architecture
    }

    /// Installs a checksum-verified release archive into the same immutable
    /// Runtime location as the App-bundled archive. The existing Games prefix
    /// deliberately lives elsewhere and is never copied, moved or recreated.
    @discardableResult
    nonisolated static func installDownloadedRuntimeArchive(
        _ archiveURL: URL,
        manifest downloadedManifest: ArclumeRuntimeManifest,
        progress: ProgressHandler? = nil
    ) throws -> URL {
        try downloadedManifest.validate()
        guard supportsDownloadedRuntimeManifest(downloadedManifest) else {
            throw ArclumeRuntimeManifestError.invalid("与当前 Games 容器 ABI 不兼容")
        }
        guard try archiveSHA256(at: archiveURL)
            .caseInsensitiveCompare(downloadedManifest.archive.sha256) == .orderedSame
        else {
            throw BundledWineRuntimeError.archiveChecksumMismatch
        }

        progress?(0.02, "正在校验 Arclume Wine 更新…")
        installationLock.lock()
        defer { installationLock.unlock() }

        let fileManager = FileManager.default
        let parentURL = installationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        progress?(0.06, "正在分析 Arclume Wine 更新归档…")
        let entryCount = try archiveEntryCount(in: archiveURL)
        let stagingURL = parentURL.appendingPathComponent(
            ".\(downloadedManifest.archive.rootDirectory)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        try extractRuntimeArchive(
            archiveURL,
            into: stagingURL,
            totalEntries: entryCount,
            progress: progress
        )
        let extractedRuntimeURL = stagingURL.appendingPathComponent(
            downloadedManifest.archive.rootDirectory,
            isDirectory: true
        )
        progress?(0.94, "正在校验 Arclume Wine 更新…")
        guard isCurrentRuntime(
            at: extractedRuntimeURL,
            expectedVersion: downloadedManifest.version
        ) else {
            throw BundledWineRuntimeError.runtimeVersionMismatch(
                installedRuntimeVersion(at: extractedRuntimeURL)
            )
        }
        try replaceInstalledRuntime(
            with: extractedRuntimeURL,
            previousRootName: downloadedManifest.archive.rootDirectory,
            fileManager: fileManager
        )
        progress?(1, "Arclume Wine \(downloadedManifest.version) 已准备完成")
        return installationURL
    }

    /// Wine creates a prefix asynchronously after wineboot returns, so the
    /// registry/drive checks are the completion signal instead of only relying
    /// on the helper process exit code.
    @discardableResult
    nonisolated static func preparePrefix() throws -> URL {
        try preparePrefix(progress: nil)
    }

    @discardableResult
    nonisolated static func preparePrefix(
        progress: ProgressHandler?
    ) throws -> URL {
        progress?(0.01, "正在检查内置 Wine…")
        let runtimeURL = try ensureInstalled { fraction, label in
            progress?(0.02 + fraction * 0.60, label)
        }
        if FileManager.default.fileExists(atPath: prefixURL.path) {
            guard isValidPrefix() else { throw BundledWineRuntimeError.invalidPrefix }
            progress?(1, "内置 Wine 与 Games 容器已就绪")
            return prefixURL
        }

        let fileManager = FileManager.default
        let prefixParentURL = prefixURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: prefixParentURL, withIntermediateDirectories: true)
        let stagingPrefixURL = prefixParentURL.appendingPathComponent(
            ".\(OnlineGameMode.defaultBottleName)-initializing-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingPrefixURL) }

        progress?(0.66, "正在准备 D3DMetal 和 Wine 环境…")
        let graphicsBackend = OnlineGameMode.defaultGraphicsBackend
        let configuration = try makeLaunchConfiguration(
            runtimeURL: runtimeURL,
            graphicsBackend: graphicsBackend,
            d3dMetal4Enabled: graphicsBackend == "d3dmetal4",
            mtlHudEnabled: false,
            wineMSync: true
        )
        var environment = configuration.environment
        environment["WINEPREFIX"] = stagingPrefixURL.path
        environment["WINEARCH"] = "win64"
        // A Wine server/SEH trace can grow to several gigabytes during a
        // normal game session. It is opt-in even for Debug builds so user
        // diagnostics always remain bounded by Procyon's log retention.
        if verboseWineTraceRequested {
            environment["WINEDEBUG"] = "-all,+timestamp,+pid,+tid,+server,+seh"
        }

        progress?(0.74, "正在创建独立的 Games 容器…")
        let initializationLogHandle = try resetPrefixInitializationLog(
            runtimeURL: runtimeURL,
            stagingPrefixURL: stagingPrefixURL,
            environment: environment
        )
        defer { try? initializationLogHandle.close() }

        let process = Process()
        process.executableURL = configuration.wineURL
        process.arguments = ["C:\\windows\\system32\\wineboot.exe", "--init"]
        process.environment = environment
        process.currentDirectoryURL = runtimeURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = initializationLogHandle
        process.standardError = initializationLogHandle
        try writePrefixInitializationLog(
            "启动命令：\(configuration.wineURL.path) C:\\windows\\system32\\wineboot.exe --init",
            to: initializationLogHandle
        )
        do {
            try process.run()
        } catch {
            try? writePrefixInitializationLog(
                "无法启动 wineboot：\(error.localizedDescription)",
                to: initializationLogHandle
            )
            throw error
        }
        process.waitUntilExit()
        try? writePrefixInitializationLog(
            "wineboot 已退出：reason=\(process.terminationReason) status=\(process.terminationStatus)",
            to: initializationLogHandle
        )
        let hasDriveC = fileManager.fileExists(
            atPath: stagingPrefixURL.appendingPathComponent("drive_c").path
        )
        let hasSystemRegistry = fileManager.fileExists(
            atPath: stagingPrefixURL.appendingPathComponent("system.reg").path
        )
        let hasUserRegistry = fileManager.fileExists(
            atPath: stagingPrefixURL.appendingPathComponent("user.reg").path
        )
        try? writePrefixInitializationLog(
            "前缀文件：drive_c=\(hasDriveC) system.reg=\(hasSystemRegistry) user.reg=\(hasUserRegistry)",
            to: initializationLogHandle
        )
        if waitForValidPrefix(at: stagingPrefixURL) { fraction in
            progress?(0.78 + fraction * 0.17, "正在初始化 Windows 注册表和驱动器…")
        } {
            progress?(0.96, "正在写入中文环境和 Bottle 配置…")
            try "[EnvironmentVariables]\n".write(
                to: stagingPrefixURL.appendingPathComponent("cxbottle.conf"),
                atomically: true,
                encoding: .utf8
            )
            try fileManager.moveItem(at: stagingPrefixURL, to: prefixURL)
            progress?(1, "内置 Wine 与 Games 容器已准备完成")
            return prefixURL
        }
        if process.terminationReason == .uncaughtSignal {
            copyRecentWineCrashReports(to: initializationLogHandle)
        }
        throw BundledWineRuntimeError.prefixInitializationFailed(process.terminationStatus)
    }

    nonisolated static func makeLaunchConfiguration(options: GameOptions) throws -> LaunchConfiguration {
        let runtimeURL = try ensureInstalled()
        return try makeLaunchConfiguration(
            runtimeURL: runtimeURL,
            graphicsBackend: options.cxGraphicsBackend,
            d3dMetal4Enabled: options.d3dMtl4Enabled,
            mtlHudEnabled: options.mtlHudEnabled,
            wineMSync: options.wineMSync
        )
    }

    nonisolated private static func makeLaunchConfiguration(
        runtimeURL: URL,
        graphicsBackend: String,
        d3dMetal4Enabled: Bool,
        mtlHudEnabled: Bool,
        wineMSync: Bool
    ) throws -> LaunchConfiguration {
        guard isCurrentRuntime(at: runtimeURL) else {
            throw BundledWineRuntimeError.invalidRuntime
        }

        let d3dMetalVersion = graphicsBackend == "d3dmetal3" ? "3" : "4"
        guard let graphicsRootURL = try BundledOnlineGameResources.bundledURL(
            named: "d3dMetal\(d3dMetalVersion)"
        ) else {
            throw BundledOnlineGameResourceError.missingResource(
                BundledOnlineGameResources.d3dMetalArchiveName(version: d3dMetalVersion)
            )
        }
        let graphicsWineURL = graphicsRootURL.appendingPathComponent("wine", isDirectory: true)
        guard FileManager.default.fileExists(atPath: graphicsWineURL.path) else {
            throw BundledOnlineGameResourceError.invalidArchive("d3dMetal\(d3dMetalVersion)")
        }

        var environment = ProcessInfo.processInfo.environment
        environment["WINEDATADIR"] = runtimeURL.appendingPathComponent("share/wine").path
        environment["WINESERVER"] = runtimeURL.appendingPathComponent("bin/wineserver").path
        environment.merge(
            graphicsRuntimeEnvironment(
                runtimeURL: runtimeURL,
                graphicsRootURL: graphicsRootURL,
                graphicsWineURL: graphicsWineURL,
                graphicsBackend: graphicsBackend,
                d3dMetal4Enabled: d3dMetal4Enabled
            ),
            uniquingKeysWith: { _, new in new }
        )
        environment["WINEDEBUG"] = "-all"
        environment["WINEMSYNC"] = wineMSync ? "1" : "0"
        environment["ROSETTA_ADVERTISE_AVX"] = "1"
        environment["PROCYON_NO_GPFAULT_ERROR_DIALOG"] = "1"
        environment["PROCYON_WINE_DOCK_NAME"] = dockApplicationName
        environment["WINEPRELOADERAPPNAME"] = dockApplicationName
        environment["MTL_HUD_ENABLED"] = mtlHudEnabled ? "1" : "0"
        environment["__CX_UNIX_MTL_HUD_ENABLED"] = mtlHudEnabled ? "1" : "0"
        OnlineGameBottleConfiguration.applyProcessEnvironment(to: &environment)

        return LaunchConfiguration(
            wineURL: runtimeURL.appendingPathComponent("lib/wine/x86_64-unix/wine"),
            runtimeURL: runtimeURL,
            environment: environment
        )
    }

    /// Direct Wine does not consume Procyon's legacy DLL-path marker. Its
    /// loader only honours WINEDLLPATH, so D3DMetal must be first in that
    /// search path for its d3d11/dxgi modules to replace Wine's built-ins.
    /// Keep the Wine runtime second so all non-D3DMetal modules remain intact.
    nonisolated static func graphicsRuntimeEnvironment(
        runtimeURL: URL,
        graphicsRootURL: URL,
        graphicsWineURL: URL,
        graphicsBackend: String,
        d3dMetal4Enabled: Bool
    ) -> [String: String] {
        let wineModulePath = runtimeURL.appendingPathComponent("lib/wine").path
        let usesD3DMetal = graphicsBackend.contains("d3dmetal")
        let activeBackend = usesD3DMetal ? "d3dmetal" : graphicsBackend
        let wineDLLPath = usesD3DMetal
            ? [graphicsWineURL.path, wineModulePath].joined(separator: ":")
            : wineModulePath
        let fallbackLibraries = usesD3DMetal
            ? [
                graphicsRootURL.appendingPathComponent("external").path,
                graphicsRootURL.path,
                runtimeURL.appendingPathComponent("lib64").path
            ]
            : [runtimeURL.appendingPathComponent("lib64").path]

        return [
            "WINEDLLPATH": wineDLLPath,
            // Retained in diagnostic logs and for existing user tooling. Wine
            // itself selects the modules through WINEDLLPATH above.
            "PROCYON_DLL_PATH": usesD3DMetal ? graphicsWineURL.path : "",
            // d3d11.so/dxgi.so resolve libd3dshared.dylib from this directory.
            "DYLD_FALLBACK_LIBRARY_PATH": fallbackLibraries.joined(separator: ":"),
            "CX_GRAPHICS_BACKEND": activeBackend,
            // CrossOver normally derives this through cxcompatdb. The bundled
            // runtime launches Wine directly, so provide the final value.
            "CX_ACTIVE_GRAPHICS_BACKEND": activeBackend,
            "D3DM_MTL4": d3dMetal4Enabled ? "1" : "0",
            "D3DM_ENABLE_METALFX": "1",
            "DXMT_ENABLE_NVEXT": "1",
            "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "1",
            "MVK_CONFIG_LOG_LEVEL": "0"
        ]
    }

    nonisolated private static func requiredRuntimeManifest() throws -> ArclumeRuntimeManifest {
        do {
            return try ArclumeRuntimeManifest.load()
        } catch ArclumeRuntimeManifestError.missing {
            throw BundledWineRuntimeError.missingManifest
        }
    }

    /// Retain existing users' already-extracted Wine 11 runtime when it is
    /// exactly the final Procyon build we shipped. This is a rename within the
    /// same Application Support volume, so it neither copies the runtime nor
    /// consumes an additional 136 MB of storage.
    nonisolated private static func migrateLegacyInstallationIfNeeded(
        manifest: ArclumeRuntimeManifest
    ) throws {
        let currentURL = installationURL
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: currentURL.path),
              let legacyURL = recognizedLegacyInstallation(manifest: manifest)
        else { return }

        try fileManager.createDirectory(
            at: currentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: legacyURL, to: currentURL)
        try manifest.version.appending("\n").write(
            to: currentURL.appendingPathComponent(versionMarkerFileName),
            atomically: true,
            encoding: .utf8
        )
        try? fileManager.removeItem(at: currentURL.appendingPathComponent(
            ".procyon-runtime-version"
        ))
    }

    nonisolated private static func recognizedLegacyInstallation(
        manifest: ArclumeRuntimeManifest
    ) -> URL? {
        let parentURL = installationURL.deletingLastPathComponent()
        for rootName in manifest.legacyInstallRoots {
            let legacyURL = parentURL.appendingPathComponent(rootName, isDirectory: true)
            guard isValidRuntime(at: legacyURL) else { continue }
            let markerURL = legacyURL.appendingPathComponent(
                ".procyon-runtime-version",
                isDirectory: false
            )
            let marker = (try? String(contentsOf: markerURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let marker, manifest.legacyInstallMarkers.contains(marker) {
                return legacyURL
            }
        }
        return nil
    }

    nonisolated private static func archiveSHA256(at archiveURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func resetPrefixInitializationLog(
        runtimeURL: URL,
        stagingPrefixURL: URL,
        environment: [String: String]
    ) throws -> FileHandle {
        let logURL = prefixInitializationLogURL
        _ = ArclumeGameLogStore.directoryForUser()
        ArclumeGameLogStore.enforceStorageLimit()
        try Data().write(to: logURL, options: .atomic)
        let handle = try FileHandle(forWritingTo: logURL)
        try writePrefixInitializationLog("Arclume 内置 Wine 前缀初始化诊断", to: handle)
        try writePrefixInitializationLog("构建类型：\(buildFlavor)", to: handle)
        try writePrefixInitializationLog("App：\(Bundle.main.bundleIdentifier ?? "<未知>") \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "<未知>")", to: handle)
        try writePrefixInitializationLog("时间：\(ISO8601DateFormatter().string(from: Date()))", to: handle)
        try writePrefixInitializationLog("macOS：\(ProcessInfo.processInfo.operatingSystemVersionString)", to: handle)
        try writePrefixInitializationLog("运行时：\(runtimeURL.path)", to: handle)
        try writePrefixInitializationLog("运行时版本：\(installedRuntimeVersion(at: runtimeURL) ?? "<缺失>")", to: handle)
        try writePrefixInitializationLog("临时 Games 容器：\(stagingPrefixURL.path)", to: handle)
        for key in [
            "WINEPREFIX",
            "WINEARCH",
            "WINEDATADIR",
            "WINEDLLPATH",
            "WINESERVER",
            "PROCYON_DLL_PATH",
            "DYLD_FALLBACK_LIBRARY_PATH",
            "WINEMSYNC",
            "CX_GRAPHICS_BACKEND",
            "CX_ACTIVE_GRAPHICS_BACKEND",
            "D3DM_MTL4",
            "ROSETTA_ADVERTISE_AVX",
            "MTL_HUD_ENABLED"
        ] {
            let value = environment[key] ?? "<未设置>"
            try writePrefixInitializationLog(
                "环境 \(key)=\(value)",
                to: handle
            )
        }
        appendRuntimeBinaryDiagnostics(runtimeURL: runtimeURL, to: handle)
        handle.synchronizeFile()
        return handle
    }

    nonisolated private static var buildFlavor: String {
#if DEBUG
        "Debug"
#else
        "Release"
#endif
    }

    /// Verbose Wine tracing is intentionally an internal, explicit opt-in.
    /// The normal Debug app is shared with testers, where tracing every Wine
    /// server message would otherwise make a multi-gigabyte log file.
    nonisolated static var verboseWineTraceRequested: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["PROCYON_ENABLE_WINE_TRACE"] == "1"
#else
        false
#endif
    }

    /// Capture executable metadata before wineboot starts. This makes reports
    /// from a different macOS build actionable even when the process crashes
    /// before Wine can emit a normal debug line.
    nonisolated static func appendLauncherDiagnostics(
        runtimeURL: URL,
        wineURL: URL,
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        to handle: FileHandle
    ) {
        try? writePrefixInitializationLog("Arclume 内置 Wine 启动器调试", to: handle)
        try? writePrefixInitializationLog(
            "启动命令：\(wineURL.path) \(executableURL.path) \(arguments.joined(separator: " "))",
            to: handle
        )
        for key in [
            "WINEPREFIX",
            "WINEDATADIR",
            "WINEDLLPATH",
            "WINESERVER",
            "PROCYON_DLL_PATH",
            "DYLD_FALLBACK_LIBRARY_PATH",
            "WINEDEBUG",
            "WINEMSYNC",
            "CX_GRAPHICS_BACKEND",
            "CX_ACTIVE_GRAPHICS_BACKEND",
            "D3DM_MTL4",
            "ROSETTA_ADVERTISE_AVX"
        ] {
            try? writePrefixInitializationLog(
                "环境 \(key)=\(environment[key] ?? "<未设置>")",
                to: handle
            )
        }
        appendRuntimeBinaryDiagnostics(runtimeURL: runtimeURL, to: handle)
        handle.synchronizeFile()
    }

    nonisolated static func appendRuntimeBinaryDiagnostics(
        runtimeURL: URL,
        to handle: FileHandle
    ) {
        appendDiagnosticCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/sw_vers"),
            label: "sw_vers",
            to: handle
        )
        appendDiagnosticCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/uname"),
            arguments: ["-m"],
            label: "uname -m",
            to: handle
        )
        appendDiagnosticCommand(
            executableURL: URL(fileURLWithPath: "/usr/sbin/sysctl"),
            arguments: ["-n", "sysctl.proc_translated"],
            label: "Rosetta 状态",
            to: handle
        )

        for binaryURL in [
            runtimeURL.appendingPathComponent("lib/wine/x86_64-unix/wine"),
            runtimeURL.appendingPathComponent("bin/wineserver"),
            runtimeURL.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so")
        ] {
            appendDiagnosticCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/file"),
                arguments: [binaryURL.path],
                label: "file \(binaryURL.lastPathComponent)",
                to: handle
            )
            appendDiagnosticCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["vtool", "-show-build", binaryURL.path],
                label: "vtool \(binaryURL.lastPathComponent)",
                to: handle
            )
            appendDiagnosticCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/otool"),
                arguments: ["-L", binaryURL.path],
                label: "otool \(binaryURL.lastPathComponent)",
                to: handle
            )
            appendDiagnosticCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["-dvv", binaryURL.path],
                label: "codesign \(binaryURL.lastPathComponent)",
                to: handle
            )
        }
    }

    nonisolated private static func appendDiagnosticCommand(
        executableURL: URL,
        arguments: [String] = [],
        label: String,
        to handle: FileHandle
    ) {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        do {
            try process.run()
            process.waitUntilExit()
            let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
            let error = standardError.fileHandleForReading.readDataToEndOfFile()
            let contents = String(data: output + error, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "<无输出>"
            try? writePrefixInitializationLog(
                "[\(label)] status=\(process.terminationStatus)\n\(contents)",
                to: handle
            )
        } catch {
            try? writePrefixInitializationLog(
                "[\(label)] 无法执行：\(error.localizedDescription)",
                to: handle
            )
        }
    }

    /// macOS generally writes the .ips file after a signal-terminated child
    /// exits. The prefix validation wait below gives crash reporting time to
    /// flush; copy any matching recent report beside Procyon's own log.
    nonisolated static func copyRecentWineCrashReports(to handle: FileHandle) {
        defer { ArclumeGameLogStore.enforceStorageLimit() }
        let fileManager = FileManager.default
        let reportsURL = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first!
        .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
        guard let reports = try? fileManager.contentsOfDirectory(
            at: reportsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            try? writePrefixInitializationLog("未找到 macOS 崩溃报告目录。", to: handle)
            return
        }
        let cutoff = Date().addingTimeInterval(-120)
        let candidates = reports.filter { reportURL in
            let name = reportURL.lastPathComponent.lowercased()
            guard name.contains("wine") || name.contains("wineserver") else {
                return false
            }
            let modified = (try? reportURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            return modified >= cutoff
        }
        guard !candidates.isEmpty else {
            try? writePrefixInitializationLog(
                "尚未找到本次 wine/wineserver 的 macOS 崩溃报告。",
                to: handle
            )
            return
        }
        for reportURL in candidates {
            let destinationURL = prefixInitializationDiagnosticsDirectoryURL
                .appendingPathComponent("崩溃报告-\(reportURL.lastPathComponent)")
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: reportURL, to: destinationURL)
                try writePrefixInitializationLog(
                    "已收集 macOS 崩溃报告：\(destinationURL.path)",
                    to: handle
                )
            } catch {
                try? writePrefixInitializationLog(
                    "无法收集崩溃报告 \(reportURL.lastPathComponent)：\(error.localizedDescription)",
                    to: handle
                )
            }
        }
    }

    nonisolated private static func writePrefixInitializationLog(
        _ line: String,
        to handle: FileHandle
    ) throws {
        let data = Data((line + "\n").utf8)
        try handle.write(contentsOf: data)
        handle.synchronizeFile()
    }

    /// The runtime is immutable and holds no user state, while the Games
    /// prefix is elsewhere. Move the old runtime aside first so a failed move
    /// can be rolled back without touching the prefix.
    nonisolated private static func replaceInstalledRuntime(
        with extractedRuntimeURL: URL,
        previousRootName: String = archiveRootName,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: installationURL.path) else {
            try fileManager.moveItem(at: extractedRuntimeURL, to: installationURL)
            return
        }

        let previousRuntimeURL = installationURL.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(previousRootName)-previous-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.moveItem(at: installationURL, to: previousRuntimeURL)
        do {
            try fileManager.moveItem(at: extractedRuntimeURL, to: installationURL)
        } catch {
            try? fileManager.moveItem(at: previousRuntimeURL, to: installationURL)
            throw error
        }
        try? fileManager.removeItem(at: previousRuntimeURL)
    }

    nonisolated private static func archiveEntryCount(in archiveURL: URL) throws -> Int {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tJf", archiveURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BundledWineRuntimeError.extractionFailed(process.terminationStatus)
        }
        return max(1, data.reduce(into: 0) { count, byte in
            if byte == 0x0A { count += 1 }
        })
    }

    nonisolated private static func extractRuntimeArchive(
        _ archiveURL: URL,
        into destinationURL: URL,
        totalEntries: Int,
        progress: ProgressHandler?
    ) throws {
        let process = Process()
        let output = Pipe()
        let progressLock = NSLock()
        var extractedEntries = 0

        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xJvf", archiveURL.path, "-C", destinationURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let completed = data.reduce(into: 0) { count, byte in
                if byte == 0x0A { count += 1 }
            }
            guard completed > 0 else { return }
            progressLock.lock()
            extractedEntries += completed
            let fraction = min(Double(extractedEntries) / Double(totalEntries), 1)
            progressLock.unlock()
            progress?(0.10 + fraction * 0.80, "正在解压内置 Wine（\(Int(fraction * 100))%）…")
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            try? output.fileHandleForReading.close()
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BundledWineRuntimeError.extractionFailed(process.terminationStatus)
        }
        progress?(0.90, "Wine 解压完成，正在整理运行时文件…")
    }

    nonisolated private static func waitForValidPrefix(
        at url: URL,
        progress: (Double) -> Void
    ) -> Bool {
        for attempt in 0..<120 {
            if isValidPrefixSkeleton(at: url) { return true }
            progress(Double(attempt + 1) / 120)
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    nonisolated private static func isValidPrefixSkeleton(at bottleURL: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: bottleURL.appendingPathComponent("drive_c").path)
            && fileManager.fileExists(atPath: bottleURL.appendingPathComponent("system.reg").path)
            && fileManager.fileExists(atPath: bottleURL.appendingPathComponent("user.reg").path)
    }
}
