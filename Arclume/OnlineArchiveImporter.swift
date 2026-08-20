//
//  OnlineArchiveImporter.swift
//  Procyon
//

import Foundation

enum OnlineArchiveImportError: LocalizedError {
    case unsupportedArchive(URL)
    case unsafeArchiveEntry(String)
    case archiveExtractionFailed(String)
    case launcherInstallFailed(String)
    case launcherNotFound
    case multipleLaunchers([URL])

    var errorDescription: String? {
        switch self {
        case .unsupportedArchive(let url):
            return "不支持的压缩包格式：\(url.lastPathComponent)"
        case .unsafeArchiveEntry(let entry):
            return "压缩包包含不安全路径：\(entry)"
        case .archiveExtractionFailed(let detail):
            return "解压失败：\(detail)"
        case .launcherInstallFailed(let detail):
            return "安装启动器失败：\(detail)"
        case .launcherNotFound:
            return "所选内容中未找到 SeasunGame.exe。"
        case .multipleLaunchers(let candidates):
            return "所选内容中找到多个 SeasunGame.exe：\(candidates.map(\.path).joined(separator: ", "))"
        }
    }
}

enum OnlineLauncherDownloadScanner {
    static func candidates(in downloadsURL: URL? = nil) -> [URL] {
        let directory = downloadsURL
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let directory else { return [] }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items
            .filter { url in
                let name = url.lastPathComponent.lowercased()
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isSymbolicLink != true else { return false }
                if name == "seasungame" {
                    return values?.isDirectory == true
                }
                return name == "seasungame.zip" && values?.isRegularFile == true
            }
            .sorted { lhs, rhs in
                let lhsIsFolder = lhs.pathExtension.isEmpty
                let rhsIsFolder = rhs.pathExtension.isEmpty
                if lhsIsFolder != rhsIsFolder {
                    return lhsIsFolder
                }
                return lhs.lastPathComponent.localizedStandardCompare(
                    rhs.lastPathComponent
                ) == .orderedAscending
            }
    }
}

enum SafeArchiveExtractor {
    private static let archiveExtensions = ["zip", "tar", "gz", "tgz", "xz"]

    static func canExtract(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }

    static func extract(_ archiveURL: URL, to destination: URL) throws {
        guard canExtract(archiveURL) else {
            throw OnlineArchiveImportError.unsupportedArchive(archiveURL)
        }
        try validate(archiveURL)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        if archiveURL.pathExtension.caseInsensitiveCompare("zip") == .orderedSame {
            try run(executable: "/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, destination.path])
        } else {
            try run(executable: "/usr/bin/tar", arguments: ["-xf", archiveURL.path, "-C", destination.path])
        }
        try validateExtractedTree(at: destination)
    }

    static func validate(_ archiveURL: URL) throws {
        guard canExtract(archiveURL) else {
            throw OnlineArchiveImportError.unsupportedArchive(archiveURL)
        }
        let entries: [String]
        if archiveURL.pathExtension.caseInsensitiveCompare("zip") == .orderedSame {
            entries = try processOutput(executable: "/usr/bin/zipinfo", arguments: ["-1", archiveURL.path])
                .split(separator: "\n")
                .map(String.init)
        } else {
            entries = try processOutput(executable: "/usr/bin/tar", arguments: ["-tf", archiveURL.path])
                .split(separator: "\n")
                .map(String.init)
        }
        for entry in entries {
            guard isSafeRelativePath(entry) else {
                throw OnlineArchiveImportError.unsafeArchiveEntry(entry)
            }
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        var path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasSuffix("/") { path.removeLast() }
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains("..") && !components.contains("")
    }

    static func validateExtractedTree(at root: URL) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey]
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: keys).isSymbolicLink) == true {
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                let resolvedURL = URL(
                    fileURLWithPath: destination,
                    relativeTo: url.deletingLastPathComponent()
                ).standardizedFileURL
                let resolvedPath = resolvedURL.path
                guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else {
                    throw OnlineArchiveImportError.unsafeArchiveEntry(
                        "\(url.path) -> \(destination)"
                    )
                }
            }
        }
    }

    private static func processOutput(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw OnlineArchiveImportError.archiveExtractionFailed(result)
        }
        return result
    }

    private static func run(executable: String, arguments: [String]) throws {
        _ = try processOutput(executable: executable, arguments: arguments)
    }
}

