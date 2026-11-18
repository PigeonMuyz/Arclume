//
//  BundledWineRuntime.swift
//  Arclume
//

import CryptoKit
import Darwin
import Foundation
import OSLog

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
        if runtime == .bundledWine { return BundledWineRuntime.prefixURL }
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
                  BundledWineRuntime.isCurrentRuntime(at: WineRuntimeProvider.runtimeURL(for: bottleURL))
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

/// The ordinary Windows-game library keeps its runtime preference separate
/// from the JX3 runtime. Switching does not touch either existing prefix.
enum StandardGameRuntimeKind: String, CaseIterable, Identifiable, Sendable {
    case crossOver
    case bundledWine

    static let defaultsKey = "standard-game-runtime-kind"
    private static let crossOverBottleDefaultsKey =
        "standard-game-runtime-crossover-bottle"
    private static let bundledWineBottleDefaultsKey =
        "standard-game-runtime-bundled-wine-bottle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crossOver: "CrossOver"
        case .bundledWine: "Arclume Wine"
        }
    }

    static func selected(in defaults: UserDefaults? = nil) -> Self {
        let defaults = defaults ?? UserDefaults(suiteName: suiteName) ?? .standard
        guard let value = defaults.string(forKey: defaultsKey), let runtime = Self(rawValue: value) else {
            return .crossOver
        }
        return runtime
    }

    static func select(_ runtime: Self, in defaults: UserDefaults? = nil) {
        let defaults = defaults ?? UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(runtime.rawValue, forKey: defaultsKey)
    }

    static func configuredBottleURL(
        for runtime: Self,
        in defaults: UserDefaults? = nil
    ) -> URL? {
        let defaults = defaults ?? UserDefaults(suiteName: suiteName) ?? .standard
        guard let path = defaults.string(forKey: bottleDefaultsKey(for: runtime)) else {
            return nil
        }
        return OnlineGameDiscovery.selectedBottleURL(from: path)
    }

    static func recordBottle(
        _ bottleURL: URL,
        for runtime: Self,
        in defaults: UserDefaults? = nil
    ) {
        let defaults = defaults ?? UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(
            bottleURL.standardizedFileURL.absoluteString,
            forKey: bottleDefaultsKey(for: runtime)
        )
    }

    static func activate(
        _ runtime: Self,
        with bottleURL: URL,
        appGlobals: AppGlobals,
        in defaults: UserDefaults? = nil
    ) {
        let defaults = defaults ?? UserDefaults(suiteName: suiteName) ?? .standard
        if let current = OnlineGameDiscovery.selectedBottleURL(from: appGlobals.selectedBottle),
           FileManager.default.fileExists(atPath: current.path)
        {
            recordBottle(current, for: selected(in: defaults), in: defaults)
        }
        recordBottle(bottleURL, for: runtime, in: defaults)
        select(runtime, in: defaults)
        let path = bottleURL.standardizedFileURL.absoluteString
        appGlobals.selectedBottle = path
        persistUsrDefOptionString(key: "selectedBottle", value: path)
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
    case unsupportedD3DMetal4

    var errorDescription: String? {
        switch self {
        case .missingArchive:
            "运行环境尚未下载。请在“设置 > 运行环境”中下载运行环境及组件后重试。"
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
        case .unsupportedD3DMetal4:
            OnlineGameMode.d3dMetal4RequirementMessage
        }
    }
}

/// Keeps the bundled runtime separate from all user data. D3DMetal modules
/// are installed into the runtime's Wine module directories because Wine
/// resolves built-in modules from that layout rather than from a standalone
/// archive path. The Games prefix and game files are never modified here.
enum BundledWineRuntime {
    nonisolated private static let upgradeLogger = Logger(subsystem: "io.github.pigeonmuyz.arclume", category: "RuntimeUpgrade")
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
    private static let graphicsModuleInstallationLock = NSLock()
    private static let graphicsModuleMarkerFileName = ".arclume-d3dmetal-version"
    private static let graphicsModuleDirectoryNames = [
        "x86_64-windows",
        "x86_64-unix"
    ]

    nonisolated static var installationURL: URL {
        ARCLUME_SUPPORT_FOLDER_URL
            .appendingPathComponent("OnlineGameRuntimes", isDirectory: true)
            .appendingPathComponent(archiveRootName, isDirectory: true)
    }

    nonisolated static var prefixURL: URL {
        unifiedPrefixURL
    }

