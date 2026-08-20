//
//  OnlineGameLauncher.swift
//  Procyon
//

import Darwin
import Foundation

enum JX3RuntimeActivityState: Equatable, Sendable {
    case idle
    case launching
    case launcherRunning
    case gameRunning

    var title: String {
        switch self {
        case .idle: "未运行"
        case .launching: "正在启动剑网3启动器"
        case .launcherRunning: "剑网3启动器正在运行"
        case .gameRunning: "剑网3游戏本体正在运行"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "circle"
        case .launching: "hourglass"
        case .launcherRunning: "rectangle.and.text.magnifyingglass"
        case .gameRunning: "gamecontroller.fill"
        }
    }
}

struct JX3RuntimeActivity: Equatable, Sendable {
    let launcherProcessIdentifiers: [Int32]
    let gameProcessIdentifiers: [Int32]
    let rootProcessIsRunning: Bool
    let clientLaunchObservedInLog: Bool

    static let idle = JX3RuntimeActivity(
        launcherProcessIdentifiers: [],
        gameProcessIdentifiers: [],
        rootProcessIsRunning: false,
        clientLaunchObservedInLog: false
    )

    var state: JX3RuntimeActivityState {
        if !gameProcessIdentifiers.isEmpty || clientLaunchObservedInLog {
            return .gameRunning
        }
        if !launcherProcessIdentifiers.isEmpty {
            return .launcherRunning
        }
        return rootProcessIsRunning ? .launching : .idle
    }

    var hasLiveWindowsProcess: Bool {
        !launcherProcessIdentifiers.isEmpty || !gameProcessIdentifiers.isEmpty
    }
}

struct OnlineGameLaunchSession: Sendable {
    let processIdentifier: Int32
    let logURL: URL
    let bottleURL: URL
    let runtime: OnlineGameRuntimeKind
    let crossOverAppPath: String?
    let closeLauncherWhenGameStarts: Bool
}

enum OnlineGameInitialConfiguration {
    struct INIUpdate: Sendable {
        let section: String
        let key: String
        let value: String
    }

    private actor PollingRegistry {
        private var activeBottlePaths = Set<String>()

        func claim(_ path: String) -> Bool {
            activeBottlePaths.insert(path).inserted
        }

        func release(_ path: String) {
            activeBottlePaths.remove(path)
        }
    }

    private struct Target: Sendable {
        let url: URL
        let section: String
        let key: String
        let value: String
    }

    private static let defaultPollInterval: Duration = .seconds(2)
    private static let maximumPollAttempts = 900 // 30 minutes while the game downloads
    private static let pollingRegistry = PollingRegistry()

    /// The launcher creates these files while the game is being downloaded.
    /// Re-running this is safe: the same Bottle is only polled once at a time,
    /// and a new Procyon+ process can start a fresh repair after a game update.
    static func startPolling(
        for bottleURL: URL,
        interval: Duration = defaultPollInterval
    ) {
        let bottlePath = bottleURL.standardizedFileURL.path
        Task(priority: .utility) {
            guard await pollingRegistry.claim(bottlePath) else { return }
            await poll(for: targets(in: bottleURL), interval: interval)
            await pollingRegistry.release(bottlePath)
        }
    }

    /// Updates one INI key without replacing unrelated settings. Kept internal
    /// so the initialization behavior can be tested without a real Bottle.
    @discardableResult
    nonisolated static func enforceINIValue(
        at url: URL,
        section: String,
        key: String,
        value: String
    ) throws -> Bool {
        try enforceINIValues(
            at: url,
            updates: [INIUpdate(section: section, key: key, value: value)]
        )
    }

    /// Applies a group of changes with one read and one atomic replacement.
    /// This prevents consumers of config.ini from observing a partially written
    /// quality profile while individual settings are being updated.
    @discardableResult
    nonisolated static func enforceINIValues(
        at url: URL,
        updates: [INIUpdate]
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        guard !updates.isEmpty else { return true }

        let data = try Data(contentsOf: url)
        guard var contents = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let newline = contents.contains("\r\n") ? "\r\n" : "\n"
        contents = contents.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = contents.components(separatedBy: "\n")
        var didChange = false

        for update in updates {
            didChange = upsertINIValue(
                in: &lines,
                section: update.section,
                key: update.key,
                value: update.value
            ) || didChange
        }

        guard didChange else { return true }
        try lines.joined(separator: newline).write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        return true
    }

