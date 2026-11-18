import AppKit
import Foundation

@MainActor
enum ArclumeResetService {
    nonisolated static let pendingKey = "arclume.resetPending.v1"
    nonisolated static let skipLegacyDataKey = "arclume.skipLegacyDataAfterReset.v1"
    nonisolated static let legacyDefaultsKey = "didMigrateArclumeDefaults.v1"
    nonisolated static let trashLocationKey = "arclume.resetTrashLocation.v1"
    static var hasPendingReset: Bool { UserDefaults.standard.bool(forKey: pendingKey) }

    /// Persist recovery intent only after owned Wine and background writers are idle.
    private static func commitRequest() throws {
        try requireSingleInstance()
        UserDefaults.standard.set(true, forKey: pendingKey)
        guard UserDefaults.standard.synchronize() else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func performReset(progress: @escaping @MainActor (ArclumeResetCoordinator.Phase, URL?) -> Void) async throws -> URL? {
        guard !ArclumeTestEnvironment.isTesting else { throw CancellationError() }
        try requireSingleInstance()
        guard let appDomain = Bundle.main.bundleIdentifier,
              appDomain == "io.github.pigeonmuyz.arclume" else { throw CocoaError(.fileWriteNoPermission) }
        let parent = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = ARCLUME_SUPPORT_FOLDER_URL
        let domain = suiteName
        let previousTrash = UserDefaults.standard.url(forKey: trashLocationKey)
        if let previousTrash { progress(.moving, previousTrash) }
        let exists = try await Task.detached(priority: .userInitiated) {
            try ArclumeWineStopService.requireManagedDataIdle(root: root)
            return try validateTarget(supportRoot: root, expectedParent: parent,
                                      preferencesDomain: domain, appDomain: appDomain)
        }.value
        if previousTrash != nil && exists {
            throw NSError(domain: "ArclumeReset", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "应用数据已移入废纸篓，但原位置又出现了数据目录。为避免误移动，请先检查后再重试。"])
        }
        try commitRequest()
        progress(.moving, nil)
        let trash: URL? = try await Task.detached(priority: .userInitiated) {
            guard exists else { return previousTrash }
            // Recheck immediately before moving; never traverse or copy game files.
            try ArclumeWineStopService.requireManagedDataIdle(root: root)
            _ = try validateTarget(supportRoot: root, expectedParent: parent,
                                   preferencesDomain: domain, appDomain: appDomain)
            var result: NSURL?
            try FileManager.default.trashItem(at: root, resultingItemURL: &result)
            return result as URL?
        }.value
        // Publish before persistence: even a settings-write error must report the move.
        progress(.clearing, trash)
        if let trash {
            UserDefaults.standard.set(trash, forKey: trashLocationKey)
            guard UserDefaults.standard.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        }
        try await Task.detached(priority: .userInitiated) {
            try clearSettings(preferencesDomain: domain, appDomain: appDomain,
                              awaitingAcknowledgement: true, trash: trash)
        }.value
        return trash
    }

    static func acknowledgeCompletion() throws {
        let trash = UserDefaults.standard.url(forKey: trashLocationKey)
        UserDefaults.standard.removeObject(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: trashLocationKey)
        guard UserDefaults.standard.synchronize() else {
            UserDefaults.standard.set(true, forKey: pendingKey)
            if let trash { UserDefaults.standard.set(trash, forKey: trashLocationKey) }
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func requireSingleInstance() throws {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.pigeonmuyz.arclume")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard others.isEmpty else {
            throw NSError(domain: "ArclumeReset", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "请先退出其他正在运行的 Arclume 实例，再重置。"])
        }
    }

    /// Foundation rejects init(suiteName:) for the running app's own identifier.
    /// Separate test domains must still use their own stores, never standard.
    nonisolated static func applicationDefaults(for domain: String) -> UserDefaults? {
        domain == Bundle.main.bundleIdentifier ? .standard : UserDefaults(suiteName: domain)
    }

    /// Parameters allow tests to use only private domains and temporary folders.
    /// Move the whole directory, never traverse symlinks or enumerate game files.
    nonisolated static func reset(supportRoot: URL, expectedParent: URL,
                      preferencesDomain: String, appDomain: String,
                      moveToTrash: (URL) throws -> Void) throws {
        let exists = try validateTarget(supportRoot: supportRoot, expectedParent: expectedParent,
                                       preferencesDomain: preferencesDomain, appDomain: appDomain)
        if exists { try moveToTrash(supportRoot.standardizedFileURL) }
        try clearSettings(preferencesDomain: preferencesDomain, appDomain: appDomain)
    }

    nonisolated private static func validateTarget(supportRoot: URL, expectedParent: URL,
                                                  preferencesDomain: String, appDomain: String) throws -> Bool {
        let root = supportRoot.standardizedFileURL
        let expected = expectedParent.appendingPathComponent("Arclume", isDirectory: true).standardizedFileURL
        guard root.path == expected.path,
              !preferencesDomain.isEmpty, !appDomain.isEmpty,
              preferencesDomain != appDomain,
              preferencesDomain != "NSGlobalDomain", appDomain != "NSGlobalDomain"
        else { throw CocoaError(.fileWriteNoPermission) }
        // Resolve both stores before moving data, so an unavailable store cannot
        // leave the reset half-finished after the support folder reaches Trash.
        guard UserDefaults(suiteName: preferencesDomain) != nil,
              applicationDefaults(for: appDomain) != nil else {
            throw NSError(domain: "ArclumeReset", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "无法打开 Arclume 设置，尚未移动应用数据。"])
        }
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
        }
        return values != nil
    }

    nonisolated private static func clearSettings(preferencesDomain: String, appDomain: String,
                                                 awaitingAcknowledgement: Bool = false, trash: URL? = nil) throws {
        guard let preferences = UserDefaults(suiteName: preferencesDomain),
              let application = applicationDefaults(for: appDomain) else { throw CocoaError(.fileWriteUnknown) }
        preferences.removePersistentDomain(forName: preferencesDomain)
        // These are migration barriers, not restored user settings.
        preferences.set(true, forKey: legacyDefaultsKey)
        preferences.set(true, forKey: skipLegacyDataKey)
        guard preferences.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        // Clear the pending marker last, so a failed move/clear can be retried.
        application.removePersistentDomain(forName: appDomain)
        if awaitingAcknowledgement {
            application.set(true, forKey: pendingKey)
            if let trash { application.set(trash, forKey: trashLocationKey) }
        }
        guard application.synchronize() else {
            application.set(true, forKey: pendingKey)
            if let trash { application.set(trash, forKey: trashLocationKey) }
            _ = application.synchronize()
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