enum OnlineLauncherImporter {
    private struct PreparedPayload {
        let launcherURL: URL
        let payloadRootURL: URL?
        let cleanupURL: URL?
        let movesPayload: Bool
    }

    private static let managedInstallComponents = [
        "drive_c",
        "SeasunGame"
    ]

    static func prepareLauncher(from sourceURL: URL) throws -> URL {
        try preparePayload(from: sourceURL).launcherURL
    }

    /// Importing a launcher represents an already installed launcher. A
    /// selected folder is moved into C:\\SeasunGame inside the selected
    /// Bottle so a complete game is not duplicated. Single executables and
    /// extracted archives use a temporary staging copy, then the normal
    /// discovery pass surfaces the launcher card. Nothing is executed during
    /// import.
    static func installLauncher(from sourceURL: URL, into bottleURL: URL) throws -> URL {
        let payload = try preparePayload(from: sourceURL)
        defer {
            if let cleanupURL = payload.cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }

        let fileManager = FileManager.default
        let destinationRoot = managedInstallComponents.reduce(bottleURL) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        let destinationParent = destinationRoot.deletingLastPathComponent()
        let stagingRoot = destinationParent.appendingPathComponent(
            ".JX3Launcher-import-\(UUID().uuidString)",
            isDirectory: true
        )
        let backupRoot = destinationParent.appendingPathComponent(
            ".JX3Launcher-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        var hadExistingInstall = false

        do {
            let stagedLauncherURL: URL
            if let payloadRootURL = payload.payloadRootURL {
                let relativeLauncherPath = relativePath(
                    from: payloadRootURL,
                    to: payload.launcherURL
                )

                if payload.movesPayload {
                    // Moving a directory on the same volume is a rename and
                    // does not require another copy of a potentially huge
                    // game installation.
                    try fileManager.createDirectory(
                        at: destinationParent,
                        withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: payloadRootURL, to: stagingRoot)
                } else {
                    try fileManager.createDirectory(
                        at: stagingRoot,
                        withIntermediateDirectories: true
                    )
                    let items = try fileManager.contentsOfDirectory(
                        at: payloadRootURL,
                        includingPropertiesForKeys: nil,
                        options: []
                    )
                    for item in items {
                        try fileManager.copyItem(
                            at: item,
                            to: stagingRoot.appendingPathComponent(item.lastPathComponent)
                        )
                    }
                }
                stagedLauncherURL = stagingRoot.appendingPathComponent(relativeLauncherPath)
            } else {
                try fileManager.createDirectory(
                    at: stagingRoot,
                    withIntermediateDirectories: true
                )
                stagedLauncherURL = stagingRoot.appendingPathComponent(
                    OnlineGameMode.jx3LauncherName
                )
                try fileManager.copyItem(at: payload.launcherURL, to: stagedLauncherURL)
            }

            try SafeArchiveExtractor.validateExtractedTree(at: stagingRoot)
            guard fileManager.fileExists(atPath: stagedLauncherURL.path) else {
                throw OnlineArchiveImportError.launcherNotFound
            }

            try fileManager.createDirectory(
                at: destinationParent,
                withIntermediateDirectories: true
            )
            hadExistingInstall = fileManager.fileExists(atPath: destinationRoot.path)
            if hadExistingInstall {
                try fileManager.moveItem(at: destinationRoot, to: backupRoot)
            }

            try fileManager.moveItem(at: stagingRoot, to: destinationRoot)

            let installedLauncherURL = destinationRoot.appendingPathComponent(
                relativePath(from: stagingRoot, to: stagedLauncherURL)
            )
            guard fileManager.fileExists(atPath: installedLauncherURL.path) else {
                throw OnlineArchiveImportError.launcherNotFound
            }
            if hadExistingInstall {
                try? fileManager.removeItem(at: backupRoot)
            }
            return installedLauncherURL
        } catch let error as OnlineArchiveImportError {
            restoreMovedFolderIfNeeded(
                payload: payload,
                sourceURL: sourceURL,
                stagingRoot: stagingRoot,
                destinationRoot: destinationRoot,
                fileManager: fileManager
            )
            restoreExistingInstallIfNeeded(
                hadExistingInstall: hadExistingInstall,
                destinationRoot: destinationRoot,
                backupRoot: backupRoot,
                fileManager: fileManager
            )
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        } catch {
            restoreMovedFolderIfNeeded(
                payload: payload,
                sourceURL: sourceURL,
                stagingRoot: stagingRoot,
                destinationRoot: destinationRoot,
                fileManager: fileManager
            )
            restoreExistingInstallIfNeeded(
                hadExistingInstall: hadExistingInstall,
                destinationRoot: destinationRoot,
                backupRoot: backupRoot,
                fileManager: fileManager
            )
            try? fileManager.removeItem(at: stagingRoot)
            throw OnlineArchiveImportError.launcherInstallFailed(error.localizedDescription)
        }
    }

    private static func restoreMovedFolderIfNeeded(
        payload: PreparedPayload,
        sourceURL: URL,
        stagingRoot: URL,
        destinationRoot: URL,
        fileManager: FileManager
    ) {
        guard payload.movesPayload,
              !fileManager.fileExists(atPath: sourceURL.path)
        else {
            return
        }

        if fileManager.fileExists(atPath: stagingRoot.path) {
            try? fileManager.moveItem(at: stagingRoot, to: sourceURL)
        } else if fileManager.fileExists(atPath: destinationRoot.path) {
            // The final move may have completed before a postcondition failed.
            // Put the user's original folder back where it came from.
            try? fileManager.moveItem(at: destinationRoot, to: sourceURL)
        }
    }

    private static func restoreExistingInstallIfNeeded(
        hadExistingInstall: Bool,
        destinationRoot: URL,
        backupRoot: URL,
        fileManager: FileManager
    ) {
        guard hadExistingInstall,
              !fileManager.fileExists(atPath: destinationRoot.path),
              fileManager.fileExists(atPath: backupRoot.path)
        else {
            return
        }
        try? fileManager.moveItem(at: backupRoot, to: destinationRoot)
    }

    private static func preparePayload(from sourceURL: URL) throws -> PreparedPayload {
        if sourceURL.pathExtension.caseInsensitiveCompare("exe") == .orderedSame {
            guard sourceURL.lastPathComponent.caseInsensitiveCompare(
                OnlineGameMode.jx3LauncherName
            ) == .orderedSame else {
                throw OnlineArchiveImportError.launcherNotFound
            }
            return PreparedPayload(
                launcherURL: sourceURL,
                payloadRootURL: nil,
                cleanupURL: nil,
                movesPayload: false
            )
        }

        let sourceValues = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if sourceValues.isDirectory == true {
            guard sourceValues.isSymbolicLink != true else {
                throw OnlineArchiveImportError.unsafeArchiveEntry(sourceURL.path)
            }
            try SafeArchiveExtractor.validateExtractedTree(at: sourceURL)
            return PreparedPayload(
                launcherURL: try findLauncher(in: sourceURL),
                payloadRootURL: sourceURL,
                cleanupURL: nil,
                movesPayload: true
            )
        }

        let importRoot = ARCLUME_SUPPORT_FOLDER_URL
            .appendingPathComponent("OnlineLauncherImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try SafeArchiveExtractor.extract(sourceURL, to: importRoot)

        return PreparedPayload(
            launcherURL: try findLauncher(in: importRoot),
            payloadRootURL: importRoot,
            cleanupURL: importRoot,
            movesPayload: false
        )
    }

    private static func findLauncher(in root: URL) throws -> URL {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw OnlineArchiveImportError.launcherNotFound
        }
        let candidates = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.lastPathComponent.caseInsensitiveCompare(OnlineGameMode.jx3LauncherName) == .orderedSame,
                  (try? url.resourceValues(forKeys: keys).isRegularFile) == true,
                  (try? url.resourceValues(forKeys: keys).isSymbolicLink) != true
            else {
                return nil
            }
            return url
        }
        switch candidates.count {
        case 0:
            throw OnlineArchiveImportError.launcherNotFound
        case 1:
            return candidates[0]
        default:
            throw OnlineArchiveImportError.multipleLaunchers(candidates)
        }
    }

    private static func relativePath(from root: URL, to child: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        guard childPath.hasPrefix(rootPath + "/") else {
            return child.lastPathComponent
        }
        return String(childPath.dropFirst(rootPath.count + 1))
    }
}
