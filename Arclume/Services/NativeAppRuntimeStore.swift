//
//  NativeAppRuntimeStore.swift
//  Procyon
//

import AppKit
import Combine
import Foundation

@MainActor
final class NativeAppRuntimeStore: ObservableObject {
    @Published private(set) var sessions: [String: NativeAppRuntimeSession] = [:]
    @Published private(set) var phases: [String: NativeAppRuntimePhase] = [:]

    private struct PendingLaunch {
        let gameID: String
        let bundleIdentifier: String?
        let normalizedNames: Set<String>
        let createdAt: Date
    }

    private let workspace: NSWorkspace
    private var applicationsByProcessIdentifier: [pid_t: NSRunningApplication] = [:]
    private var pendingLaunches: [String: PendingLaunch] = [:]
    private var pendingTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var reconciliationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        let center = workspace.notificationCenter

        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notification in
                self?.handleApplicationLaunch(notification)
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                self?.handleApplicationTermination(notification)
            }
            .store(in: &cancellables)
    }

    deinit {
        pendingTimeoutTasks.values.forEach { $0.cancel() }
        reconciliationTask?.cancel()
    }

    func phase(for gameID: String) -> NativeAppRuntimePhase? {
        phases[gameID]
    }

    func isActive(gameID: String) -> Bool {
        phases[gameID]?.isActive == true
    }

    func isRunning(gameID: String) -> Bool {
        guard case .running = phases[gameID] else { return false }
        return true
    }

    func launchApplication(
        gameID: String,
        at applicationURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) async throws {
        phases[gameID] = .launching

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        if !environment.isEmpty {
            configuration.environment = ProcessInfo.processInfo.environment.merging(
                environment,
                uniquingKeysWith: { _, override in override }
            )
        }

        do {
            let application = try await workspace.openApplication(
                at: applicationURL,
                configuration: configuration
            )
            guard !application.isTerminated else {
                finish(gameID: gameID)
                throw NativeAppRuntimeError.applicationExitedDuringLaunch
            }
            register(gameID: gameID, application: application)
        } catch {
            if sessions[gameID] == nil {
                phases[gameID] = .failed(message: error.localizedDescription)
            }
            throw error
        }
    }

    /// Starts tracking an app that another launcher (for example Steam) will open.
    /// Returns false when a matching process is already running and has been attached.
    @discardableResult
    func expectApplicationLaunch(
        gameID: String,
        appNames: [String],
        bundleIdentifier: String? = nil,
        timeout: Duration = .seconds(70)
    ) -> Bool {
        if let runningApplication = workspace.runningApplications.first(where: {
            matches(
                application: $0,
                bundleIdentifier: bundleIdentifier,
                normalizedNames: Self.normalizedNames(appNames)
            )
        }) {
            register(gameID: gameID, application: runningApplication)
            return false
        }

        pendingTimeoutTasks.removeValue(forKey: gameID)?.cancel()
        pendingLaunches[gameID] = PendingLaunch(
            gameID: gameID,
            bundleIdentifier: bundleIdentifier,
            normalizedNames: Self.normalizedNames(appNames),
            createdAt: Date()
        )
        phases[gameID] = .launching

        pendingTimeoutTasks[gameID] = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self, self.pendingLaunches.removeValue(forKey: gameID) != nil else {
                return
            }
            self.pendingTimeoutTasks.removeValue(forKey: gameID)
            self.phases[gameID] = .failed(
                message: L10n.string("The native app did not start before the timeout.")
            )
        }
        return true
    }

    func cancelExpectedLaunch(gameID: String, error: Error? = nil) {
        pendingLaunches.removeValue(forKey: gameID)
        pendingTimeoutTasks.removeValue(forKey: gameID)?.cancel()
        if let error {
            phases[gameID] = .failed(message: error.localizedDescription)
        } else {
            phases.removeValue(forKey: gameID)
        }
    }

    @discardableResult
    func stop(gameID: String) -> Bool {
        guard let session = sessions[gameID],
              let application = applicationsByProcessIdentifier[session.processIdentifier]
                ?? NSRunningApplication(processIdentifier: session.processIdentifier)
        else {
            finish(gameID: gameID)
            return false
        }

        phases[gameID] = .stopping(processIdentifier: session.processIdentifier)
        let accepted = application.terminate()
        if !accepted {
            // The process is still alive, so keep the runtime state truthful and
            // continue tracking its PID even if the polite quit request failed.
            phases[gameID] = .running(processIdentifier: session.processIdentifier)
        }
        return accepted
    }

    func reconcileRunningApplications() {
        for session in Array(sessions.values) {
            let application = applicationsByProcessIdentifier[session.processIdentifier]
                ?? NSRunningApplication(processIdentifier: session.processIdentifier)
            if application == nil || application?.isTerminated == true {
                finish(processIdentifier: session.processIdentifier)
            }
        }
    }

    // Internal state entry points keep process matching testable without launching UI fixtures.
    func registerSession(
        gameID: String,
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        isTerminated: Bool = false
    ) {
        guard !isTerminated else {
            finish(gameID: gameID)
            return
        }
        sessions[gameID] = NativeAppRuntimeSession(
            gameID: gameID,
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            startedAt: Date()
        )
        phases[gameID] = .running(processIdentifier: processIdentifier)
        startReconciliationIfNeeded()
    }

    func finish(processIdentifier: pid_t) {
        guard let session = sessions.values.first(where: {
            $0.processIdentifier == processIdentifier
        }) else {
            applicationsByProcessIdentifier.removeValue(forKey: processIdentifier)
            return
        }
        finish(gameID: session.gameID)
    }

    private func register(gameID: String, application: NSRunningApplication) {
        let processIdentifier = application.processIdentifier
        applicationsByProcessIdentifier[processIdentifier] = application
        registerSession(
            gameID: gameID,
            processIdentifier: processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            isTerminated: application.isTerminated
        )
    }

    private func finish(gameID: String) {
        pendingLaunches.removeValue(forKey: gameID)
        pendingTimeoutTasks.removeValue(forKey: gameID)?.cancel()
        if let session = sessions.removeValue(forKey: gameID) {
            applicationsByProcessIdentifier.removeValue(forKey: session.processIdentifier)
        }
        phases.removeValue(forKey: gameID)
        if sessions.isEmpty {
            reconciliationTask?.cancel()
            reconciliationTask = nil
        }
    }

    private func handleApplicationLaunch(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
        else {
            return
        }

        let match = pendingLaunches.values
            .filter {
                matches(
                    application: application,
                    bundleIdentifier: $0.bundleIdentifier,
                    normalizedNames: $0.normalizedNames
                )
            }
            .min(by: { $0.createdAt < $1.createdAt })
        guard let match else { return }

        pendingLaunches.removeValue(forKey: match.gameID)
        pendingTimeoutTasks.removeValue(forKey: match.gameID)?.cancel()
        register(gameID: match.gameID, application: application)
    }

    private func handleApplicationTermination(_ notification: Notification) {
        if let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication {
            finish(processIdentifier: application.processIdentifier)
            return
        }

        if let processIdentifier = notification.userInfo?["NSApplicationProcessIdentifier"]
            as? NSNumber {
            finish(processIdentifier: processIdentifier.int32Value)
        }
    }

    private func matches(
        application: NSRunningApplication,
        bundleIdentifier: String?,
        normalizedNames: Set<String>
    ) -> Bool {
        if let bundleIdentifier,
           application.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
            return true
        }

        let candidates = [
            application.localizedName,
            application.bundleURL?.lastPathComponent,
            application.executableURL?.lastPathComponent,
        ].compactMap { $0 }
        return candidates.contains { candidate in
            normalizedNames.contains(Self.normalizeName(candidate))
        }
    }

    private func startReconciliationIfNeeded() {
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard let self else { return }
                self.reconcileRunningApplications()
                if self.sessions.isEmpty {
                    self.reconciliationTask = nil
                    return
                }
            }
        }
    }

    private static func normalizedNames(_ names: [String]) -> Set<String> {
        Set(names.flatMap { name in
            let normalized = normalizeName(name)
            return [normalized, normalizeName((name as NSString).deletingPathExtension)]
        }.filter { !$0.isEmpty })
    }

    private static func normalizeName(_ name: String) -> String {
        let baseName = URL(fileURLWithPath: name).lastPathComponent
        let withoutAppExtension = baseName.lowercased().hasSuffix(".app")
            ? String(baseName.dropLast(4))
            : baseName
        return withoutAppExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
