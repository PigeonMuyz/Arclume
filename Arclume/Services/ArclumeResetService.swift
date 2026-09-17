import AppKit
import Foundation

@MainActor
enum ArclumeResetService {
    nonisolated static let pendingKey = "arclume.resetPending.v1"
    nonisolated static let skipLegacyDataKey = "arclume.skipLegacyDataAfterReset.v1"
    nonisolated static let legacyDefaultsKey = "didMigrateArclumeDefaults.v1"
    static var requested = false

    /// Commit only after the ordinary quit path has drained owned Wine.
    static func commitIfRequested() throws {
        guard requested else { return }
        try requireSingleInstance()
        try GameAssociatedDataService.requireRegistryIdle()
        UserDefaults.standard.set(true, forKey: pendingKey)
        guard UserDefaults.standard.synchronize() else {
            UserDefaults.standard.removeObject(forKey: pendingKey)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func performPendingReset() throws {
        guard !ArclumeTestEnvironment.isTesting,
              UserDefaults.standard.bool(forKey: pendingKey) else { return }
        try requireSingleInstance()
        // Another Wine installation may have opened a managed prefix since quit.
        // Refuse rather than killing unrelated processes or moving live data.
        try GameAssociatedDataService.requireRegistryIdle()
        guard let appDomain = Bundle.main.bundleIdentifier,
              appDomain == "io.github.pigeonmuyz.arclume" else { throw CocoaError(.fileWriteNoPermission) }
        let parent = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try reset(supportRoot: ARCLUME_SUPPORT_FOLDER_URL, expectedParent: parent,
                  preferencesDomain: suiteName, appDomain: appDomain) { root in
            try FileManager.default.trashItem(at: root, resultingItemURL: nil)
        }
    }

    private static func requireSingleInstance() throws {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.pigeonmuyz.arclume")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard others.isEmpty else {
            throw NSError(domain: "ArclumeReset", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "请先退出其他正在运行的 Arclume 实例，再重置。"])
        }
    }

    /// Parameters allow tests to use only private domains and temporary folders.
    /// Move the whole directory, never traverse symlinks or enumerate game files.
    static func reset(supportRoot: URL, expectedParent: URL,
                      preferencesDomain: String, appDomain: String,
                      moveToTrash: (URL) throws -> Void) throws {
        let root = supportRoot.standardizedFileURL
        let expected = expectedParent.appendingPathComponent("Arclume", isDirectory: true).standardizedFileURL
        guard root.path == expected.path,
              !preferencesDomain.isEmpty, !appDomain.isEmpty,
              preferencesDomain != appDomain,
              preferencesDomain != "NSGlobalDomain", appDomain != "NSGlobalDomain"
        else { throw CocoaError(.fileWriteNoPermission) }
        let values: URLResourceValues?
        do {
            values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            values = nil
        }
        if let values {
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileWriteNoPermission)
            }
            try moveToTrash(root)
        }
        guard let preferences = UserDefaults(suiteName: preferencesDomain),
              let application = UserDefaults(suiteName: appDomain) else { throw CocoaError(.fileWriteUnknown) }
        preferences.removePersistentDomain(forName: preferencesDomain)
        // These are migration barriers, not restored user settings.
        preferences.set(true, forKey: legacyDefaultsKey)
        preferences.set(true, forKey: skipLegacyDataKey)
        guard preferences.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        // Clear the pending marker last, so a failed move/clear can be retried.
        application.removePersistentDomain(forName: appDomain)
        guard application.synchronize() else {
            application.set(true, forKey: pendingKey)
            _ = application.synchronize()
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
