//
//  BundledWineRuntime.swift
//  Procyon
//

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
        case .bundledWine: "Procyon+ Wine（Beta）"
        }
    }

    static let launcherRuntimeOptions: DropdownOptions = Self.allCases.map {
        (id: $0.rawValue, label: $0.launcherTitle)
    }

    var detail: String {
        switch self {
        case .crossOver:
            "使用你选择的 CrossOver.app；Procyon 只为它配置随 App 附带的依赖。"
        case .bundledWine:
            "使用 Procyon 内置的自编译 Wine，首次会解压到应用支持目录并建立独立 Games 容器。"
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
    case missingVersionMarker
    case invalidRuntime
    case runtimeVersionMismatch(String?)
    case invalidPrefix
    case extractionFailed(Int32)
    case prefixInitializationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingArchive:
            "App 内未找到自编译 Wine 运行时归档。"
        case .missingVersionMarker:
            "App 内未找到内置 Wine 运行时版本标记。"
        case .invalidRuntime:
            "内置 Wine 运行时不完整，无法启动。"
        case .runtimeVersionMismatch(let installedVersion):
            if let installedVersion {
                "内置 Wine 版本 \(installedVersion) 与当前 App 不匹配。"
            } else {
                "内置 Wine 缺少版本标记，无法确认其是否与当前 App 匹配。"
            }
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
/// the existing versioned archives and is selected through PROCYON_DLL_PATH,
/// so switching D3DMetal 3/4 never mutates this runtime or CrossOver.
enum BundledWineRuntime {
    typealias ProgressHandler = @Sendable (_ fraction: Double, _ label: String) -> Void

    struct LaunchConfiguration {
        let wineURL: URL
        let environment: [String: String]
    }

    nonisolated static let archiveName = "procyon-wine-runtime-x86_64-v8-mono.tar.xz"
    nonisolated static let archiveRootName = "procyon-wine-runtime-x86_64-v8-mono-d3dmetal4-zhcn"
    nonisolated static let versionResourceName = "procyon-wine-runtime-version.txt"
    nonisolated static let versionMarkerFileName = ".procyon-runtime-version"
    nonisolated static let dockApplicationName = "剑网3旗舰版"

    /// Kept outside the disposable staging prefix so a failed first-run can be
    /// diagnosed after the staging directory is cleaned up.
    nonisolated static var prefixInitializationLogURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/Procyon", isDirectory: true)
            .appendingPathComponent("内置 Wine 初始化.log", isDirectory: false)
    }

    private static let installationLock = NSLock()

    nonisolated static var installationURL: URL {
        PROCYON_SUPPORT_FOLDER_URL
            .appendingPathComponent("OnlineGameRuntimes", isDirectory: true)
            .appendingPathComponent(archiveRootName, isDirectory: true)
    }

    nonisolated static var prefixURL: URL {
        PROCYON_SUPPORT_FOLDER_URL
            .appendingPathComponent("OnlineGameWinePrefixes", isDirectory: true)
            .appendingPathComponent(OnlineGameMode.defaultBottleName, isDirectory: true)
    }

    nonisolated static var runtimeVersion: String {
        (try? requiredRuntimeVersion()) ?? "未知版本"
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
        let expected = expectedVersion ?? (try? requiredRuntimeVersion())
        return expected != nil && installedRuntimeVersion(at: runtimeURL) == expected
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
        let expectedVersion = try requiredRuntimeVersion()

        if FileManager.default.fileExists(atPath: installationURL.path) {
            guard isValidRuntime() else { throw BundledWineRuntimeError.invalidRuntime }
            if isCurrentRuntime(expectedVersion: expectedVersion) {
                progress?(1, "内置 Wine \(expectedVersion) 已就绪")
                return installationURL
            }
            progress?(0.05, "正在更新内置 Wine \(expectedVersion)…")
        }

        guard let archiveURL = BundledOnlineGameResources.resourceURL(named: archiveName) else {
            throw BundledWineRuntimeError.missingArchive
        }

        let fileManager = FileManager.default
        let parentURL = installationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        progress?(0.06, "正在分析 Wine 运行时归档…")
        let archiveEntryCount = try archiveEntryCount(in: archiveURL)

        let stagingURL = parentURL.appendingPathComponent(
            ".\(archiveRootName)-\(UUID().uuidString)",
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
            archiveRootName,
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
        let configuration = try makeLaunchConfiguration(
            runtimeURL: runtimeURL,
            graphicsBackend: OnlineGameMode.defaultGraphicsBackend,
            d3dMetal4Enabled: true,
            mtlHudEnabled: false,
            wineMSync: true
        )
        var environment = configuration.environment
        environment["WINEPREFIX"] = stagingPrefixURL.path
        environment["WINEARCH"] = "win64"

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
        environment["WINEDLLPATH"] = runtimeURL.appendingPathComponent("lib/wine").path
        environment["WINESERVER"] = runtimeURL.appendingPathComponent("bin/wineserver").path
        environment["PROCYON_DLL_PATH"] = graphicsWineURL.path
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = [
            graphicsRootURL.path,
            runtimeURL.appendingPathComponent("lib64").path
        ].joined(separator: ":")
        environment["WINEDEBUG"] = "-all"
        environment["WINEMSYNC"] = wineMSync ? "1" : "0"
        environment["CX_GRAPHICS_BACKEND"] = graphicsBackend.contains("d3dmetal")
            ? "d3dmetal"
            : graphicsBackend
        environment["D3DM_MTL4"] = d3dMetal4Enabled ? "1" : "0"
        environment["D3DM_ENABLE_METALFX"] = "1"
        environment["DXMT_ENABLE_NVEXT"] = "1"
        environment["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] = "1"
        environment["MVK_CONFIG_LOG_LEVEL"] = "0"
        environment["ROSETTA_ADVERTISE_AVX"] = "1"
        environment["PROCYON_NO_GPFAULT_ERROR_DIALOG"] = "1"
        environment["PROCYON_WINE_DOCK_NAME"] = dockApplicationName
        environment["WINEPRELOADERAPPNAME"] = dockApplicationName
        environment["MTL_HUD_ENABLED"] = mtlHudEnabled ? "1" : "0"
        environment["__CX_UNIX_MTL_HUD_ENABLED"] = mtlHudEnabled ? "1" : "0"
        OnlineGameBottleConfiguration.applyProcessEnvironment(to: &environment)

        return LaunchConfiguration(
            wineURL: runtimeURL.appendingPathComponent("lib/wine/x86_64-unix/wine"),
            environment: environment
        )
    }

    nonisolated private static func requiredRuntimeVersion() throws -> String {
        guard let versionURL = BundledOnlineGameResources.resourceURL(
            named: versionResourceName
        ), let value = try? String(contentsOf: versionURL, encoding: .utf8)
        else {
            throw BundledWineRuntimeError.missingVersionMarker
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw BundledWineRuntimeError.missingVersionMarker
        }
        return normalized
    }

    nonisolated private static func resetPrefixInitializationLog(
        runtimeURL: URL,
        stagingPrefixURL: URL,
        environment: [String: String]
    ) throws -> FileHandle {
        let fileManager = FileManager.default
        let logURL = prefixInitializationLogURL
        try fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: logURL, options: .atomic)
        let handle = try FileHandle(forWritingTo: logURL)
        try writePrefixInitializationLog("Procyon 内置 Wine 前缀初始化诊断", to: handle)
        try writePrefixInitializationLog("时间：\(ISO8601DateFormatter().string(from: Date()))", to: handle)
        try writePrefixInitializationLog("macOS：\(ProcessInfo.processInfo.operatingSystemVersionString)", to: handle)
        try writePrefixInitializationLog("运行时：\(runtimeURL.path)", to: handle)
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
        handle.synchronizeFile()
        return handle
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
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: installationURL.path) else {
            try fileManager.moveItem(at: extractedRuntimeURL, to: installationURL)
            return
        }

        let previousRuntimeURL = installationURL.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(archiveRootName)-previous-\(UUID().uuidString)",
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
