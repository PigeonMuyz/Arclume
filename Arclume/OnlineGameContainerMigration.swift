//
//  OnlineGameContainerMigration.swift
//  Procyon
//

import Darwin
import Foundation

enum OnlineGameContainerMigrationError: LocalizedError {
    case destinationContainsFiles
    case sourceInstallationMissing
    case destinationOnDifferentVolume
    case validationFailed
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .destinationContainsFiles:
            "目标 Games 容器中已有未完成的 SeasunGame 文件，无法安全覆盖。"
        case .sourceInstallationMissing:
            "当前 Games 容器中未找到可迁移的剑网3启动器。"
        case .destinationOnDifferentVolume:
            "两个 Games 容器不在同一磁盘，无法在不复制游戏文件的情况下迁移。"
        case .validationFailed:
            "迁移后的剑网3启动器校验失败，已恢复到原 Games 容器。"
        case .transferFailed(let detail):
            "迁移剑网3失败：\(detail)"
        }
    }
}

/// Moves only the JX3 managed installation between runtime-specific
/// containers. The source container itself stays in place with its registry
/// and runtime configuration, while drive_c/SeasunGame changes ownership.
enum OnlineGameContainerMigration {
    typealias ProgressHandler = @Sendable (_ fraction: Double, _ label: String) -> Void

    struct TransferResult: Sendable {
        let didMove: Bool
    }

    nonisolated private static let installationComponents = ["drive_c", "SeasunGame"]
    nonisolated private static let launcherFileName = "SeasunGame.exe"

    @discardableResult
    nonisolated static func migrateJX3(
        from sourceBottleURL: URL,
        to destinationBottleURL: URL,
        progress: ProgressHandler? = nil
    ) throws -> TransferResult {
        guard sourceBottleURL.standardizedFileURL != destinationBottleURL.standardizedFileURL else {
            return TransferResult(didMove: false)
        }

        let fileManager = FileManager.default
        let sourceRoot = installationRoot(in: sourceBottleURL)
        let destinationRoot = installationRoot(in: destinationBottleURL)
        guard !fileManager.fileExists(atPath: destinationRoot.path) else {
            if containsLauncher(in: destinationRoot, fileManager: fileManager) {
                return TransferResult(didMove: false)
            }
            throw OnlineGameContainerMigrationError.destinationContainsFiles
        }

        progress?(0.05, "正在检查剑网3文件…")
        guard containsLauncher(in: sourceRoot, fileManager: fileManager) else {
            throw OnlineGameContainerMigrationError.sourceInstallationMissing
        }

        try fileManager.createDirectory(
            at: destinationRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        progress?(0.30, "正在迁移剑网3到新的 Games 容器…")

        var shouldRollback = false
        do {
            try moveOnSameVolume(from: sourceRoot, to: destinationRoot)
            shouldRollback = true

            progress?(0.82, "正在校验迁移后的剑网3启动器…")
            guard containsLauncher(in: destinationRoot, fileManager: fileManager) else {
                throw OnlineGameContainerMigrationError.validationFailed
            }
            shouldRollback = false
        } catch {
            if shouldRollback,
               fileManager.fileExists(atPath: destinationRoot.path),
               !fileManager.fileExists(atPath: sourceRoot.path) {
                try? moveOnSameVolume(from: destinationRoot, to: sourceRoot)
            }
            throw error
        }

        progress?(1, "剑网3迁移完成")
        return TransferResult(didMove: true)
    }

    nonisolated private static func installationRoot(in bottleURL: URL) -> URL {
        installationComponents.reduce(bottleURL) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
    }

    nonisolated private static func containsLauncher(
        in installationRoot: URL,
        fileManager: FileManager
    ) -> Bool {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: installationRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        for case let url as URL in enumerator {
            guard url.lastPathComponent.caseInsensitiveCompare(launcherFileName) == .orderedSame,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                continue
            }
            return true
        }
        return false
    }

    nonisolated private static func moveOnSameVolume(from sourceURL: URL, to destinationURL: URL) throws {
        let result = sourceURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            let code = errno
            if code == EXDEV {
                throw OnlineGameContainerMigrationError.destinationOnDifferentVolume
            }
            let error = POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            throw OnlineGameContainerMigrationError.transferFailed(error.localizedDescription)
        }
    }
}