    nonisolated private static func upsertINIValue(
        in lines: inout [String],
        section: String,
        key: String,
        value: String
    ) -> Bool {
        var sectionStart: Int?
        var sectionEnd = lines.count

        for index in lines.indices {
            let trimmed = normalizedLine(lines[index])
            guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else {
                continue
            }

            if sectionStart != nil {
                sectionEnd = index
                break
            }
            if trimmed.dropFirst().dropLast()
                .trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare(section) == .orderedSame {
                sectionStart = index
            }
        }

        if let sectionStart {
            for index in (sectionStart + 1)..<sectionEnd {
                let trimmed = normalizedLine(lines[index])
                guard !trimmed.hasPrefix(";") && !trimmed.hasPrefix("#") else {
                    continue
                }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard let storedKey = parts.first,
                      storedKey.trimmingCharacters(in: .whitespaces)
                          .caseInsensitiveCompare(key) == .orderedSame
                else {
                    continue
                }

                let replacement = "\(key)=\(value)"
                guard lines[index] != replacement else { return false }
                lines[index] = replacement
                return true
            }

            lines.insert("\(key)=\(value)", at: sectionEnd)
            return true
        } else {
            if !lines.isEmpty, !lines[lines.count - 1].isEmpty {
                lines.append("")
            }
            lines.append("[\(section)]")
            lines.append("\(key)=\(value)")
            return true
        }
    }

    /// Applies the user-facing DLSS3 frame-generation switch to the JX3
    /// client configuration. The default value remains DLSS=1; enabling the
    /// beta option changes only this key to DLSS=2.
    @discardableResult
    static func applyDLSSFrameGeneration(
        enabled: Bool,
        in bottleURL: URL
    ) throws -> Bool {
        guard let gameRoot = OnlineGameDiscovery.jx3GameDirectory(in: bottleURL) else {
            return false
        }
        let machineConfig = gameRoot
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("machine_config.ini")

        return try enforceINIValue(
            at: machineConfig,
            section: "Performance",
            key: "DLSS",
            value: enabled ? "2" : "1"
        )
    }

    private static func targets(in bottleURL: URL) -> [Target] {
        guard let gameRoot = OnlineGameDiscovery.jx3GameDirectory(in: bottleURL) else {
            return []
        }

        return [
            Target(
                url: gameRoot.appendingPathComponent("config.ini"),
                section: "Debug",
                key: "SkipVideoCardScoreUpdate",
                value: "1"
            ),
            Target(
                url: gameRoot
                    .appendingPathComponent("config", isDirectory: true)
                    .appendingPathComponent("machine_config.ini"),
                section: "Performance",
                key: "DLSS",
                value: "1"
            )
        ]
    }

    private static func poll(for targets: [Target], interval: Duration) async {
        var pending = targets

        for attempt in 0..<maximumPollAttempts {
            var nextPending: [Target] = []
            for target in pending {
                do {
                    if try enforceINIValue(
                        at: target.url,
                        section: target.section,
                        key: target.key,
                        value: target.value
                    ) {
                        console.log("剑网3初始化配置已确认：\(target.key)=\(target.value)")
                    } else {
                        nextPending.append(target)
                    }
                } catch {
                    nextPending.append(target)
                    console.warn(
                        "剑网3初始化配置暂时无法写入 \(target.url.lastPathComponent)：\(error.localizedDescription)"
                    )
                }
            }

            pending = nextPending
            if pending.isEmpty {
                console.log("剑网3初始化配置轮询完成")
                return
            }
            if attempt + 1 < maximumPollAttempts {
                try? await Task.sleep(for: interval)
            }
        }

        console.warn("剑网3初始化配置轮询超时，未等到全部游戏配置文件")
    }

    nonisolated private static func normalizedLine(_ line: String) -> String {
        line.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
        )
    }
}

enum OnlineGameLauncher {
    private struct ActiveWineProcess {
        let process: Process
        let logURL: URL
        let bottleURL: URL
        let runtime: OnlineGameRuntimeKind
        let crossOverAppPath: String?
        let closeLauncherWhenGameStarts: Bool
    }

    private static let processLock = NSLock()
    private static let runtimePreparationLock = NSLock()
    private static var activeWineProcesses: [Int32: ActiveWineProcess] = [:]
    private static let runtimePreparationDefaultsKey = "online-game-runtime-preparation-v1"

    /// Returns whether a launch initiated by this app is still alive. Wine's
    /// x86_64 loader is not exposed as a normal NSWorkspace application under
    /// Rosetta, so process ownership is a more reliable source of truth than
    /// looking for `SeasunGame.exe` in NSWorkspace.
    static func isActive(_ session: OnlineGameLaunchSession) -> Bool {
        processLock.lock()
        defer { processLock.unlock() }
        return activeWineProcesses[session.processIdentifier]?.process.isRunning == true
    }

