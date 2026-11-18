import Combine
import Foundation

/// Owns the visible reset transaction; tests inject operations and never reset user data.
@MainActor
final class ArclumeResetCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle, checking, stopping, moving, clearing, completed, failed

        var title: String {
            switch self {
            case .idle, .checking: "正在检查重置条件…"
            case .stopping: "正在结束 Windows 程序…"
            case .moving: "正在将应用数据移入废纸篓…"
            case .clearing: "正在清除设置…"
            case .completed: "重置已完成"
            case .failed: "重置尚未完成"
            }
        }
    }

    static let shared = ArclumeResetCoordinator(
        check: {
            guard !ArclumeTestEnvironment.isTesting else { throw CancellationError() }
            guard activities.isEmpty, !UnifiedContainerMigrationModel.shared.busy else {
                throw NSError(domain: "ArclumeReset", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "正在下载、安装、更新或初始化，请等待任务完成后再重置。"])
            }
            try ArclumeResetService.requireSingleInstance()
        },
        beginExit: {
            ArclumeWineStopService.beginApplicationExit()
            WineWarmupService.shared.beginQuitting()
        },
        stop: {
            try await ArclumeWineStopService.stopManagedRuntimes()
        },
        reset: { progress in try await ArclumeResetService.performReset(progress: progress) },
        finish: { try ArclumeResetService.acknowledgeCompletion() }
    )
    private static var activities: Set<AnyHashable> = []
    static var hasActiveActivities: Bool { !activities.isEmpty }

    /// Track writers owned by view-local stores as well as singleton services.
    static func setActivity(_ owner: AnyObject, busy: Bool) {
        let id = ObjectIdentifier(owner)
        if busy { activities.insert(id) } else { activities.remove(id) }
    }

    static func beginActivity() -> UUID {
        let token = UUID()
        activities.insert(token)
        return token
    }

    static func endActivity(_ token: UUID) { activities.remove(token) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var error: String?
    @Published private(set) var trashURL: URL?
    @Published private(set) var allowsExit = false
    var isActive: Bool { phase != .idle }
    var isRunning: Bool { [.checking, .stopping, .moving, .clearing].contains(phase) }
    var blocksQuit: Bool { isActive && !allowsExit }
    private let check: () throws -> Void
    private let beginExit: () -> Void
    private let stop: () async throws -> Void
    private let reset: (@escaping @MainActor (Phase, URL?) -> Void) async throws -> URL?
    private let finish: () throws -> Void

    init(check: @escaping () throws -> Void, beginExit: @escaping () -> Void,
         stop: @escaping () async throws -> Void,
         reset: @escaping (@escaping @MainActor (Phase, URL?) -> Void) async throws -> URL?,
         finish: @escaping () throws -> Void = {}) {
        self.check = check; self.beginExit = beginExit; self.stop = stop; self.reset = reset
        self.finish = finish
    }

    func start() {
        guard phase == .idle || phase == .failed else { return }
        phase = .checking; error = nil; allowsExit = false
        Task {
            do {
                // Give the reset screen an opportunity to appear before any work.
                await Task.yield()
                try check()
                beginExit()
                phase = .stopping
                try await stop()
                try check()
                let moved = try await reset { [weak self] phase, trash in
                    self?.phase = phase
                    if let trash { self?.trashURL = trash }
                }
                if let moved { trashURL = moved }
                phase = .completed
            } catch {
                self.error = error.localizedDescription
                phase = .failed
            }
        }
    }

    /// Completion must be acknowledged so the Trash notice is never lost to auto-quit.
    @discardableResult
    func acknowledgeExit() -> Bool {
        guard phase == .completed || phase == .failed else { return false }
        do {
            if phase == .completed { try finish() }
            allowsExit = true
            return true
        } catch {
            self.error = error.localizedDescription
            phase = .failed
            return false
        }
    }
}
