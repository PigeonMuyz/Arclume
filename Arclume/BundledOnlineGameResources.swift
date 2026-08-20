//
//  BundledOnlineGameResources.swift
//  Procyon
//

import Foundation

enum BundledOnlineGameResourceError: LocalizedError {
    case missingResource(String)
    case extractionFailed(String, Int32)
    case invalidArchive(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "App 内未找到剑网3模式资源：\(name)"
        case .extractionFailed(let name, let status):
            "无法解压内置 \(name)（退出状态 \(status)）。"
        case .invalidArchive(let name):
            "内置 \(name) 的目录结构不完整。"
        }
    }
}

enum BundledOnlineGameResources {
    static let resourceSubdirectory = "OnlineGameDependencies"
    static let gstreamerArchiveName = "gstreamer-framework.tar.xz"
    static let dxmtArchiveName = "dxmt.tar.gz"
    static let fontsArchiveName = "fonts.tar.xz"
    static let chineseFontName = "NotoSansCJKsc-Regular.otf"
    static let nvngxArchiveName = "nvngx-jx3.tar.xz"
    static let nvngxFileNames = ["nvngx_dlss.dll", "nvngx_dlssg.dll"]
    private static let materializationLock = NSLock()
    /// Retain the active app build's extraction plus one previous build, so a
    /// running game is not left with a removed D3DMetal path while repeated
    /// development builds cannot grow this cache without bound.
    private static let retainedMaterializationsPerResource = 2

