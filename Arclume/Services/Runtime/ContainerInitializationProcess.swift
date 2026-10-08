import Darwin
import Foundation

/// Bounded waiting for a child created by this operation; never matches or
/// signals unrelated processes by executable name.
nonisolated enum ContainerInitializationProcess {
    static func wait(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard process.isRunning else { return true }
        process.terminate()
        let grace = ProcessInfo.processInfo.systemUptime + 1
        while process.isRunning && ProcessInfo.processInfo.systemUptime < grace {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        return false
    }
}
