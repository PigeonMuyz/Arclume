//
//  OnlineGameLauncher.swift
//  Arclume
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
        case .launching: "正在启动剑网3"
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
    let executableName: String
    let logURL: URL?
    let bottleURL: URL
    let runtime: OnlineGameRuntimeKind
    let crossOverAppPath: String?
    let closeLauncherWhenGameStarts: Bool
    var installationBottleURL: URL? = nil
}

enum OnlineGameInitialConfiguration {
    struct INIUpdate: Sendable {
        let section: String
        let key: String
        let value: String
        var preservingValues: Set<String> = []
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
        var preservingValues: Set<String> = []
    }

    nonisolated private struct INILine {
        var text: String
        var ending: String
    }

    private static let defaultPollInterval: Duration = .seconds(2)
    private static let defaultPollTimeout: Duration = .seconds(24 * 60 * 60)
    private static let pollingRegistry = PollingRegistry()
    nonisolated private static let iniWriteLock = NSLock()

    /// The launcher creates these files while the game is being downloaded.
    /// Re-running this is safe: the same Bottle is only polled once at a time,
    /// and a new application process can start a fresh repair after a game update.
    @discardableResult
    static func startPolling(
        for bottleURL: URL,
        installation: OnlineGameInstallation? = nil,
        interval: Duration = defaultPollInterval,
        timeout: Duration = defaultPollTimeout
    ) -> Task<Void, Never> {
        let bottlePath = bottleURL.resolvingSymlinksInPath().standardizedFileURL.path
        return Task(priority: .utility) {
            guard await pollingRegistry.claim(bottlePath) else { return }
            await poll(for: bottleURL, installation: installation, interval: interval, timeout: timeout)
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
        value: String,
        preservingValues: Set<String> = []
    ) throws -> Bool {
        try enforceINIValues(
            at: url,
            updates: [INIUpdate(section: section, key: key, value: value, preservingValues: preservingValues)]
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
        iniWriteLock.lock()
        defer { iniWriteLock.unlock() }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        guard !updates.isEmpty else { return true }

        let data = try Data(contentsOf: url)
        guard let document = JX3INIText(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard !document.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let contents = document.contents
        var lines: [INILine] = []
        contents.enumerateSubstrings(in: contents.startIndex..<contents.endIndex, options: .byLines) {
            _, textRange, lineRange, _ in
            lines.append(INILine(
                text: String(contents[textRange]),
                ending: String(contents[textRange.upperBound..<lineRange.upperBound])
            ))
        }
        let newline = lines.first(where: { !$0.ending.isEmpty })?.ending ?? "\n"
        var didChange = false

        for update in updates {
            didChange = upsertINIValue(
                in: &lines,
                update: update,
                newline: newline
            ) || didChange
        }

        guard didChange else { return true }
        let replacement = try document.encode(lines.map { $0.text + $0.ending }.joined())
        // The client can update the file independently of Arclume.
        guard try Data(contentsOf: url) == data else { return false }
        try replacement.write(to: url, options: .atomic)
        return true
    }

    nonisolated private static func upsertINIValue(
        in lines: inout [INILine],
        update: INIUpdate,
        newline: String
    ) -> Bool {
        var sectionStart: Int?
        var sectionEnd = lines.count

        for index in lines.indices {
            let trimmed = lines[index].text.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else {
                continue
            }

            if sectionStart != nil {
                sectionEnd = index
                break
            }
            if trimmed.dropFirst().dropLast()
                .trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare(update.section) == .orderedSame {
                sectionStart = index
            }
        }

        let newEntry = "\(update.key)=\(update.value)"
        if let sectionStart {
            for index in (sectionStart + 1)..<sectionEnd {
                let line = lines[index].text
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix(";") && !trimmed.hasPrefix("#"),
                      let separator = line.firstIndex(of: "="),
                      line[..<separator].trimmingCharacters(in: .whitespaces)
                        .caseInsensitiveCompare(update.key) == .orderedSame
                else {
                    continue
                }
                let storedValue = line[line.index(after: separator)...]
                let trimmedValue = storedValue.trimmingCharacters(in: .whitespaces)
                if trimmedValue == update.value || update.preservingValues.contains(trimmedValue) {
                    return false
                }

                let valueStart = storedValue.firstIndex(where: { !$0.isWhitespace }) ?? storedValue.endIndex
                let valueEnd = storedValue.lastIndex(where: { !$0.isWhitespace })
                    .map { storedValue.index(after: $0) } ?? valueStart
                lines[index].text.replaceSubrange(valueStart..<valueEnd, with: update.value)
                return true
            }

            insertINILines([newEntry], at: sectionEnd, into: &lines, newline: newline)
        } else {
            let padding = lines.last?.text.isEmpty == false ? [""] : []
            insertINILines(padding + ["[\(update.section)]", newEntry], at: lines.count, into: &lines, newline: newline)
        }
        return true
    }

    nonisolated private static func insertINILines(
        _ texts: [String],
        at index: Int,
        into lines: inout [INILine],
        newline: String
    ) {
        let endsWithNewline = lines.last?.ending.isEmpty == false
        let insertingAtEnd = index == lines.endIndex
        if insertingAtEnd && !endsWithNewline && index > lines.startIndex {
            lines[index - 1].ending = newline
        }
        let newLines = texts.enumerated().map { offset, text in
            let needsNewline = !insertingAtEnd || endsWithNewline || offset < texts.count - 1
            return INILine(text: text, ending: needsNewline ? newline : "")
        }
        lines.insert(contentsOf: newLines, at: index)
    }

    /// Repair the required client setting on every fresh launch, not only import.
    /// Never create a partial config before the client has generated its defaults.
    @discardableResult
    nonisolated static func applySkipVideoCardScoreUpdate(
        in bottleURL: URL,
        installation: OnlineGameInstallation? = nil
    ) throws -> Bool {
        guard let gameRoot = OnlineGameDiscovery.jx3GameDirectory(in: bottleURL, installation: installation) else {
            return false
        }
        return try enforceINIValue(
            at: gameRoot.appendingPathComponent("config.ini"),
            section: "Debug",
            key: "SkipVideoCardScoreUpdate",
            value: "1"
        )
    }

    /// Declares DLSS (1) or DLSS + frame-generation (2) capability to the client.
    /// This does not enable upscaling or frame generation in the game's quality settings.
    /// Keep the API/preferences name for compatibility with existing saved options.
    @discardableResult
    nonisolated static func applyDLSSFrameGeneration(
        enabled: Bool,
        in bottleURL: URL,
        installation: OnlineGameInstallation? = nil
    ) throws -> Bool {
        guard let gameRoot = OnlineGameDiscovery.jx3GameDirectory(in: bottleURL, installation: installation) else {
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

    nonisolated private static func targets(in gameRoot: URL) -> [Target] {
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
                value: "1",
                preservingValues: ["1", "2"]
            )
        ]
    }

    @concurrent private static func poll(
        for bottleURL: URL,
        installation: OnlineGameInstallation?,
        interval: Duration,
        timeout: Duration
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var nextDiscovery = clock.now
        var knownInstallation = installation ?? OnlineGameInstallation(clientURL: nil, launcherURL: nil)
        var pending: [Target]?
        var loggedFailures: Set<URL> = []

        while !Task.isCancelled && clock.now < deadline {
            if pending == nil {
                if let gameRoot = OnlineGameDiscovery.jx3GameDirectory(in: bottleURL, installation: knownInstallation) {
                    pending = targets(in: gameRoot)
                } else if clock.now >= nextDiscovery {
                    // The default and launcher-relative paths are cheap to check.
                    // Refresh the filesystem scan less often for custom installs.
                    knownInstallation = OnlineGameDiscovery.jx3Installation(in: bottleURL)
                    if let gameRoot = OnlineGameDiscovery.jx3GameDirectory(in: bottleURL, installation: knownInstallation) {
                        pending = targets(in: gameRoot)
                    }
                    nextDiscovery = clock.now + interval * 15
                }
            }
            var nextPending: [Target] = []
            for target in pending ?? [] {
                do {
                    if try enforceINIValue(
                        at: target.url,
                        section: target.section,
                        key: target.key,
                        value: target.value,
                        preservingValues: target.preservingValues
                    ) {
                        let detail = target.preservingValues.isEmpty
                            ? "\(target.key)=\(target.value)"
                            : "\(target.key)（保留已有能力声明）"
                        await console.log("剑网3初始化配置已确认：\(detail)")
                    } else {
                        nextPending.append(target)
                    }
                } catch {
                    nextPending.append(target)
                    if loggedFailures.insert(target.url).inserted {
                        await console.warn(
                            "剑网3初始化配置暂时无法写入 \(target.url.lastPathComponent)：\(error.localizedDescription)"
                        )
                    }
                }
            }

            if pending != nil {
                guard !nextPending.isEmpty else { return }
                pending = nextPending
            }
            do { try await clock.sleep(until: min(clock.now + interval, deadline)) }
            catch { return }
        }

        if !Task.isCancelled {
            await console.warn("剑网3初始化配置轮询超时，未等到全部游戏配置文件")
        }
    }
}

enum OnlineGameLauncher {
    nonisolated private struct ActiveWineProcess {
        let process: Process
        let session: OnlineGameLaunchSession
    }

    nonisolated private static let processLock = NSLock()
    // Launch, monitor and termination callbacks all guard this registry with processLock.
    nonisolated(unsafe) private static var activeWineProcesses: [Int32: ActiveWineProcess] = [:]

    /// Returns whether a launch initiated by this app is still alive. Wine's
    /// x86_64 loader is not exposed as a normal NSWorkspace application under
    /// Rosetta, so process ownership is a more reliable source of truth than
    /// looking for `SeasunGame.exe` in NSWorkspace.
    nonisolated static func isActive(_ session: OnlineGameLaunchSession) -> Bool {
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
                if let logURL = session.logURL {
                    let previousLogOffset = logOffset
                    let logRead = await Task.detached(priority: .utility) {
                        readLaunchLog(from: logURL, offset: previousLogOffset)
                    }.value
                    logOffset = logRead.nextOffset
                    if containsClientLaunchSignal(in: logRead.contents) {
                        clientLaunchObservedInLog = true
                    }
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

    static func reusableJX3LaunchSession(
        from sessions: [OnlineGameLaunchSession],
        in bottleURL: URL,
        requiresClient: Bool
    ) -> OnlineGameLaunchSession? {
        let bottlePath = bottleURL.standardizedFileURL.resolvingSymlinksInPath().path
        let matchingSessions = sessions.filter { session in
            let sessionBottle = session.installationBottleURL ?? session.bottleURL
            return sessionBottle.standardizedFileURL.resolvingSymlinksInPath().path == bottlePath
        }
        let clientSession = matchingSessions.first {
            $0.executableName.caseInsensitiveCompare(OnlineGameMode.jx3ClientName) == .orderedSame
        }
        return clientSession ?? (requiresClient ? nil : matchingSessions.first)
    }

    private static func activeLaunchSession(
        in bottleURL: URL,
        requiresClient: Bool = false
    ) -> OnlineGameLaunchSession? {
        processLock.lock()
        activeWineProcesses = activeWineProcesses.filter { $0.value.process.isRunning }
        let sessions = activeWineProcesses.values.map(\.session)
        processLock.unlock()
        return reusableJX3LaunchSession(from: sessions, in: bottleURL, requiresClient: requiresClient)
    }

    private static func reusableJX3LaunchSession(
        in bottleURL: URL,
        crossOverAppPath: String?,
        runtime: OnlineGameRuntimeKind,
        requiresClient: Bool
    ) async -> OnlineGameLaunchSession? {
        if let session = activeLaunchSession(in: bottleURL, requiresClient: requiresClient) {
            return session
        }
        guard requiresClient else { return nil }

        let activity = await Task.detached(priority: .utility) {
            currentJX3Activity(for: nil, clientLaunchObservedInLog: false, in: bottleURL)
        }.value
        // Another request may have started a direct launch while the process scan was running.
        if let session = activeLaunchSession(in: bottleURL, requiresClient: true) {
            return session
        }
        guard let clientPID = activity.gameProcessIdentifiers.first else { return nil }
        return OnlineGameLaunchSession(
            processIdentifier: clientPID,
            executableName: OnlineGameMode.jx3ClientName,
            logURL: nil,
            bottleURL: bottleURL,
            runtime: runtime,
            crossOverAppPath: crossOverAppPath,
            closeLauncherWhenGameStarts: false
        )
    }

    @discardableResult
    @MainActor
    static func launchJX3(
        in bottleURL: URL,
        crossOverAppPath: String?,
        options: GameOptions
    ) async throws -> OnlineGameLaunchSession {
        let runtime = OnlineGameRuntimeKind.selected()
        let requiresClient = options.jx3SkipLauncher
        let launchTicket = runtime == .bundledWine
            ? try ArclumeWineStopService.launchTicket() : nil
        if let activeSession = await reusableJX3LaunchSession(
            in: bottleURL, crossOverAppPath: crossOverAppPath, runtime: runtime, requiresClient: requiresClient
        ) {
            OnlineGameInitialConfiguration.startPolling(for: bottleURL)
            console.log("复用已运行的剑网3 Wine 会话（\(activeSession.executableName)，PID \(activeSession.processIdentifier)）")
            return activeSession
        }

        let installation = OnlineGameDiscovery.jx3Installation(in: bottleURL)
        let clientArguments = options.gameArguments.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let target = installation.launchTarget(
            skipLauncher: requiresClient, clientArguments: clientArguments
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        OnlineGameMode.applyDefaultRuntimePreferences(to: options)
        if runtime == .bundledWine {
            if options.cxGraphicsBackend == "dxmt" {
                try await GameMetalShaderCache.prepare(prefix: bottleURL)
            }
            try await WineWarmupService.shared.prepareForLaunch(prefix: bottleURL, wineMSync: options.wineMSync)
        }
        var shouldPollForConfiguration = false
        do {
            if try OnlineGameInitialConfiguration.applySkipVideoCardScoreUpdate(in: bottleURL, installation: installation) {
                console.log("剑网3启动配置已确认：SkipVideoCardScoreUpdate=1")
            } else {
                shouldPollForConfiguration = true
            }
        } catch {
            shouldPollForConfiguration = true
            console.warn("剑网3 SkipVideoCardScoreUpdate 暂时无法写入：\(error.localizedDescription)")
        }
        let machineConfig = JX3GameConfiguration.configURL(in: bottleURL, installation: installation)
            .deletingLastPathComponent()
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("machine_config.ini")
        try await JX3GPUProfileStore.shared.reapply(at: machineConfig)
        do {
            if try OnlineGameInitialConfiguration.applyDLSSFrameGeneration(
                enabled: options.dlssFrameGenerationEnabled,
                in: bottleURL,
                installation: installation
            ) {
                let value = options.dlssFrameGenerationEnabled ? "2" : "1"
                console.log("剑网3 DLSS 能力声明已设置为 DLSS=\(value)；实际画质开关由客户端控制")
            } else {
                shouldPollForConfiguration = true
            }
        } catch {
            shouldPollForConfiguration = true
            console.warn("剑网3 DLSS 能力声明暂时无法写入：\(error.localizedDescription)")
        }
        if shouldPollForConfiguration {
            OnlineGameInitialConfiguration.startPolling(for: bottleURL, installation: installation)
        }
        do {
            if try BundledOnlineGameResources.installNVNGX(into: bottleURL) {
                console.log("已将内置 NVNGX DLL 替换到剑网3客户端目录")
            }
        } catch {
            // The launcher may already have a working NVNGX pair. A failed
            // best-effort refresh must not prevent Wine itself from starting.
            console.warn("剑网3 NVNGX 更新暂时无法完成：\(error.localizedDescription)")
        }
        let reusableSession = await reusableJX3LaunchSession(
            in: bottleURL, crossOverAppPath: crossOverAppPath, runtime: runtime, requiresClient: requiresClient
        )
        if let activeSession = activeLaunchSession(in: bottleURL, requiresClient: requiresClient) ?? reusableSession {
            console.log("复用已运行的剑网3 Wine 会话（\(activeSession.executableName)，PID \(activeSession.processIdentifier)）")
            return activeSession
        }
        return try launchExecutable(
            target,
            in: bottleURL,
            runtime: runtime,
            crossOverAppPath: crossOverAppPath,
            options: options,
            closeLauncherWhenGameStarts: !requiresClient && options.closeLauncherWhenGameStarts,
            wineLaunchTicket: launchTicket,
            shaderGameID: OnlineGameMode.jx3GameID
        )
    }

    private static func launchExecutable(
        _ target: OnlineGameInstallation.LaunchTarget,
        in bottleURL: URL,
        runtime: OnlineGameRuntimeKind,
        crossOverAppPath: String?,
        options: GameOptions,
        closeLauncherWhenGameStarts: Bool = false,
        wineLaunchTicket: Int? = nil,
        shaderGameID: String? = nil
    ) throws -> OnlineGameLaunchSession {
        if runtime == .bundledWine {
            return try launchBundledWineExecutable(
                target,
                in: bottleURL,
                options: options,
                closeLauncherWhenGameStarts: closeLauncherWhenGameStarts,
                wineLaunchTicket: wineLaunchTicket,
                shaderGameID: shaderGameID
            )
        }
        guard let crossOverAppPath else {
            throw CocoaError(.fileNoSuchFile)
        }
        let crossOverURL = URL(fileURLWithPath: crossOverAppPath)
        let logURL = try makeLaunchLogURL()
        let logHandle = try FileHandle(forWritingTo: logURL)
        writeLaunchLog("使用已安装的 CrossOver 运行时", to: logHandle)
        let executableName = target.executableURL.lastPathComponent
        writeLaunchLog("启动程序：\(executableName)", to: logHandle)
        if target.arguments.first == OnlineGameInstallation.directClientArgument {
            writeLaunchLog("剑网3直启参数：\(OnlineGameInstallation.directClientArgument)", to: logHandle)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["CX_ROOT"] = crossOverURL
            .appendingPathComponent("Contents/SharedSupport/CrossOver")
            .path
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

        let process = makeWineProcess(
            wineURL: wineURL, target: target, bottleURL: bottleURL, runtime: runtime, environment: environment
        )
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()

        let processIdentifier = process.processIdentifier
        writeLaunchLog("Wine 已启动（PID \(processIdentifier)）", to: logHandle)
        let session = OnlineGameLaunchSession(
            processIdentifier: processIdentifier,
            executableName: executableName,
            logURL: logURL,
            bottleURL: bottleURL,
            runtime: .crossOver,
            crossOverAppPath: crossOverAppPath,
            closeLauncherWhenGameStarts: closeLauncherWhenGameStarts
        )
        processLock.lock()
        activeWineProcesses[processIdentifier] = ActiveWineProcess(process: process, session: session)
        processLock.unlock()
        process.terminationHandler = { _ in
            writeLaunchLog("Wine 启动命令已退出（状态 \(process.terminationStatus)）", to: logHandle)
            logHandle.closeFile()
            ArclumeGameLogStore.enforceStorageLimit()
            processLock.lock()
            activeWineProcesses.removeValue(forKey: processIdentifier)
            processLock.unlock()
        }

        return session
    }

    private static func launchBundledWineExecutable(
        _ target: OnlineGameInstallation.LaunchTarget,
        in bottleURL: URL,
        options: GameOptions,
        closeLauncherWhenGameStarts: Bool,
        wineLaunchTicket: Int?,
        shaderGameID: String? = nil
    ) throws -> OnlineGameLaunchSession {
        let launchTicket = try wineLaunchTicket ?? ArclumeWineStopService.launchTicket()
        guard BundledWineRuntime.ownsPrefix(bottleURL), BundledWineRuntime.isValidPrefix(at: bottleURL) else {
            throw BundledWineRuntimeError.invalidPrefix
        }

        let logURL = try makeLaunchLogURL()
        let logHandle = try FileHandle(forWritingTo: logURL)
        let runtimeName = "Arclume Runtime"
        writeLaunchLog("开始准备 \(runtimeName) 运行时", to: logHandle)

        let configuration: BundledWineRuntime.LaunchConfiguration
        do {
            configuration = try BundledWineRuntime.makeLaunchConfiguration(options: options, prefix: bottleURL)
            try OnlineGameBottleConfiguration.apply(to: bottleURL)
        } catch {
            writeLaunchLog("\(runtimeName) 运行时准备失败：\(error.localizedDescription)", to: logHandle)
            writeLaunchFailure(error, stage: "runtime-preparation", to: logHandle)
            logHandle.closeFile()
            throw error
        }

        var environment = configuration.environment
        environment = GameAdaptationRules.processEnvironment(environment, executable: target.executableURL, bottle: bottleURL)
        if let shaderGameID, configuration.environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "dxmt" {
            try GameMetalShaderCache.configure(environment: &environment, prefix: bottleURL, gameID: shaderGameID)
            writeLaunchLog("DXMT 0.80 着色器目录：\(environment["DXMT_SHADER_CACHE_PATH"] ?? "")", to: logHandle)
        }
        // Focused input tracing is developer-only. It is limited to the IME
        // and clipboard driver channels, avoiding unbounded server tracing.
        if BundledWineRuntime.verboseWineTraceRequested {
            environment["WINEDEBUG"] = "-all,+timestamp,+pid,+tid,+imm,+clipboard"
        }

        let process = makeWineProcess(
            wineURL: configuration.wineURL, target: target, bottleURL: bottleURL,
            runtime: .bundledWine, environment: environment
        )
        writeLaunchLog(
            "\(runtimeName) 命令：\(configuration.wineURL.path) \(process.arguments?.joined(separator: " ") ?? "")",
            to: logHandle
        )
#if DEBUG
        BundledWineRuntime.appendLauncherDiagnostics(
                runtimeURL: configuration.runtimeURL,
                wineURL: configuration.wineURL,
                executableURL: target.executableURL,
                arguments: target.arguments,
                environment: process.environment ?? environment,
                to: logHandle
        )
#endif

        process.standardOutput = logHandle
        process.standardError = logHandle
        do { try ArclumeWineStopService.withLaunchTicket(launchTicket) { try process.run() } }
        catch {
            writeLaunchFailure(error, stage: "wine-process-run", to: logHandle)
            logHandle.closeFile()
            throw error
        }

        let processIdentifier = process.processIdentifier
        writeLaunchLog("\(runtimeName) 已启动（PID \(processIdentifier)）", to: logHandle)
        let session = OnlineGameLaunchSession(
            processIdentifier: processIdentifier,
            executableName: target.executableURL.lastPathComponent,
            logURL: logURL,
            bottleURL: bottleURL,
            runtime: .bundledWine,
            crossOverAppPath: nil,
            closeLauncherWhenGameStarts: closeLauncherWhenGameStarts
        )
        processLock.lock()
        activeWineProcesses[processIdentifier] = ActiveWineProcess(process: process, session: session)
        processLock.unlock()
        process.terminationHandler = { terminatedProcess in
            writeLaunchLog(
                "\(runtimeName) 启动命令已退出（reason \(terminatedProcess.terminationReason)，状态 \(terminatedProcess.terminationStatus)）",
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

        return session
    }

    static func makeWineProcess(
        wineURL: URL,
        target: OnlineGameInstallation.LaunchTarget,
        bottleURL: URL,
        runtime: OnlineGameRuntimeKind,
        environment: [String: String]
    ) -> Process {
        let bottleArguments = runtime == .crossOver ? ["--bottle", bottleURL.lastPathComponent] : []
        var environment = environment
        environment["WINEPREFIX"] = bottleURL.path

        let process = Process()
        process.executableURL = wineURL
        process.arguments = bottleArguments + [target.executableURL.path] + target.arguments
        process.environment = environment
        process.currentDirectoryURL = target.workingDirectoryURL ?? target.executableURL.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice
        return process
    }

    private static func writeLaunchFailure(_ error: Error, stage: String, to handle: FileHandle) {
        var current = error as NSError
        for depth in 0..<4 {
            writeLaunchLog("启动失败 [\(stage)] error[\(depth)] domain=\(current.domain) code=\(current.code)：\(current.localizedDescription)", to: handle)
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        handle.synchronizeFile()
    }

    /// Terminates only the two JX3 Windows executables in the selected Games
    /// prefix. This deliberately avoids the old global Wine sweep, which
    /// could also close another game or a user's separately-opened CrossOver.
    static func forceQuitJX3(
        in bottleURL: URL,
        crossOverAppPath: String?
    ) async {
        let activeSession = activeLaunchSession(in: bottleURL)
        let runtime = activeSession?.runtime ?? OnlineGameRuntimeKind.selected()
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

        let session = activeLaunchSession(in: bottleURL)
        let initialActivity = await Task.detached(priority: .utility) {
            currentJX3Activity(for: session, clientLaunchObservedInLog: false, in: bottleURL)
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
            currentJX3Activity(for: session, clientLaunchObservedInLog: false, in: bottleURL)
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

    nonisolated static func classifyJX3Activity(
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

    static func isJX3ClientRunning() -> Bool {
        !currentJX3Activity(for: nil, clientLaunchObservedInLog: false).gameProcessIdentifiers.isEmpty
    }

    nonisolated private static func currentJX3Activity(
        for session: OnlineGameLaunchSession?,
        clientLaunchObservedInLog: Bool,
        in bottleURL: URL? = nil
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
        let installationBottle = session?.installationBottleURL ?? session?.bottleURL ?? bottleURL
        return classifyJX3Activity(
            processList: processList,
            openFiles: openFiles,
            rootProcessIdentifier: rootPID,
            rootProcessIsRunning: session.map(isActive) ?? false,
            clientLaunchObservedInLog: clientLaunchObservedInLog,
            requiredBottlePath: installationBottle?.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    nonisolated private static func parseProcessList(_ output: String) -> [ProcessListEntry] {
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

    nonisolated private static func processIDsToInspect(
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

    nonisolated private static func lsofOutput(for processIdentifiers: Set<Int32>) -> String {
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

    nonisolated private static func processOutput(
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

    nonisolated private static func classifyJX3Path(
        _ path: String,
        processIdentifier: Int32,
        launcherPIDs: inout Set<Int32>,
        gamePIDs: inout Set<Int32>,
        requiredBottlePath: String?
    ) {
        let lowercased = path.lowercased()
        if let requiredBottlePath,
           !lowercased.contains(requiredBottlePath.lowercased() + "/") {
            return
        }
        if lowercased.contains(OnlineGameMode.jx3LauncherName.lowercased()) {
            launcherPIDs.insert(processIdentifier)
        }
        if lowercased.contains(OnlineGameMode.jx3ClientName.lowercased()) {
            gamePIDs.insert(processIdentifier)
        }
    }

    nonisolated private static func readLaunchLog(
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
        crossOverAppPath: String?,
        force: Bool = false
    ) throws {
        let launchTicket = runtime == .bundledWine ? try ArclumeWineStopService.launchTicket() : nil
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
            let runtimeURL = try WineRuntimeProvider.ensureRuntime(for: bottleURL)
            let wineURL = runtimeURL.appendingPathComponent("lib/wine/x86_64-unix/wine")
            guard FileManager.default.isExecutableFile(atPath: wineURL.path) else { return }
            process.executableURL = wineURL
            environment["WINEDATADIR"] = runtimeURL.appendingPathComponent("share/wine").path
            environment["WINEDLLPATH"] = runtimeURL.appendingPathComponent("lib/wine").path
            environment["WINESERVER"] = runtimeURL.appendingPathComponent("bin/wineserver").path
            process.arguments = [
                "C:\\windows\\system32\\taskkill.exe",
                "/IM", executableName,
                "/T"
            ]
        }
        if force { process.arguments?.append("/F") }
        environment["WINEPREFIX"] = bottleURL.path
        environment["WINEDEBUG"] = "-all"
        process.environment = environment
        process.currentDirectoryURL = bottleURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if let launchTicket { try ArclumeWineStopService.withLaunchTicket(launchTicket) { try process.run() } }
        else { try process.run() }
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

    private static func writeLaunchLog(_ message: String, to handle: FileHandle) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[Arclume][\(timestamp)] \(message)\n"
        handle.write(Data(line.utf8))
    }

    private static func makeLaunchLogURL() throws -> URL {
        try ArclumeGameLogStore.createLaunchLogURL()
    }
}