    /// Watches both the launcher and the detached game client. Wine's launch
    /// command may exit after it hands the client to wineserver, so the root
    /// Wine process alone is not a valid indication that JX3 has stopped.
    @MainActor
    static func monitor(
        _ session: OnlineGameLaunchSession,
        onUpdate: @escaping @MainActor (JX3RuntimeActivity) -> Void,
        onTermination: @escaping () -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            var lastActivity: JX3RuntimeActivity?
            var consecutiveInactivePolls = 0
            var clientLaunchObservedInLog = false
            var didRequestLauncherClose = false
            var logOffset: UInt64 = 0

            while !Task.isCancelled {
                let previousLogOffset = logOffset
                let logRead = await Task.detached(priority: .utility) {
                    readLaunchLog(from: session.logURL, offset: previousLogOffset)
                }.value
                logOffset = logRead.nextOffset
                if containsClientLaunchSignal(in: logRead.contents) {
                    clientLaunchObservedInLog = true
                }

                let activity = await Task.detached(priority: .utility) {
                    currentJX3Activity(
                        for: session,
                        clientLaunchObservedInLog: clientLaunchObservedInLog
                    )
                }.value
                if activity != lastActivity {
                    onUpdate(activity)
                    lastActivity = activity
                }

                if session.closeLauncherWhenGameStarts,
                   activity.state == .gameRunning,
                   !didRequestLauncherClose {
                    didRequestLauncherClose = true
                    console.log("已检测到 JX3ClientX64.exe，按设置关闭 SeasunGame.exe")
                    await closeJX3Launcher(for: session)
                }

                if activity.hasLiveWindowsProcess || activity.rootProcessIsRunning {
                    consecutiveInactivePolls = 0
                } else {
                    consecutiveInactivePolls += 1
                    // A short gap is normal while Wine hands a detached client
                    // to wineserver. Three polls avoids clearing the UI during
                    // that transition but still reacts promptly after exit.
                    if consecutiveInactivePolls >= 3 {
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            if lastActivity != .idle {
                onUpdate(.idle)
            }
            onTermination()
        }
    }

    @MainActor
    static func monitor(
        _ session: OnlineGameLaunchSession,
        onTermination: @escaping () -> Void
    ) -> Task<Void, Never> {
        monitor(session, onUpdate: { _ in }, onTermination: onTermination)
    }

    private static func activeLaunchSession() -> OnlineGameLaunchSession? {
        processLock.lock()
        defer { processLock.unlock() }

        activeWineProcesses = activeWineProcesses.filter { $0.value.process.isRunning }
        guard let (processIdentifier, activeProcess) = activeWineProcesses.first else {
            return nil
        }
        return OnlineGameLaunchSession(
            processIdentifier: processIdentifier,
            logURL: activeProcess.logURL,
            bottleURL: activeProcess.bottleURL,
            runtime: activeProcess.runtime,
            crossOverAppPath: activeProcess.crossOverAppPath,
            closeLauncherWhenGameStarts: activeProcess.closeLauncherWhenGameStarts
        )
    }

    @discardableResult
    static func launchJX3(
        in bottleURL: URL,
        crossOverAppPath: String?,
        options: GameOptions
    ) async throws -> OnlineGameLaunchSession {
        if let activeSession = activeLaunchSession() {
            console.log("复用已运行的剑网3 Wine 会话（PID \(activeSession.processIdentifier)）")
            return activeSession
        }

        OnlineGameMode.applyDefaultRuntimePreferences(to: options)
        let installation = OnlineGameDiscovery.jx3Installation(in: bottleURL)
        guard let executableURL = installation.preferredLaunchURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        do {
            if try OnlineGameInitialConfiguration.applyDLSSFrameGeneration(
                enabled: options.dlssFrameGenerationEnabled,
                in: bottleURL
            ) {
                let value = options.dlssFrameGenerationEnabled ? "2" : "1"
                console.log("剑网3 DLSS 帧生成配置已设置为 DLSS=\(value)")
            }
        } catch {
            console.warn("剑网3 DLSS 帧生成配置暂时无法写入：\(error.localizedDescription)")
        }
        if try BundledOnlineGameResources.installNVNGX(into: bottleURL) {
            console.log("已将内置 NVNGX DLL 替换到剑网3客户端目录")
        }
        return try launchExecutable(
            executableURL,
            in: bottleURL,
            crossOverAppPath: crossOverAppPath,
            arguments: installation.preferredLaunchArguments,
            options: options,
            currentDirectoryURL: installation.preferredWorkingDirectory,
            closeLauncherWhenGameStarts: options.closeLauncherWhenGameStarts
        )
    }

    static func launchExecutable(
        _ executableURL: URL,
        in bottleURL: URL,
        crossOverAppPath: String?,
        arguments: [String],
        options: GameOptions,
        currentDirectoryURL: URL? = nil,
        closeLauncherWhenGameStarts: Bool = false
    ) throws -> OnlineGameLaunchSession {
        if OnlineGameRuntimeKind.selected() == .bundledWine {
            return try launchBundledWineExecutable(
                executableURL,
                in: bottleURL,
                arguments: arguments,
                options: options,
                currentDirectoryURL: currentDirectoryURL,
                closeLauncherWhenGameStarts: closeLauncherWhenGameStarts
            )
        }
        guard let crossOverAppPath else {
            throw CocoaError(.fileNoSuchFile)
        }
        let crossOverURL = URL(fileURLWithPath: crossOverAppPath)
        let logURL = try makeLaunchLogURL()
        let logHandle = try FileHandle(forWritingTo: logURL)
        let launchStartedAt = Date()

        writeLaunchLog("开始准备 CrossOver 运行时", to: logHandle)
        do {
            let reusedRuntime = try prepareRuntime(
                at: crossOverURL,
                crossOverAppPath: crossOverAppPath,
                options: options
            )
            let elapsed = Date().timeIntervalSince(launchStartedAt)
            let elapsedText = String(format: "%.2f", elapsed)
            writeLaunchLog(
                reusedRuntime
                    ? "复用已准备的运行时（\(elapsedText) 秒）"
                    : "已更新运行时（\(elapsedText) 秒）",
                to: logHandle
            )
        } catch {
            writeLaunchLog("运行时准备失败：\(error.localizedDescription)", to: logHandle)
            logHandle.closeFile()
            throw error
        }

        var environment = ProcessInfo.processInfo.environment
        environment["CX_ROOT"] = crossOverURL
            .appendingPathComponent("Contents/SharedSupport/CrossOver")
            .path
        environment["WINEPREFIX"] = bottleURL.path
        environment["WINEDEBUG"] = "-all"
        environment["WINEMSYNC"] = options.wineMSync ? "1" : "0"
        OnlineGameBottleConfiguration.applyProcessEnvironment(to: &environment)
        try OnlineGameBottleConfiguration.apply(to: bottleURL)
        environment["CX_GRAPHICS_BACKEND"] = options.cxGraphicsBackend.contains("d3dmetal")
            ? "d3dmetal"
            : options.cxGraphicsBackend
        environment["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] = options.mvkArgBuff ? "1" : "0"
        environment["MVK_CONFIG_UE4_HACK_ENABLED"] = options.ue4Hack ? "1" : "0"
        environment["NAS_DISABLE_UE4_HACK"] = options.ue4Hack ? "0" : "1"
        environment["ROSETTA_ADVERTISE_AVX"] = options.advertiseAVX ? "1" : "0"
        environment["D3DM_ENABLE_METALFX"] = "1"
        environment["DXMT_ENABLE_NVEXT"] = "1"
        environment["MVK_CONFIG_LOG_LEVEL"] = "0"
        if options.d3dMtl4Enabled { environment["D3DM_MTL4"] = "1" }
        if options.mtlHudEnabled { environment["MTL_HUD_ENABLED"] = "1" }

        let wineURL = crossOverURL
            .appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
        guard FileManager.default.isExecutableFile(atPath: wineURL.path) else {
            logHandle.closeFile()
            throw CocoaError(.fileNoSuchFile)
        }

        let process = Process()
        process.executableURL = wineURL
        process.arguments = ["--bottle", bottleURL.lastPathComponent, executableURL.path] + arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL ?? executableURL.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()

        let processIdentifier = process.processIdentifier
        writeLaunchLog("Wine 已启动（PID \(processIdentifier)）", to: logHandle)
        processLock.lock()
        activeWineProcesses[processIdentifier] = ActiveWineProcess(
            process: process,
            logURL: logURL,
            bottleURL: bottleURL,
            runtime: .crossOver,
            crossOverAppPath: crossOverAppPath,
            closeLauncherWhenGameStarts: closeLauncherWhenGameStarts
        )
        processLock.unlock()
        process.terminationHandler = { _ in
            writeLaunchLog("Wine 启动命令已退出（状态 \(process.terminationStatus)）", to: logHandle)
            logHandle.closeFile()
            ArclumeGameLogStore.enforceStorageLimit()
            processLock.lock()
            activeWineProcesses.removeValue(forKey: processIdentifier)
            processLock.unlock()
        }

        return OnlineGameLaunchSession(
            processIdentifier: processIdentifier,
            logURL: logURL,
            bottleURL: bottleURL,
            runtime: .crossOver,
            crossOverAppPath: crossOverAppPath,
            closeLauncherWhenGameStarts: closeLauncherWhenGameStarts
        )
    }

    private static func launchBundledWineExecutable(
        _ executableURL: URL,
        in bottleURL: URL,
        arguments: [String],
        options: GameOptions,
        currentDirectoryURL: URL?,
        closeLauncherWhenGameStarts: Bool
    ) throws -> OnlineGameLaunchSession {
        guard BundledWineRuntime.ownsPrefix(bottleURL),
              BundledWineRuntime.isValidPrefix(at: bottleURL)
        else {
            throw BundledWineRuntimeError.invalidPrefix
        }

        let logURL = try makeLaunchLogURL()
        let logHandle = try FileHandle(forWritingTo: logURL)
        writeLaunchLog("开始准备 Arclume 内置 Wine 运行时", to: logHandle)

        let configuration: BundledWineRuntime.LaunchConfiguration
        do {
            configuration = try BundledWineRuntime.makeLaunchConfiguration(options: options)
            try OnlineGameBottleConfiguration.apply(to: bottleURL)
        } catch {
            writeLaunchLog("内置 Wine 运行时准备失败：\(error.localizedDescription)", to: logHandle)
            logHandle.closeFile()
            throw error
        }

        var environment = configuration.environment
        environment["WINEPREFIX"] = bottleURL.path
        // Detailed Wine server tracing is developer-only. Test builds retain
        // their normal launch/crash diagnostics without continuously dumping
        // every Wine server operation into the user log.
        if BundledWineRuntime.verboseWineTraceRequested {
            environment["WINEDEBUG"] = "-all,+timestamp,+pid,+tid,+server,+seh"
        }

        writeLaunchLog(
            "内置 Wine 命令：\(configuration.wineURL.path) \(executableURL.path) \(arguments.joined(separator: " "))",
            to: logHandle
        )
#if DEBUG
        BundledWineRuntime.appendLauncherDiagnostics(
            runtimeURL: configuration.runtimeURL,
            wineURL: configuration.wineURL,
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            to: logHandle
        )
#endif

        let process = Process()
        process.executableURL = configuration.wineURL
        process.arguments = [executableURL.path] + arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL ?? executableURL.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()

        let processIdentifier = process.processIdentifier
        writeLaunchLog("内置 Wine 已启动（PID \(processIdentifier)）", to: logHandle)
        processLock.lock()
        activeWineProcesses[processIdentifier] = ActiveWineProcess(
            process: process,
            logURL: logURL,
            bottleURL: bottleURL,
            runtime: .bundledWine,
            crossOverAppPath: nil,
            closeLauncherWhenGameStarts: closeLauncherWhenGameStarts
        )
        processLock.unlock()
        process.terminationHandler = { terminatedProcess in
            writeLaunchLog(
                "内置 Wine 启动命令已退出（reason \(terminatedProcess.terminationReason)，状态 \(terminatedProcess.terminationStatus)）",
                to: logHandle
            )
            let didCrash = terminatedProcess.terminationReason == .uncaughtSignal
                || terminatedProcess.terminationStatus == 11
                || terminatedProcess.terminationStatus == 139
            let closeLogAndForgetProcess = {
                logHandle.closeFile()
                ArclumeGameLogStore.enforceStorageLimit()
                processLock.lock()
                activeWineProcesses.removeValue(forKey: processIdentifier)
                processLock.unlock()
            }
            if didCrash {
                // ReportCrash runs after the child exits. Give it a short
                // window, then copy the .ips file beside the launch log.
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + 3
                ) {
                    BundledWineRuntime.copyRecentWineCrashReports(to: logHandle)
                    closeLogAndForgetProcess()
                }
                return
            }
            closeLogAndForgetProcess()
        }

        return OnlineGameLaunchSession(
            processIdentifier: processIdentifier,
            logURL: logURL,
            bottleURL: bottleURL,
            runtime: .bundledWine,
            crossOverAppPath: nil,
            closeLauncherWhenGameStarts: closeLauncherWhenGameStarts
        )
    }

    /// Terminates only the two JX3 Windows executables in the selected Games
    /// prefix. This deliberately avoids the old global Wine sweep, which
    /// could also close another game or a user's separately-opened CrossOver.
    static func forceQuitJX3(
        in bottleURL: URL,
        crossOverAppPath: String?
    ) async {
        let runtime = OnlineGameRuntimeKind.selected()
        await Task.detached(priority: .userInitiated) {
            for executableName in [
                OnlineGameMode.jx3LauncherName,
                OnlineGameMode.jx3ClientName
            ] {
                try? requestWindowsTaskKill(
                    executableName,
                    in: bottleURL,
                    runtime: runtime,
                    crossOverAppPath: crossOverAppPath
                )
            }
        }.value

        let session = activeLaunchSession().flatMap {
            $0.bottleURL.standardizedFileURL == bottleURL.standardizedFileURL ? $0 : nil
        }
        let initialActivity = await Task.detached(priority: .utility) {
            currentJX3Activity(for: session, clientLaunchObservedInLog: false)
        }.value
        terminateMacProcesses(
            Set(initialActivity.launcherProcessIdentifiers)
                .union(initialActivity.gameProcessIdentifiers),
            signal: SIGTERM
        )
        if let session {
            terminateTrackedRootProcess(for: session, signal: SIGTERM)
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let remainingActivity = await Task.detached(priority: .utility) {
            currentJX3Activity(for: session, clientLaunchObservedInLog: false)
        }.value
        terminateMacProcesses(
            Set(remainingActivity.launcherProcessIdentifiers)
                .union(remainingActivity.gameProcessIdentifiers),
            signal: SIGKILL
        )
        if let session, remainingActivity.rootProcessIsRunning {
            terminateTrackedRootProcess(for: session, signal: SIGKILL)
        }
    }

    /// Closes only SeasunGame.exe once the actual game client is present.
    /// PIDs that also hold JX3ClientX64.exe are deliberately excluded before
    /// a Unix signal is sent, so the automatic option never kills the client.
    private static func closeJX3Launcher(for session: OnlineGameLaunchSession) async {
        await Task.detached(priority: .utility) {
            try? requestWindowsTaskKill(
                OnlineGameMode.jx3LauncherName,
                in: session.bottleURL,
                runtime: session.runtime,
                crossOverAppPath: session.crossOverAppPath
            )
        }.value

        var activity = await Task.detached(priority: .utility) {
            currentJX3Activity(for: session, clientLaunchObservedInLog: false)
        }.value
        var launcherOnlyPIDs = Set(activity.launcherProcessIdentifiers)
            .subtracting(activity.gameProcessIdentifiers)
        terminateMacProcesses(launcherOnlyPIDs, signal: SIGTERM)

        try? await Task.sleep(nanoseconds: 1_500_000_000)
        activity = await Task.detached(priority: .utility) {
            currentJX3Activity(for: session, clientLaunchObservedInLog: false)
        }.value
        launcherOnlyPIDs = Set(activity.launcherProcessIdentifiers)
            .subtracting(activity.gameProcessIdentifiers)
        terminateMacProcesses(launcherOnlyPIDs, signal: SIGKILL)
    }

    static func classifyJX3Activity(
        processList: String,
        openFiles: String,
        rootProcessIdentifier: Int32?,
        rootProcessIsRunning: Bool,
        clientLaunchObservedInLog: Bool,
        requiredBottlePath: String? = nil
    ) -> JX3RuntimeActivity {
        let processEntries = parseProcessList(processList)
        var launcherPIDs = Set<Int32>()
        var gamePIDs = Set<Int32>()

        for process in processEntries {
            classifyJX3Path(
                process.command,
                processIdentifier: process.processIdentifier,
                launcherPIDs: &launcherPIDs,
                gamePIDs: &gamePIDs,
                requiredBottlePath: requiredBottlePath
            )
        }

        var currentPID: Int32?
        for line in openFiles.split(whereSeparator: \.isNewline) {
            guard let prefix = line.first else { continue }
            switch prefix {
            case "p":
                currentPID = Int32(line.dropFirst())
            case "n":
                guard let currentPID else { continue }
                classifyJX3Path(
                    String(line.dropFirst()),
                    processIdentifier: currentPID,
                    launcherPIDs: &launcherPIDs,
                    gamePIDs: &gamePIDs,
                    requiredBottlePath: requiredBottlePath
                )
            default:
                continue
            }
        }

        // Keep the direct root PID only as a liveness signal. It is never
        // treated as a launcher/client PID unless its command or open files
        // explicitly identify one of the two Windows executables.
        let rootIsRunning = rootProcessIdentifier != nil && rootProcessIsRunning
        return JX3RuntimeActivity(
            launcherProcessIdentifiers: launcherPIDs.sorted(),
            gameProcessIdentifiers: gamePIDs.sorted(),
            rootProcessIsRunning: rootIsRunning,
            clientLaunchObservedInLog: clientLaunchObservedInLog
        )
    }

    static func containsClientLaunchSignal(in logContents: String) -> Bool {
        let lowercased = logContents.lowercased()
        return lowercased.contains("detachprogram(")
            && lowercased.contains(OnlineGameMode.jx3ClientName.lowercased())
    }

    private struct ProcessListEntry: Sendable {
        let processIdentifier: Int32
        let parentProcessIdentifier: Int32
        let command: String
    }

    private struct LaunchLogRead: Sendable {
        let contents: String
        let nextOffset: UInt64
    }

    private static func currentJX3Activity(
        for session: OnlineGameLaunchSession?,
        clientLaunchObservedInLog: Bool
    ) -> JX3RuntimeActivity {
        let processList = processOutput(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,ppid=,command="]
        )
        let rootPID = session?.processIdentifier
        let processIDs = processIDsToInspect(
            from: processList,
            rootProcessIdentifier: rootPID
        )
        let openFiles = lsofOutput(for: processIDs)
        return classifyJX3Activity(
            processList: processList,
            openFiles: openFiles,
            rootProcessIdentifier: rootPID,
            rootProcessIsRunning: session.map(isActive) ?? false,
            clientLaunchObservedInLog: clientLaunchObservedInLog,
            requiredBottlePath: session?.bottleURL.standardizedFileURL.path
        )
    }

    private static func parseProcessList(_ output: String) -> [ProcessListEntry] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(
                maxSplits: 2,
                omittingEmptySubsequences: true,
                whereSeparator: \.isWhitespace
            )
            guard parts.count == 3,
                  let processIdentifier = Int32(parts[0]),
                  let parentProcessIdentifier = Int32(parts[1])
            else {
                return nil
            }
            return ProcessListEntry(
                processIdentifier: processIdentifier,
                parentProcessIdentifier: parentProcessIdentifier,
                command: String(parts[2])
            )
        }
    }

    private static func processIDsToInspect(
        from processList: String,
        rootProcessIdentifier: Int32?
    ) -> Set<Int32> {
        let entries = parseProcessList(processList)
        var descendants = Set(rootProcessIdentifier.map { [$0] } ?? [])
        var foundNewDescendant = true
        while foundNewDescendant {
            foundNewDescendant = false
            for entry in entries where descendants.contains(entry.parentProcessIdentifier) {
                if descendants.insert(entry.processIdentifier).inserted {
                    foundNewDescendant = true
                }
            }
        }

        let knownRuntimeTerms = ["wine", "crossover", "jx3client", "seasungame"]
        for entry in entries {
            let command = entry.command.lowercased()
            if knownRuntimeTerms.contains(where: command.contains) {
                descendants.insert(entry.processIdentifier)
            }
        }
        return descendants
    }

    private static func lsofOutput(for processIdentifiers: Set<Int32>) -> String {
        guard !processIdentifiers.isEmpty else { return "" }
        return processOutput(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: [
                "-n",
                "-Fpn",
                "-p",
                processIdentifiers.sorted().map(String.init).joined(separator: ",")
            ]
        )
    }

    private static func processOutput(
        executableURL: URL,
        arguments: [String]
    ) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    private static func classifyJX3Path(
        _ path: String,
        processIdentifier: Int32,
        launcherPIDs: inout Set<Int32>,
        gamePIDs: inout Set<Int32>,
        requiredBottlePath: String?
    ) {
        let lowercased = path.lowercased()
        if let requiredBottlePath,
           !lowercased.contains(requiredBottlePath.lowercased()) {
            return
        }
        if lowercased.contains(OnlineGameMode.jx3LauncherName.lowercased()) {
            launcherPIDs.insert(processIdentifier)
        }
        if lowercased.contains(OnlineGameMode.jx3ClientName.lowercased()) {
            gamePIDs.insert(processIdentifier)
        }
    }

    private static func readLaunchLog(
        from url: URL,
        offset: UInt64
    ) -> LaunchLogRead {
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = fileAttributes[.size] as? NSNumber
        else {
            return LaunchLogRead(contents: "", nextOffset: offset)
        }
        let totalSize = fileSize.uint64Value
        let startOffset = totalSize >= offset ? offset : 0
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return LaunchLogRead(contents: "", nextOffset: startOffset)
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: startOffset)
            let data = try handle.readToEnd() ?? Data()
            return LaunchLogRead(
                contents: String(decoding: data, as: UTF8.self),
                nextOffset: totalSize
            )
        } catch {
            return LaunchLogRead(contents: "", nextOffset: startOffset)
        }
    }

    private static func requestWindowsTaskKill(
        _ executableName: String,
        in bottleURL: URL,
        runtime: OnlineGameRuntimeKind,
        crossOverAppPath: String?
    ) throws {
        let process = Process()
        var environment = ProcessInfo.processInfo.environment
        switch runtime {
        case .crossOver:
            guard let crossOverAppPath else { return }
            let crossOverURL = URL(fileURLWithPath: crossOverAppPath)
            let wineURL = crossOverURL
                .appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
            guard FileManager.default.isExecutableFile(atPath: wineURL.path) else { return }
            process.executableURL = wineURL
            process.arguments = [
                "--bottle", bottleURL.lastPathComponent,
                "C:\\windows\\system32\\taskkill.exe",
                "/IM", executableName,
                "/T"
            ]
            environment["CX_ROOT"] = crossOverURL
                .appendingPathComponent("Contents/SharedSupport/CrossOver")
                .path
        case .bundledWine:
            let runtimeURL = try BundledWineRuntime.ensureInstalled()
            let wineURL = runtimeURL.appendingPathComponent("lib/wine/x86_64-unix/wine")
            guard FileManager.default.isExecutableFile(atPath: wineURL.path) else { return }
            process.executableURL = wineURL
            process.arguments = [
                "C:\\windows\\system32\\taskkill.exe",
                "/IM", executableName,
                "/T"
            ]
            environment["WINEDATADIR"] = runtimeURL.appendingPathComponent("share/wine").path
            environment["WINEDLLPATH"] = runtimeURL.appendingPathComponent("lib/wine").path
            environment["WINESERVER"] = runtimeURL.appendingPathComponent("bin/wineserver").path
        }
        environment["WINEPREFIX"] = bottleURL.path
        environment["WINEDEBUG"] = "-all"
        process.environment = environment
        process.currentDirectoryURL = bottleURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    private static func terminateMacProcesses(
        _ processIdentifiers: Set<Int32>,
        signal: Int32
    ) {
        for processIdentifier in processIdentifiers where processIdentifier > 1 {
            _ = Darwin.kill(processIdentifier, signal)
        }
    }

    private static func terminateTrackedRootProcess(
        for session: OnlineGameLaunchSession,
        signal: Int32
    ) {
        _ = Darwin.kill(session.processIdentifier, signal)
    }

    /// CrossOver 的 D3DMetal 资源约 63 MB。此前每次点“游玩”都会移除并重拷它们，
    /// 即使图形后端和 MoltenVK 版本没有变化。只在配置、Procyon 资源或 CrossOver 本体变化时更新。
    private static func prepareRuntime(
        at crossOverURL: URL,
        crossOverAppPath: String,
        options: GameOptions
    ) throws -> Bool {
        let d3dMetalVersion = options.cxGraphicsBackend == "d3dmetal4" ? "4" : "3"
        let fingerprint = runtimePreparationFingerprint(
            crossOverURL: crossOverURL,
            d3dMetalVersion: d3dMetalVersion,
            vulkanLibrary: options.vulkanLib
        )

        runtimePreparationLock.lock()
        defer { runtimePreparationLock.unlock() }

        let defaults = UserDefaults.standard
        let destinationRoot = crossOverURL
            .appendingPathComponent(SHARED_SUPPORT_COMPONENT)
            .appendingPathComponent("\(LIB_ROOT)/apple_gptk/external")
        let moltenVKDestination = crossOverURL
            .appendingPathComponent(SHARED_SUPPORT_COMPONENT)
            .appendingPathComponent("\(LIB_ROOT)/libMoltenVK.dylib")
        let runtimeFilesExist = FileManager.default.fileExists(atPath: destinationRoot.path)
            && (options.vulkanLib.isEmpty
                || FileManager.default.fileExists(atPath: moltenVKDestination.path))

        if runtimeFilesExist,
           defaults.string(forKey: runtimePreparationDefaultsKey) == fingerprint {
            return true
        }

        try installd3dMetal(at: crossOverURL, version: d3dMetalVersion)
        if !options.vulkanLib.isEmpty {
            try copyMoltenVK(cxAppPath: crossOverAppPath, vulkanLibID: options.vulkanLib)
        }
        defaults.set(fingerprint, forKey: runtimePreparationDefaultsKey)
        return false
    }

    private static func runtimePreparationFingerprint(
        crossOverURL: URL,
        d3dMetalVersion: String,
        vulkanLibrary: String
    ) -> String {
        let infoPlist = crossOverURL.appendingPathComponent("Contents/Info.plist")
        let d3dMetalResource = BundledOnlineGameResources.resourceURL(
            named: "d3dMetal\(d3dMetalVersion)"
        ) ?? BundledOnlineGameResources.resourceURL(
            named: BundledOnlineGameResources.d3dMetalArchiveName(version: d3dMetalVersion)
        )
        let moltenVKResource = Bundle.main.url(
            forResource: "libMoltenVK-\(vulkanLibrary)",
            withExtension: "dylib"
        )
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return [
            "schema=1",
            "app-build=\(appBuild)",
            "crossover=\(fileSignature(for: infoPlist))",
            "d3dmetal=\(fileSignature(for: d3dMetalResource))",
            "moltenvk=\(fileSignature(for: moltenVKResource))",
            "backend=\(d3dMetalVersion)",
            "vulkan=\(vulkanLibrary)"
        ].joined(separator: "|")
    }

    private static func fileSignature(for url: URL?) -> String {
        guard let url,
              let values = try? url.resourceValues(forKeys: [
                  .fileSizeKey,
                  .contentModificationDateKey
              ])
        else {
            return "missing"
        }
        let date = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.path):\(values.fileSize ?? 0):\(date)"
    }

    private static func writeLaunchLog(_ message: String, to handle: FileHandle) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[Arclume][\(timestamp)] \(message)\n"
        handle.write(Data(line.utf8))
    }

    private static func makeLaunchLogURL() throws -> URL {
        try ArclumeGameLogStore.createLaunchLogURL()
    }
}
