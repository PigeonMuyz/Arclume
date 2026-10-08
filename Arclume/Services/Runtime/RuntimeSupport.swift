//
//  RuntimeSupport.swift
//  Arclume
//
//  Created by Italo Mandara on 26/03/2026.
//
import Foundation

let D3DM_CACHE_FOLDER = "d3dm"
nonisolated private let applicationSupportDirectoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
private let legacySupportFolderURL = applicationSupportDirectoryURL.appendingPathComponent("Procyon", isDirectory: true)
private let legacyLogsFolderURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
    .first!
    .appendingPathComponent("Logs/Procyon", isDirectory: true)

nonisolated let ARCLUME_SUPPORT_FOLDER_URL = applicationSupportDirectoryURL.appendingPathComponent("Arclume", isDirectory: true)
let OSVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

/// Moves data from previous app versions into Arclume without duplicating a Bottle or
/// Games container. Both paths share the same parent volume, so each move is a
/// filesystem rename. If an Arclume directory already exists, only missing
/// top-level entries are moved; conflicting entries are left untouched.
func migrateLegacyAppDataIfNeeded() {
    guard UserDefaults(suiteName: suiteName)?.bool(forKey: ArclumeResetService.skipLegacyDataKey) != true else { return }
    migrateLegacyDirectory(
        from: legacySupportFolderURL,
        to: ARCLUME_SUPPORT_FOLDER_URL
    )

    let arclumeLogsFolderURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("Logs/Arclume", isDirectory: true)
    migrateLegacyDirectory(
        from: legacyLogsFolderURL,
        to: arclumeLogsFolderURL
    )
}

@discardableResult
func migrateLegacyDirectory(from source: URL, to destination: URL) -> Bool {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: source.path) else { return false }

    do {
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: source, to: destination)
            console.log("Migrated legacy app data to \(destination.path)")
            return true
        }

        let children = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for child in children {
            let target = destination.appendingPathComponent(child.lastPathComponent, isDirectory: true)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.moveItem(at: child, to: target)
        }

        if (try? fileManager.contentsOfDirectory(atPath: source.path).isEmpty) == true {
            try fileManager.removeItem(at: source)
        }
        return true
    } catch {
        console.error("Could not migrate legacy app data: \(error.localizedDescription)")
        return false
    }
}

func darwinUserCacheDir() -> URL? {
    var buf = [CChar](repeating: 0, count: 1024)
    let success = confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count) >= 0
    guard success else { return nil }
    return URL(fileURLWithFileSystemRepresentation: &buf, isDirectory: true, relativeTo: nil)
}

enum DeleteStatus {
    case failed
    case success
    case idle
    case progress
}

func removeD3DMetalCaches() -> DeleteStatus {
    let f = FileManager.default
    do {
        let d3dmPath = darwinUserCacheDir()!.appendingPathComponent(D3DM_CACHE_FOLDER, isDirectory: true).path

        let _items = try f.contentsOfDirectory(atPath: d3dmPath)
        let items = try _items.filter { d3dmPath in
                let pattern = try Regex(#"^.*\.exe$"#)
                return d3dmPath.contains(pattern)
        }
        for itemPath in items {
            console.log("Deleting \(itemPath)")
            try f.removeItem(atPath: d3dmPath + "/"  + itemPath)
        }
    } catch {
        console.log(error.localizedDescription)
        return DeleteStatus.failed
    }

    return DeleteStatus.success
}