    nonisolated static var unifiedPrefixURL: URL {
        ARCLUME_SUPPORT_FOLDER_URL.appendingPathComponent("ALBottles", isDirectory: true)
    }

    nonisolated static var standardSteamPrefixURL: URL {
        unifiedPrefixURL
    }

    nonisolated static var runtimeVersion: String {
        manifest.version
    }

    nonisolated static func ownsPrefix(_ bottleURL: URL) -> Bool {
        switch WineRuntimeProvider.provider(for: bottleURL) {
        case .arclume, .nefinita: true
        default: false
        }
    }

    nonisolated static func ownsStandardSteamPrefix(_ bottleURL: URL) -> Bool {
        ownsPrefix(bottleURL)
    }

    nonisolated static func isValidRuntime(at runtimeURL: URL = installationURL) -> Bool {
        if runtimeURL.standardizedFileURL == NefinitaRuntime.installationURL.standardizedFileURL {
            return NefinitaRuntime.isReady(at: runtimeURL)
        }
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
        if runtimeURL.standardizedFileURL == NefinitaRuntime.installationURL.standardizedFileURL {
            return NefinitaRuntime.isReady(at: runtimeURL) && (expectedVersion == nil || expectedVersion == NefinitaRuntime.version)
        }
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

    /// The final legacy runtime was installed under a different directory
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

    /// Expands the signed, compressed runtime only into Arclume's private
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
        upgradeLogger.notice("Runtime check: expected=\(expectedVersion, privacy: .public) installed=\(installedRuntimeVersion(at: installationURL) ?? "missing", privacy: .public)")
        try migrateLegacyInstallationIfNeeded(manifest: manifest)

        if FileManager.default.fileExists(atPath: installationURL.path) {
            guard isValidRuntime() else { throw BundledWineRuntimeError.invalidRuntime }
            if isCurrentRuntime(expectedVersion: expectedVersion) {
                upgradeLogger.notice("Runtime check: reusing installed runtime")
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
        upgradeLogger.notice("Runtime bundled archive installed: version=\(expectedVersion, privacy: .public)")
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
        upgradeLogger.notice("Runtime downloaded update: installed=\(installedRuntimeVersion(at: installationURL) ?? "missing", privacy: .public) target=\(downloadedManifest.version, privacy: .public)")
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
        upgradeLogger.notice("Runtime downloaded update completed: version=\(downloadedManifest.version, privacy: .public)")
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
        progress: ProgressHandler?,
        graphicsBackend: String? = nil
    ) throws -> URL {
        let target = prefixURL
        let result = try preparePrefix(
            at: target,
            containerName: target.lastPathComponent,
            progress: progress,
            graphicsBackend: graphicsBackend
        )
        NotificationCenter.default.post(name: .arclumeWinePrefixReady, object: result)
        return result
    }

    @discardableResult
    nonisolated static func prepareStandardSteamPrefix(
        progress: ProgressHandler? = nil
    ) throws -> URL {
        let target = standardSteamPrefixURL
        let result = try preparePrefix(
            at: target,
            containerName: target.lastPathComponent,
            progress: progress
        )
        NotificationCenter.default.post(name: .arclumeWinePrefixReady, object: result)
        return result
    }

    /// Explicit container-management preparation. Existing ALBottles and the
    /// global engine selection are deliberately outside this entry point.
    nonisolated static func prepareManagedContainer(
        id: String, repository: ManagedWineContainerRepository,
        progress: ProgressHandler? = nil
    ) throws -> URL {
        let item = try repository.initializationTarget(id: id)
        let runtime = item.provider == .arclume ? installationURL : NefinitaRuntime.installationURL
        guard isCurrentRuntime(at: runtime) else { throw ManagedContainerError.runtimeUnavailable }
        // User-facing names must never form temporary directory paths.
        return try preparePrefix(at: item.prefixURL(root: repository.root), containerName: item.id,
                                 progress: progress, preparedRuntimeURL: runtime,
                                 displayName: item.name, initializationTimeout: 120)
    }

    private static func preparePrefix(
        at targetPrefixURL: URL,
        containerName: String,
        progress: ProgressHandler?,
        preparedRuntimeURL: URL? = nil,
        displayName: String? = nil,
        initializationTimeout: TimeInterval? = nil,
        graphicsBackend: String? = nil
    ) throws -> URL {
        let displayName = displayName ?? containerName
        let launchTicket = try ArclumeWineStopService.launchTicket()
        progress?(0.01, "正在检查内置 Wine…")
        let runtimeURL = try preparedRuntimeURL ?? WineRuntimeProvider.ensureRuntime(for: targetPrefixURL)
        try WineMonoSupport.ensureAvailable(runtimeURL: runtimeURL)
        if FileManager.default.fileExists(atPath: targetPrefixURL.path) {
            guard isValidPrefix(at: targetPrefixURL) else {
                throw BundledWineRuntimeError.invalidPrefix
            }
            progress?(1, "内置 Wine 与 \(displayName) 容器已就绪")
            return targetPrefixURL
        }

        let fileManager = FileManager.default
        let prefixParentURL = targetPrefixURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: prefixParentURL, withIntermediateDirectories: true)
        let stagingPrefixURL = prefixParentURL.appendingPathComponent(
            ".\(containerName)-initializing-\(UUID().uuidString)",
            isDirectory: true
        )
        var preserveStaging = false
        defer { if !preserveStaging { try? fileManager.removeItem(at: stagingPrefixURL) } }

        progress?(0.66, "正在准备图形后端和 Wine 环境…")
        let graphicsBackend = graphicsBackend.map {
            OnlineGameMode.resolvedGraphicsBackend($0, supportingD3DMetal4: OnlineGameMode.supportsD3DMetal4)
        } ?? OnlineGameMode.defaultGraphicsBackend
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
        // Input diagnostics are opt-in even for Debug builds. Restrict this
        // to IME and clipboard channels: broad server/SEH tracing can grow to
        // several gigabytes during a normal game session.
        if verboseWineTraceRequested {
            environment["WINEDEBUG"] = "-all,+timestamp,+pid,+tid,+imm,+clipboard"
        }

        progress?(0.74, "正在创建独立的 \(displayName) 容器…")
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
            try ArclumeWineStopService.withLaunchTicket(launchTicket) { try process.run() }
        } catch {
            try? writePrefixInitializationLog(
                "无法启动 wineboot：\(error.localizedDescription)",
                to: initializationLogHandle
            )
            throw error
        }
        if let initializationTimeout {
            guard ContainerInitializationProcess.wait(process, timeout: initializationTimeout) else {
                // Retain only this new staging prefix if asynchronous Wine
                // workers are still winding down. Never clean a live prefix.
                preserveStaging = true
                if let serverPath = environment["WINESERVER"] {
                    let server = Process()
                    server.executableURL = URL(fileURLWithPath: serverPath)
                    server.arguments = ["-k"]
                    server.environment = environment // WINEPREFIX scopes -k to staging.
                    server.standardOutput = initializationLogHandle
                    server.standardError = initializationLogHandle
                    if (try? server.run()) != nil { _ = ContainerInitializationProcess.wait(server, timeout: 5) }
                }
                throw ManagedContainerError.initializationTimedOut
            }
        } else { process.waitUntilExit() }
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
            try fileManager.moveItem(at: stagingPrefixURL, to: targetPrefixURL)
            progress?(1, "内置 Wine 与 \(displayName) 容器已准备完成")
            return targetPrefixURL
        }
        if process.terminationReason == .uncaughtSignal {
            copyRecentWineCrashReports(to: initializationLogHandle)
        }
        throw BundledWineRuntimeError.prefixInitializationFailed(process.terminationStatus)
    }

    nonisolated static func makeLaunchConfiguration(options: GameOptions, prefix: URL? = nil) throws -> LaunchConfiguration {
        let runtimeURL = try WineRuntimeProvider.ensureRuntime(for: prefix ?? prefixURL)
        let graphicsBackend = OnlineGameMode.resolvedGraphicsBackend(
            options.cxGraphicsBackend,
            supportingD3DMetal4: OnlineGameMode.supportsD3DMetal4
        )
        let configuration = try makeLaunchConfiguration(
            runtimeURL: runtimeURL,
            graphicsBackend: graphicsBackend,
            d3dMetal4Enabled: graphicsBackend == "d3dmetal4",
            mtlHudEnabled: options.mtlHudEnabled,
            wineMSync: options.wineMSync
        )
        var environment = configuration.environment
        if graphicsBackend == "dxmt" {
            var settings: [String] = []
            if options.dxmtPreferredMaxFrameRate.isFinite, options.dxmtPreferredMaxFrameRate > 20 {
                settings.append("d3d11.preferredMaxFrameRate=\(options.dxmtPreferredMaxFrameRate)")
            }
            environment["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = options.dxmtMetalFXSpatial ? "1" : "0"
            if options.dxmtMetalFXSpatial, options.dxmtMetalSpatialUpscaleFactor.isFinite {
                settings.append("d3d11.metalSpatialUpscaleFactor=\(options.dxmtMetalSpatialUpscaleFactor)")
            }
            environment["DXMT_CONFIG"] = settings.joined(separator: ";")
        }
        return LaunchConfiguration(wineURL: configuration.wineURL, runtimeURL: configuration.runtimeURL, environment: environment)
    }

    nonisolated static func makeDefaultLaunchConfiguration(prefix: URL? = nil) throws -> LaunchConfiguration {
        let runtimeURL = try WineRuntimeProvider.ensureRuntime(for: prefix ?? prefixURL)
        let graphicsBackend = OnlineGameMode.defaultGraphicsBackend
        return try makeLaunchConfiguration(
            runtimeURL: runtimeURL,
            graphicsBackend: graphicsBackend,
            d3dMetal4Enabled: graphicsBackend == "d3dmetal4",
            mtlHudEnabled: false,
            wineMSync: true
        )
    }

    nonisolated static func makeLaunchConfiguration(
        runtimeURL: URL,
        graphicsBackend: String,
        d3dMetal4Enabled: Bool,
        mtlHudEnabled: Bool,
        wineMSync: Bool,
        graphicsRoot: URL? = nil
    ) throws -> LaunchConfiguration {
        guard graphicsBackend == "dxmt" || OnlineGameMode.supportsD3DMetal4 else {
            throw BundledWineRuntimeError.unsupportedD3DMetal4
        }
        guard isCurrentRuntime(at: runtimeURL) else {
            throw BundledWineRuntimeError.invalidRuntime
        }
        if runtimeURL == NefinitaRuntime.installationURL && !graphicsBackend.contains("d3dmetal") {
            throw NefinitaBuildError.failed("Nefinita 当前仅接入 D3DMetal 图形后端，请在运行设置中选择 D3DMetal")
        }

        let usesDXMT = graphicsBackend == "dxmt"
        let resource = usesDXMT ? "dxmt" : "d3dMetal4"
        guard let graphicsRootURL = try graphicsRoot ?? BundledOnlineGameResources.bundledURL(
            named: resource
        ) else {
            throw BundledOnlineGameResourceError.missingResource(
                usesDXMT ? BundledOnlineGameResources.dxmtArchiveName
                    : BundledOnlineGameResources.d3dMetalArchiveName(version: "4")
            )
        }
        let graphicsWineURL = usesDXMT ? graphicsRootURL
            : graphicsRootURL.appendingPathComponent("wine", isDirectory: true)
        if usesDXMT {
            try BundledOnlineGameResources.validateDXMT(at: graphicsRootURL)
            try installDXMTModules(from: graphicsRootURL, into: runtimeURL)
        } else {
            let shared = graphicsRootURL.appendingPathComponent("external/libd3dshared.dylib")
            guard FileManager.default.fileExists(atPath: shared.path) else {
                throw BundledOnlineGameResourceError.invalidArchive(resource)
            }
            try BundledOnlineGameResources.validateD3DMetalVersion(at: graphicsRootURL)
            try installD3DMetalModules(from: graphicsWineURL, into: runtimeURL, version: "4")
        }

        var environment = ProcessInfo.processInfo.environment
        WineMonoSupport.applyEnvironment(to: &environment)
        environment["WINEDATADIR"] = runtimeURL.appendingPathComponent("share/wine").path
        environment["WINESERVER"] = runtimeURL.appendingPathComponent("bin/wineserver").path
        if runtimeURL == NefinitaRuntime.installationURL {
            environment["GST_PLUGIN_SYSTEM_PATH_1_0"] = runtimeURL.appendingPathComponent("lib/gstreamer-1.0").path
            environment["GST_PLUGIN_PATH_1_0"] = runtimeURL.appendingPathComponent("lib/gstreamer-1.0").path
        }
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
        environment = GameAdaptationRules.processEnvironment(environment)
        environment["MTL_HUD_ENABLED"] = mtlHudEnabled ? "1" : "0"
        environment["__CX_UNIX_MTL_HUD_ENABLED"] = mtlHudEnabled ? "1" : "0"
        OnlineGameBottleConfiguration.applyProcessEnvironment(to: &environment)

        return LaunchConfiguration(
            wineURL: runtimeURL.appendingPathComponent("lib/wine/x86_64-unix/wine"),
            runtimeURL: runtimeURL,
            environment: environment
        )
    }

    /// The Windows and Unix D3DMetal modules are installed into the selected
    /// runtime before launch. WINEDLLPATH therefore points at Wine's own
    /// architecture-specific directories, which is where Wine resolves
    /// built-in `d3d11.dll` and `dxgi.dll`.
    nonisolated static func graphicsRuntimeEnvironment(
        runtimeURL: URL,
        graphicsRootURL: URL,
        graphicsWineURL: URL,
        graphicsBackend: String,
        d3dMetal4Enabled: Bool
    ) -> [String: String] {
        let wineModuleURL = runtimeURL.appendingPathComponent("lib/wine", isDirectory: true)
        let usesD3DMetal = graphicsBackend.contains("d3dmetal")
        let activeBackend = usesD3DMetal ? "d3dmetal" : graphicsBackend
        let wineDLLPaths = [
            wineModuleURL.appendingPathComponent("x86_64-windows").path,
            wineModuleURL.appendingPathComponent("i386-windows").path,
            wineModuleURL.path
        ]
        let fallbackLibraries = usesD3DMetal
            ? [
                graphicsRootURL.appendingPathComponent("external").path,
                graphicsRootURL.path,
                runtimeURL.appendingPathComponent("lib64").path
            ]
            : [runtimeURL.appendingPathComponent("lib64").path]

        return [
            "WINEDLLPATH": wineDLLPaths.joined(separator: ":"),
            "PROCYON_DLL_PATH": usesD3DMetal || graphicsBackend == "dxmt" ? graphicsWineURL.path : "",
            // Mirrors CrossOver's explicit GPTK dependency handoff.
            "CX_APPLEGPTK_LIBD3DSHARED_PATH": usesD3DMetal
                ? graphicsRootURL.appendingPathComponent("external/libd3dshared.dylib").path
                : "",
            // GPTK 4's libd3dshared chooses its framework through this
            // explicit path before falling back to the system framework
            // location. The bundled framework is intentionally outside the
            // runtime module directory, so it must be handed off directly.
            "D3DMETAL_FRAMEWORK_PATH": usesD3DMetal
                ? graphicsRootURL.appendingPathComponent(
                    "external/D3DMetal.framework/D3DMetal"
                ).path
                : "",
            // d3d11.so/dxgi.so also resolve libd3dshared.dylib from this directory.
            "DYLD_FALLBACK_LIBRARY_PATH": fallbackLibraries.joined(separator: ":"),
            "CX_GRAPHICS_BACKEND": activeBackend,
            // CrossOver normally derives this through cxcompatdb. The bundled
            // runtime launches Wine directly, so provide the final value.
            "CX_ACTIVE_GRAPHICS_BACKEND": activeBackend,
            // Beta 3 enables its Metal 4 backend on macOS 27 and later.
            // The same D3DMetal 4 component uses its Metal 3 backend on macOS 26.
            "D3DM_MTL4": d3dMetal4Enabled && ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
            ) ? "1" : "0",
            "D3DM_ENABLE_METALFX": "1",
            "DXMT_ENABLE_NVEXT": "1",
            "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "1",
            "MVK_CONFIG_LOG_LEVEL": "0"
        ]
    }

    /// Wine's built-in module resolver selects files from `lib/wine`, even
    /// when WINEDLLPATH names a separate archive. Install the D3DMetal module
    /// pair atomically into the disposable runtime instead of copying either
    /// the Games prefix or any game resource.
    nonisolated static func installD3DMetalModules(
        from graphicsWineURL: URL,
        into runtimeURL: URL,
        version: String
    ) throws {
        try installGraphicsModules(from: graphicsWineURL, into: runtimeURL, backend: "d3dmetal\(version)")
    }

    nonisolated static func installDXMTModules(from root: URL, into runtime: URL) throws {
        try BundledOnlineGameResources.validateDXMT(at: root)
        try installGraphicsModules(from: root, into: runtime, backend: "dxmt-\(BundledOnlineGameResources.dxmtVersion)")
    }

    nonisolated private static func installGraphicsModules(
        from graphicsWineURL: URL, into runtimeURL: URL, backend: String
    ) throws {
        graphicsModuleInstallationLock.lock()
        defer { graphicsModuleInstallationLock.unlock() }

        let fileManager = FileManager.default
        var modulePairs: [(source: URL, sourceContent: URL, destination: URL, isSymbolicLink: Bool)] = []
        let usesDXMT = backend.hasPrefix("dxmt-")
        let directories = usesDXMT ? graphicsModuleDirectoryNames + ["i386-windows"] : graphicsModuleDirectoryNames
        for directoryName in directories {
            let sourceDirectoryURL = graphicsWineURL.appendingPathComponent(
                directoryName,
                isDirectory: true
            )
            let destinationDirectoryURL = runtimeURL.appendingPathComponent(
                "lib/wine/\(directoryName)",
                isDirectory: true
            )
            guard fileManager.fileExists(atPath: sourceDirectoryURL.path),
                  fileManager.fileExists(atPath: destinationDirectoryURL.path)
            else {
                throw BundledOnlineGameResourceError.invalidArchive(backend)
            }

            let sourceURLs = try fileManager.contentsOfDirectory(
                at: sourceDirectoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            let moduleSources = sourceURLs.compactMap { sourceURL -> (source: URL, content: URL, isSymbolicLink: Bool)? in
                guard let values = try? sourceURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                ), values.isRegularFile == true || values.isSymbolicLink == true
                else {
                    return nil
                }

                // Keep one canonical shared library image. Copying the Unix
                // links as separate binaries breaks CrossOver's ABI dispatch.
                let contentURL = values.isSymbolicLink == true
                    ? sourceURL.resolvingSymlinksInPath()
                    : sourceURL
                guard (try? contentURL.resourceValues(
                    forKeys: [.isRegularFileKey]
                ).isRegularFile) == true else {
                    return nil
                }
                return (sourceURL, contentURL, values.isSymbolicLink == true)
            }
            guard !moduleSources.isEmpty else {
                throw BundledOnlineGameResourceError.invalidArchive(backend)
            }
            modulePairs += moduleSources.map { source in
                (
                    source: source.source,
                    sourceContent: source.content,
                    destination: destinationDirectoryURL.appendingPathComponent(
                        source.source.lastPathComponent
                    ),
                    isSymbolicLink: source.isSymbolicLink
                )
            }
        }

        let requiredModuleNames: Set<String> = usesDXMT
            ? ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll", "winemetal.so"]
            : [
            "d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll",
            "d3d11.so", "d3d12.so", "d3d12core.so", "dxgi.so"
        ]
        guard requiredModuleNames.isSubset(of: Set(modulePairs.map { $0.source.lastPathComponent })) else {
            throw BundledOnlineGameResourceError.invalidArchive(backend)
        }

        let markerURL = runtimeURL.appendingPathComponent(graphicsModuleMarkerFileName)
        let expectedMarker = "\(backend)\n"
        let ownershipURL = runtimeURL.appendingPathComponent(".arclume-graphics-modules.json")
        let oldOwnership = try? Data(contentsOf: ownershipURL)
        let oldMarker = try? Data(contentsOf: markerURL)
        let previousPaths: [String]
        if FileManager.default.fileExists(atPath: ownershipURL.path) {
            previousPaths = try JSONDecoder().decode([String].self, from: Data(contentsOf: ownershipURL))
        } else {
            previousPaths = []
        }
        guard previousPaths.allSatisfy({ relative in
            let parts = relative.split(separator: "/")
            return parts.count == 2 && (graphicsModuleDirectoryNames + ["i386-windows"]).contains(String(parts[0]))
                && parts[1] != "." && parts[1] != ".."
        }) else { throw BundledOnlineGameResourceError.invalidArchive(backend) }
        let relativePath: (URL) -> String = { "\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" }
        let installedPaths = Set(modulePairs.map { relativePath($0.source) })
        // DXMT talks to Metal through winemetal. Remove stale GPTK Unix
        // dispatch modules even for installations created before ownership tracking.
        let disabledPaths = usesDXMT
            ? Set(["d3d11", "dxgi", "d3d10core"].map { "x86_64-unix/\($0).so" })
            : Set<String>()
        let desiredPaths = installedPaths.union(disabledPaths)
        let modulesMatch = {
            modulePairs.allSatisfy { pair in
                if pair.isSymbolicLink {
                    return (try? fileManager.attributesOfItem(atPath: pair.destination.path)[.type])
                        as? FileAttributeType == .typeSymbolicLink
                        && pair.destination.resolvingSymlinksInPath() == pair.sourceContent
                }
                return fileManager.contentsEqual(
                    atPath: pair.sourceContent.path, andPath: pair.destination.path
                )
            }
        }
        if (try? String(contentsOf: markerURL, encoding: .utf8)) == expectedMarker,
           modulesMatch(),
           Set(previousPaths) == desiredPaths,
           disabledPaths.allSatisfy({ relative in
               (try? fileManager.attributesOfItem(atPath: runtimeURL.appendingPathComponent("lib/wine/\(relative)").path)) == nil
           }) {
            return
        }

        guard try !graphicsModulesAreInUse(runtimeURL: runtimeURL) else {
            throw ResourceDownloadError.busyRuntime
        }

        let stagingURL = runtimeURL.appendingPathComponent(
            ".arclume-graphics-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        let originals = runtimeURL.appendingPathComponent(".arclume-graphics-originals", isDirectory: true)
        let affectedPaths = Set(previousPaths).union(desiredPaths)
        for relative in affectedPaths.sorted() {
            let destination = runtimeURL.appendingPathComponent("lib/wine/\(relative)")
            let original = originals.appendingPathComponent(relative)
            let absent = originals.appendingPathComponent(relative + ".absent")
            try fileManager.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fileManager.attributesOfItem(atPath: original.path)) == nil,
               !fileManager.fileExists(atPath: absent.path) {
                if (try? fileManager.attributesOfItem(atPath: destination.path)) != nil {
                    try fileManager.copyItem(at: destination, to: original)
                } else {
                    try Data().write(to: absent, options: .atomic)
                }
            }
        }
        for pair in modulePairs {
            let relativeDirectory = pair.source.deletingLastPathComponent().lastPathComponent
            let stagedDirectoryURL = stagingURL.appendingPathComponent(relativeDirectory, isDirectory: true)
            try fileManager.createDirectory(at: stagedDirectoryURL, withIntermediateDirectories: true)
            let stagedModule = stagedDirectoryURL.appendingPathComponent(pair.source.lastPathComponent)
            if pair.isSymbolicLink {
                try fileManager.createSymbolicLink(at: stagedModule, withDestinationURL: pair.sourceContent)
            } else {
                try fileManager.copyItem(at: pair.sourceContent, to: stagedModule)
            }
        }

        // Restore modules owned only by the previous backend from their original
        // runtime files, including d3d10core, winemetal and 32-bit DXMT modules.
        var replacements = installedPaths
        for relative in Set(previousPaths).subtracting(desiredPaths) {
            let original = originals.appendingPathComponent(relative)
            if (try? fileManager.attributesOfItem(atPath: original.path)) != nil {
                let staged = stagingURL.appendingPathComponent(relative)
                try fileManager.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: original, to: staged)
                replacements.insert(relative)
            }
        }
        let rollback = stagingURL.appendingPathComponent("rollback")
        try fileManager.createDirectory(at: rollback, withIntermediateDirectories: true)
        var applied: [String] = []
        do {
            for relative in affectedPaths.sorted() {
                let destination = runtimeURL.appendingPathComponent("lib/wine/\(relative)")
                let stagedURL = stagingURL.appendingPathComponent(relative)
                let previous = rollback.appendingPathComponent(relative)
                if (try? fileManager.attributesOfItem(atPath: destination.path)) != nil {
                    try fileManager.createDirectory(at: previous.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: destination, to: previous)
                }
                applied.append(relative)
                if !replacements.contains(relative) {
                    if (try? fileManager.attributesOfItem(atPath: destination.path)) != nil {
                        try fileManager.removeItem(at: destination)
                    }
                    continue
                }
                // POSIX rename replaces the link itself instead of following it.
                // Staging is on the runtime volume, so each module replacement is atomic.
                guard Darwin.rename(stagedURL.path, destination.path) == 0 else {
                    throw NSError(
                        domain: NSPOSIXErrorDomain, code: Int(errno),
                        userInfo: [NSFilePathErrorKey: destination.path]
                    )
                }
            }
            guard modulesMatch() else { throw BundledOnlineGameResourceError.invalidArchive(backend) }
            try JSONEncoder().encode(desiredPaths.sorted()).write(to: ownershipURL, options: .atomic)
            try expectedMarker.write(to: markerURL, atomically: true, encoding: .utf8)
        } catch {
            for relative in applied.reversed() {
                let destination = runtimeURL.appendingPathComponent("lib/wine/\(relative)")
                let previous = rollback.appendingPathComponent(relative)
                if (try? fileManager.attributesOfItem(atPath: previous.path)) != nil {
                    _ = Darwin.rename(previous.path, destination.path)
                } else {
                    try? fileManager.removeItem(at: destination)
                }
            }
            if let oldOwnership { try? oldOwnership.write(to: ownershipURL, options: .atomic) }
            else { try? fileManager.removeItem(at: ownershipURL) }
            if let oldMarker { try? oldMarker.write(to: markerURL, options: .atomic) }
            else { try? fileManager.removeItem(at: markerURL) }
            throw error
        }
    }

    /// Wine's idle services and keepalive client do not hold graphics modules.
    /// Only a client already mapping a replaced D3D/Metal module prevents a switch.
    nonisolated private static func graphicsModulesAreInUse(runtimeURL: URL) throws -> Bool {
        let root = runtimeURL.resolvingSymlinksInPath().standardizedFileURL.path
        let clients = try ArclumeWineStopService.snapshot(root: root)
        guard !clients.isEmpty else { return false }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Arclume-GraphicsScan-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ArclumeWineStopService.StopError.enumerationFailed
        }
        defer { try? FileManager.default.removeItem(at: output) }
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-n", "-P", "-a", "-p", clients.map { String($0.pid) }.joined(separator: ","), "-d", "txt", "-Fpn"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = file
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        guard ContainerInitializationProcess.wait(process, timeout: 3),
              process.terminationReason == .exit, process.terminationStatus == 0 || process.terminationStatus == 1,
              (try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8 * 1024 * 1024
        else { throw ArclumeWineStopService.StopError.enumerationFailed }
        let loaded = graphicsModulePIDs(try String(contentsOf: output, encoding: .utf8))
        return clients.contains { loaded.contains($0.pid) && ArclumeWineStopService.readIdentity($0.pid) == $0 }
    }

    nonisolated static func graphicsModulePIDs(_ output: String) -> Set<Int32> {
        let modules: Set<String> = [
            "d3d10core.dll", "d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll", "winemetal.dll",
            "d3d11.so", "d3d12.so", "d3d12core.so", "dxgi.so", "winemetal.so",
            "nvapi64.dll", "nvngx.dll", "libd3dshared.dylib", "d3dmetal"
        ]
        var pid: Int32?
        var loaded = Set<Int32>()
        for line in output.split(separator: "\n") {
            if line.first == "p" { pid = Int32(line.dropFirst()) }
            if line.first == "n", let pid,
               modules.contains(URL(fileURLWithPath: String(line.dropFirst())).lastPathComponent.lowercased()) {
                loaded.insert(pid)
            }
        }
        return loaded
    }

    nonisolated private static func requiredRuntimeManifest() throws -> ArclumeRuntimeManifest {
        do {
            return try ArclumeRuntimeManifest.load()
        } catch ArclumeRuntimeManifestError.missing {
            throw BundledWineRuntimeError.missingManifest
        }
    }

    /// Retain existing users' already-extracted Wine 11 runtime when it is
    /// exactly the final legacy build we shipped. This is a rename within the
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
        upgradeLogger.notice("Legacy runtime adoption: root=\(legacyURL.lastPathComponent, privacy: .public) targetMarker=\(manifest.version, privacy: .public); existing binaries will be reused")

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
            "CX_APPLEGPTK_LIBD3DSHARED_PATH",
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

    /// Focused Wine input tracing is intentionally an internal, explicit
    /// opt-in. It records only IME and clipboard driver activity.
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
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        try? writePrefixInitializationLog("App：\(appVersion) (\(appBuild)) / \(buildFlavor)；运行时清单：\(runtimeVersion)；已安装标记：\(installedRuntimeVersion(at: runtimeURL) ?? "missing")", to: handle)
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
            "CX_APPLEGPTK_LIBD3DSHARED_PATH",
            "DYLD_FALLBACK_LIBRARY_PATH",
            "WINEDEBUG",
            "WINEMSYNC",
            "CX_GRAPHICS_BACKEND",
            "CX_ACTIVE_GRAPHICS_BACKEND",
            "D3DM_MTL4",
            "ROSETTA_ADVERTISE_AVX",
            "MTL_HUD_ENABLED",
            "__CX_UNIX_MTL_HUD_ENABLED"
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
            label: "当前诊断进程是否经 Rosetta 转译（不是 Rosetta 安装状态）",
            to: handle
        )
        appendDiagnosticCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/arch"),
            arguments: ["-x86_64", "/usr/bin/uname", "-m"],
            label: "x86_64 执行能力检查（不启动 Wine）",
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
    /// flush; copy any matching recent report beside the Wine launch log.
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