    static func resourceURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: nil)
            ?? Bundle.main.url(
                forResource: name,
                withExtension: nil,
                subdirectory: resourceSubdirectory
            )
    }

    static func chineseFontURL() -> URL? {
        resourceURL(named: chineseFontName)
            ?? Bundle.main.url(
                forResource: chineseFontName,
                withExtension: nil,
                subdirectory: "\(resourceSubdirectory)/Fonts"
            )
            ?? materializedFileURL(
                from: resourceURL(named: fontsArchiveName),
                named: chineseFontName,
                cacheName: "fonts"
            )
    }

    /// Resolves a resource that may live in a compressed GPTK archive. The
    /// existing uncompressed layout remains supported for development builds
    /// and for older copies of the app.
    static func bundledURL(named name: String) throws -> URL? {
        if let directURL = resourceURL(named: name) {
            return directURL
        }

        let components = name.split(separator: "/", omittingEmptySubsequences: true)
        guard let firstComponent = components.first else { return nil }
        let first = String(firstComponent)
        guard first == "d3dMetal3" || first == "d3dMetal4" else { return nil }

        let version = String(first.dropFirst("d3dMetal".count))
        let root = try d3dMetalResourceRoot(version: version)
        guard components.count > 1 else { return root }

        var resolvedURL = root
        for component in components.dropFirst() {
            resolvedURL.appendPathComponent(String(component))
        }
        return FileManager.default.fileExists(atPath: resolvedURL.path)
            ? resolvedURL
            : nil
    }

    static func d3dMetalArchiveName(version: String) -> String {
        "d3dMetal\(version).tar.xz"
    }

    /// Replaces the two game-side DLSS DLLs in the JX3 `bin64` runtime
    /// directory. An existing file is retained as `.orig` once, so the
    /// replacement remains reversible for users who need to restore the
    /// original game files.
    @discardableResult
    static func installNVNGX(into bottleURL: URL) throws -> Bool {
        guard let binaryDirectoryURL = OnlineGameDiscovery.jx3BinaryDirectory(in: bottleURL) else {
            return false
        }

        if let archiveURL = resourceURL(named: nvngxArchiveName) {
            let extractedRoot = try materializedArchiveRoot(
                archiveURL,
                cacheName: "nvngx-jx3"
            )
            try replaceNVNGXFiles(from: extractedRoot, into: binaryDirectoryURL)
            return true
        }

        var sourceURLs: [URL] = []
        for name in nvngxFileNames {
            guard let sourceURL = resourceURL(named: name) else {
                throw BundledOnlineGameResourceError.missingResource(nvngxArchiveName)
            }
            sourceURLs.append(sourceURL)
        }
        try replaceNVNGXFiles(from: sourceURLs, into: binaryDirectoryURL)
        return true
    }

    /// Injectable archive path used by tests and by local diagnostics.
    @discardableResult
    static func installNVNGX(from archiveURL: URL, into destinationDirectoryURL: URL) throws -> Bool {
        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArclumeNVNGX-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: stagingRoot) }
        try extract(archive: archiveURL, into: stagingRoot)
        try replaceNVNGXFiles(from: stagingRoot, into: destinationDirectoryURL)
        return true
    }

    /// Installs the fixed dependency set shipped inside Procyon+.
    /// No network access is performed from this path.
    static func install(
        into crossOverURL: URL,
        setProgress: @escaping (Double, String) -> Void
    ) throws {
        let gstreamerArchive = try requiredResource(named: gstreamerArchiveName)
        let dxmtArchive = try requiredResource(named: dxmtArchiveName)

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ArclumeOnlineGameDependencies-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        setProgress(10, "准备内置 GStreamer")
        let gstreamerRoot = stagingRoot.appendingPathComponent("gstreamer", isDirectory: true)
        try FileManager.default.createDirectory(
            at: gstreamerRoot,
            withIntermediateDirectories: true
        )
        try extract(archive: gstreamerArchive, into: gstreamerRoot)
        guard let frameworkRoot = findGStreamerRoot(in: gstreamerRoot) else {
            throw BundledOnlineGameResourceError.invalidArchive("GStreamer")
        }
        try installGstreamer(srcUrl: frameworkRoot, destUrl: crossOverURL)

        setProgress(58, "准备内置 DXMT")
        let dxmtRoot = stagingRoot.appendingPathComponent("dxmt", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dxmtRoot,
            withIntermediateDirectories: true
        )
        try extract(archive: dxmtArchive, into: dxmtRoot)
        try installDXMT(srcURL: dxmtRoot, destUrl: crossOverURL, versionTag: nil)

        setProgress(84, "准备 GPTK 4.0 Beta 2")
        _ = try d3dMetalResourceRoot(version: "4")
        try installd3dMetal(at: crossOverURL, version: "4")
        setProgress(100, "内置依赖准备完成")
    }

    private static func requiredResource(named name: String) throws -> URL {
        guard let url = resourceURL(named: name) else {
            throw BundledOnlineGameResourceError.missingResource(name)
        }
        return url
    }

    private static func d3dMetalResourceRoot(version: String) throws -> URL {
        let directoryName = "d3dMetal\(version)"
        if let directURL = resourceURL(named: directoryName) {
            return directURL
        }

        let archiveURL = try requiredResource(named: d3dMetalArchiveName(version: version))
        let extractedRoot = try materializedArchiveRoot(
            archiveURL,
            cacheName: directoryName
        )
        let directoryURL = extractedRoot.appendingPathComponent(directoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            throw BundledOnlineGameResourceError.invalidArchive(directoryName)
        }
        return directoryURL
    }

    private static func materializedFileURL(
        from archiveURL: URL?,
        named name: String,
        cacheName: String
    ) -> URL? {
        guard let archiveURL,
              let extractedRoot = try? materializedArchiveRoot(archiveURL, cacheName: cacheName)
        else {
            return nil
        }

        let directURL = extractedRoot.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        guard let enumerator = FileManager.default.enumerator(
            at: extractedRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let url as URL in enumerator
        where url.lastPathComponent == name {
            return url
        }
        return nil
    }

    private static func materializedArchiveRoot(
        _ archiveURL: URL,
        cacheName: String
    ) throws -> URL {
        let fileManager = FileManager.default
        let cacheParent = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent(
            "Procyon/BundledOnlineGameResources",
            isDirectory: true
        )
        let cacheKey = try resourceCacheKey(for: archiveURL)
        let cacheURL = cacheParent.appendingPathComponent(
            "\(cacheName)-\(cacheKey)",
            isDirectory: true
        )

        materializationLock.lock()
        defer { materializationLock.unlock() }

        if fileManager.fileExists(atPath: cacheURL.path) {
            pruneStaleMaterializations(
                in: cacheParent,
                cacheName: cacheName,
                keeping: cacheURL
            )
            return cacheURL
        }

        try fileManager.createDirectory(
            at: cacheParent,
            withIntermediateDirectories: true
        )
        let stagingURL = cacheParent.appendingPathComponent(
            ".\(cacheName)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingURL) }
        try extract(archive: archiveURL, into: stagingURL)
        try fileManager.moveItem(at: stagingURL, to: cacheURL)
        pruneStaleMaterializations(
            in: cacheParent,
            cacheName: cacheName,
            keeping: cacheURL
        )
        return cacheURL
    }

    private static func pruneStaleMaterializations(
        in cacheParent: URL,
        cacheName: String,
        keeping cacheURL: URL
    ) {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentModificationDateKey
        ]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheParent,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let prefix = "\(cacheName)-"
        let candidates = contents.filter { url in
            guard url.lastPathComponent.hasPrefix(prefix) else { return false }
            return (try? url.resourceValues(forKeys: resourceKeys).isDirectory) == true
        }
        let newestFirst = candidates.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(
                forKeys: resourceKeys
            ))?.contentModificationDate
            let rhsDate = (try? rhs.resourceValues(
                forKeys: resourceKeys
            ))?.contentModificationDate
            return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
        }

        var retainedPaths = Set([cacheURL.standardizedFileURL.path])
        for candidate in newestFirst where candidate.standardizedFileURL != cacheURL.standardizedFileURL {
            guard retainedPaths.count < retainedMaterializationsPerResource else {
                continue
            }
            retainedPaths.insert(candidate.standardizedFileURL.path)
        }
        for candidate in candidates where !retainedPaths.contains(candidate.standardizedFileURL.path) {
            try? fileManager.removeItem(at: candidate)
        }
    }

    private static func resourceCacheKey(for url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let size = values.fileSize ?? 0
        let modificationDate = Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        return "\(size)-\(modificationDate)"
    }

    private static func replaceNVNGXFiles(from root: URL, into destinationDirectory: URL) throws {
        let sourceURLs = try nvngxFileNames.map { name in
            guard let sourceURL = findFile(named: name, under: root) else {
                throw BundledOnlineGameResourceError.invalidArchive("NVNGX/\(name)")
            }
            return sourceURL
        }
        try replaceNVNGXFiles(from: sourceURLs, into: destinationDirectory)
    }

    private static func replaceNVNGXFiles(from sourceURLs: [URL], into destinationDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        for sourceURL in sourceURLs {
            let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                let backupURL = destinationURL.appendingPathExtension("orig")
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                } else {
                    try fileManager.moveItem(at: destinationURL, to: backupURL)
                }
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func findFile(named name: String, under root: URL) -> URL? {
        let directURL = root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let url as URL in enumerator
        where url.lastPathComponent == name {
            return url
        }
        return nil
    }

    private static func extract(archive: URL, into destination: URL) throws {
        let compressionFlag = archive.pathExtension.lowercased() == "xz" ? "-xJf" : "-xzf"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [compressionFlag, archive.path, "-C", destination.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BundledOnlineGameResourceError.extractionFailed(
                archive.lastPathComponent,
                process.terminationStatus
            )
        }
    }

    private static func findGStreamerRoot(in root: URL) -> URL? {
        if FileManager.default.fileExists(
            atPath: root.appendingPathComponent("GStreamer.framework", isDirectory: true).path
        ) {
            return root
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            if url.lastPathComponent == "GStreamer.framework" {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }
}
