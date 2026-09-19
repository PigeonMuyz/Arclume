import AppKit

/// Keep the normal run loop alive while Swift concurrency drains owned Wine.
/// terminateLater enters AppKit's modal loop, which can starve MainActor tasks.
@MainActor
final class ArclumeAppDelegate: NSObject, NSApplicationDelegate {
    private var terminationPending = false
    private(set) var terminationReady = false
    private let beginExit: () -> Void
    private let stopWine: () async throws -> Void
    private let cancelExit: () -> Void
    private let reportFailure: (Error) -> Void
    private let finishExit: () throws -> Void

    override convenience init() {
        self.init(
            beginExit: {
                ArclumeWineStopService.beginApplicationExit()
                WineWarmupService.shared.beginQuitting()
            },
            stopWine: {
                let root = BundledWineRuntime.installationURL.deletingLastPathComponent()
                try await ArclumeWineStopService.stop(runtimeRoot: root)
            },
            cancelExit: {
                ArclumeResetService.requested = false
                ArclumeWineStopService.cancelApplicationExit()
                WineWarmupService.shared.cancelQuitting()
            },
            reportFailure: { error in
                let alert = NSAlert()
                alert.messageText = "退出准备未完成，已取消退出或重置"
                alert.informativeText = error.localizedDescription + "\n请稍后再次退出 Arclume。已经结束的 Windows 应用不会自动恢复。"
                alert.addButton(withTitle: "好")
                alert.runModal()
            },
            finishExit: { try ArclumeResetService.commitIfRequested() }
        )
    }

    init(beginExit: @escaping () -> Void, stopWine: @escaping () async throws -> Void,
         cancelExit: @escaping () -> Void, reportFailure: @escaping (Error) -> Void,
         finishExit: @escaping () throws -> Void = {}) {
        self.beginExit = beginExit
        self.stopWine = stopWine
        self.cancelExit = cancelExit
        self.reportFailure = reportFailure
        self.finishExit = finishExit
        super.init()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !ArclumeTestEnvironment.isTesting else { return .terminateNow }
        if terminationReady { return .terminateNow }
        if UnifiedContainerMigrationModel.shared.busy {
            ArclumeResetService.requested = false
            let alert = NSAlert()
            alert.messageText = "容器迁移正在进行"
            alert.informativeText = "请等待校验或恢复完成后再退出，避免中断容器切换。"
            alert.runModal()
            return .terminateCancel
        }
        return requestTermination { completed in
            if completed { sender.terminate(nil) }
        }
    }

    func requestTermination(reply: @escaping (Bool) -> Void) -> NSApplication.TerminateReply {
        // Cancel this attempt, then ask AppKit to terminate again after cleanup.
        // Do not use reply(toApplicationShouldTerminate:) without terminateLater.
        guard !terminationPending else { return .terminateCancel }
        terminationPending = true
        beginExit()
        Task {
            do {
                try await stopWine()
                try finishExit()
                terminationReady = true
                reply(true)
            } catch {
                cancelExit()
                terminationPending = false
                reply(false)
                reportFailure(error)
            }
        }
        return .terminateCancel
    }
}
