import AppKit
import Combine
import CryptoKit
import Foundation

extension Notification.Name {
    nonisolated static let arclumeWinePrefixReady = Notification.Name("Arclume.WinePrefixReady")
}

/// The only writer of the helper's stdin lives in this App. EOF releases the
/// helper on normal exit, SIGKILL or crash, without killing the shared server.
nonisolated final class WineWarmupLease: @unchecked Sendable {
    let process: Process
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var released = false
    private var received = Data()
    private var ready = false

    init(process: Process, onReady: @escaping @Sendable () -> Void,
         onExit: @escaping @Sendable (Int32) -> Void) {
        self.process = process
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { handle.readabilityHandler = nil; return }
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self.lock.lock()
            self.received.append(data.prefix(max(0, 128 - self.received.count)))
            let report = !self.ready && self.received.starts(with: Data("ARCLUME_WINE_READY\n".utf8))
            if report { self.ready = true }
            self.lock.unlock()
            if report { onReady() }
        }
        process.terminationHandler = { onExit($0.terminationStatus) }
    }

    func release() {
        lock.lock()
        let shouldClose = !released
        released = true
        lock.unlock()
        guard shouldClose else { return }
        try? input.fileHandleForWriting.close()
        // Only our own helper, never wineserver or application processes.
        let child = process
        Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if child.isRunning { child.terminate() }
        }
    }
}

@MainActor
final class WineWarmupService: ObservableObject {
    static let shared = WineWarmupService()
    nonisolated static let defaultsKey = "winePrewarmAtAppLaunch.v1"
    nonisolated static let targetsKey = "winePrewarmTargets.v1"
    nonisolated static let helperSHA256 = "9b9a3a45e9bdbd31ba37cab6b1ae365c9486fe0f6e2dc40e552c4e901e56f83a"
    private var sessions: [WineWarmupTarget: WineWarmupSession] = [:]
    private var quitting = false

    nonisolated static func shouldStart(enabled: Bool, suspended: Bool, testing: Bool) -> Bool {
        enabled && !suspended && !testing
    }

    nonisolated static func verifyHelper(_ url: URL) throws {
        guard url.standardizedFileURL == url.resolvingSymlinksInPath(),
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size < 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        guard hash == helperSHA256 else { throw CocoaError(.fileReadCorruptFile) }
    }

    func configure(prefix: URL?) {
        guard !ArclumeTestEnvironment.isTesting else { return }
        if let defaults = UserDefaults(suiteName: suiteName), let prefix {
            Self.migrateSelection(in: defaults, previousTarget: WineWarmupTarget.allCases.first { $0.prefix == prefix })
            if BundledWineRuntime.prefixURL == BundledWineRuntime.standardSteamPrefixURL {
                let old = WineWarmupTarget.decode(defaults.string(forKey: Self.targetsKey) ?? "[]")
                defaults.set(WineWarmupTarget.encode(old.isEmpty ? [] : [.steam]), forKey: Self.targetsKey)
            }
        }
        refresh()
    }

    nonisolated static func migrateSelection(in defaults: UserDefaults, previousTarget: WineWarmupTarget?) {
        guard defaults.object(forKey: targetsKey) == nil else { return }
        let targets: Set<WineWarmupTarget> = defaults.bool(forKey: defaultsKey)
            ? Set(previousTarget.map { [$0] } ?? []) : []
        defaults.set(WineWarmupTarget.encode(targets), forKey: targetsKey)
    }

    func session(for target: WineWarmupTarget) -> WineWarmupSession {
        if let session = sessions[target] { return session }
        let session = WineWarmupSession(prefix: target.prefix)
        sessions[target] = session
        return session
    }

    func preferenceChanged(retry: Bool = true) {
        refresh(retry: retry)
    }

    func beginQuitting() {
        quitting = true
        for session in sessions.values { session.configure(enabled: false) }
    }

    func cancelQuitting() {
        // Do not restart Wine immediately after the user cancelled a failed quit.
        quitting = false
    }

    private func refresh(retry: Bool = false) {
        guard !ArclumeTestEnvironment.isTesting, !quitting else { return }
        let defaults = UserDefaults(suiteName: suiteName)
        let enabled = defaults?.bool(forKey: Self.defaultsKey) == true
        let targets = WineWarmupTarget.decode(defaults?.string(forKey: Self.targetsKey) ?? "[]")
        var warmedPaths = Set<String>()
        for target in WineWarmupTarget.allCases {
            let wanted = enabled && targets.contains(target)
            let unique = wanted && warmedPaths.insert(target.prefix.resolvingSymlinksInPath().path).inserted
            session(for: target).configure(enabled: unique, retry: retry)
        }
    }

    func prepareForLaunch(prefix: URL, wineMSync: Bool) async throws {
        guard let target = WineWarmupTarget.allCases.first(where: { $0.prefix == prefix }) else { return }
        try await session(for: target).prepareForLaunch(wineMSync: wineMSync)
    }
}

/// One lease per prefix: selection and failures in one container do not stop another.
@MainActor
final class WineWarmupSession: ObservableObject {
    @Published private(set) var status = "未开启"
    private let prefix: URL
    private var enabled = false
    private var lease: WineWarmupLease?
    private var session: UUID?
    private var ready = false
    private var suspended = false
    private var deadline: Task<Void, Never>?
    private var msyncWarmedPrefixes = Set<URL>()

    init(prefix: URL) { self.prefix = prefix }

    func configure(enabled: Bool, retry: Bool = false) {
        if retry || self.enabled != enabled { suspended = false }
        self.enabled = enabled
        if !enabled { stop(message: "未开启") }
        else { reconcile() }
    }

    private func stop(message: String) {
        deadline?.cancel(); deadline = nil
        session = nil
        // Even before READY the helper may have created an MSync server.
        if lease != nil { msyncWarmedPrefixes.insert(prefix) }
        lease?.release(); lease = nil
        ready = false
        status = message
    }

    private func reconcile() {
        guard WineWarmupService.shouldStart(enabled: enabled, suspended: suspended, testing: ArclumeTestEnvironment.isTesting), lease == nil else { return }
        let prefix = self.prefix
        guard BundledWineRuntime.ownsStandardSteamPrefix(prefix) || BundledWineRuntime.ownsPrefix(prefix),
              prefix.standardizedFileURL == prefix.resolvingSymlinksInPath(),
              BundledWineRuntime.isValidPrefix(at: prefix), BundledWineRuntime.isCurrentRuntime() else {
            status = "等待容器初始化"
            return
        }
        do {
            let ticket = try ArclumeWineStopService.launchTicket()
            guard let helper = Bundle.main.url(forResource: "wine-keepalive", withExtension: "exe") else { throw CocoaError(.fileNoSuchFile) }
            try WineWarmupService.verifyHelper(helper)
            let runtime = BundledWineRuntime.installationURL
            // This helper needs no graphics modules. In particular, do NOT use
            // makeDefaultLaunchConfiguration: it can install/change D3DMetal.
            let process = Process()
            process.executableURL = runtime.appendingPathComponent("lib/wine/x86_64-unix/wine")
            process.arguments = [helper.path]
            process.currentDirectoryURL = prefix
            process.environment = [
                "PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(),
                "WINEPREFIX": prefix.path, "WINESERVER": runtime.appendingPathComponent("bin/wineserver").path,
                "WINEDATADIR": runtime.appendingPathComponent("share/wine").path,
                "WINEDLLPATH": ["lib/wine/x86_64-windows", "lib/wine/i386-windows", "lib/wine"].map { runtime.appendingPathComponent($0).path }.joined(separator: ":"),
                "DYLD_FALLBACK_LIBRARY_PATH": runtime.appendingPathComponent("lib64").path,
                "WINEMSYNC": "1", "WINEDEBUG": "-all", "ROSETTA_ADVERTISE_AVX": "1",
                "LANG": "zh_CN.UTF-8"
            ]
            let token = UUID()
            session = token
            let newLease = WineWarmupLease(process: process, onReady: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.session == token else { return }
                    self.ready = true
                    self.msyncWarmedPrefixes.insert(prefix)
                    self.deadline?.cancel()
                    self.status = "已预热"
                }
            }, onExit: { [weak self] code in
                Task { @MainActor [weak self] in
                    guard let self, self.session == token else { return }
                    self.suspended = true
                    self.stop(message: code == 0 ? "已停止" : "预热暂停（\(code)）")
                }
            })
            lease = newLease
            status = "正在预热…"
            try ArclumeWineStopService.withLaunchTicket(ticket) { try process.run() }
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, self.session == token, !self.ready else { return }
                self.suspended = true
                self.stop(message: "预热超时")
            }
        } catch {
            suspended = true
            stop(message: "预热未完成：\(error.localizedDescription)")
        }
    }

    /// WINEMSYNC is a server-wide choice. Release our client and allow the
    /// server to exit naturally before a game explicitly requests it disabled.
    func prepareForLaunch(wineMSync: Bool) async throws {
        guard !wineMSync else { return }
        if lease != nil {
            suspended = true
            // An in-flight startup may already have created an MSync server.
            msyncWarmedPrefixes.insert(prefix)
            stop(message: "本次已暂停保温：应用使用不同的 Wine 同步设置")
        }
        guard msyncWarmedPrefixes.contains(prefix) else { return }
        let launchTicket = try ArclumeWineStopService.launchTicket()
        let waiter = Process()
        waiter.executableURL = BundledWineRuntime.installationURL.appendingPathComponent("bin/wineserver")
        waiter.arguments = ["-w"]
        waiter.environment = ["WINEPREFIX": prefix.path, "HOME": NSHomeDirectory()]
        waiter.standardInput = FileHandle.nullDevice
        waiter.standardOutput = FileHandle.nullDevice
        waiter.standardError = FileHandle.nullDevice
        try ArclumeWineStopService.withLaunchTicket(launchTicket) { try waiter.run() }
        defer { if waiter.isRunning { waiter.terminate() } }
        let timeout = ContinuousClock.now.advanced(by: .seconds(8))
        while waiter.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < timeout else {
                throw NSError(domain: "Arclume.WineWarmup", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Wine 保温已暂停，但同容器后台进程尚未退出。此应用关闭了 MSync，请先退出该容器内的其他 Windows 应用后重试；未强制终止任何应用。"])
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard waiter.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        msyncWarmedPrefixes.remove(prefix)
    }
}
