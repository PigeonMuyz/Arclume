//
//  NativeApplicationBundleDetector.swift
//  Procyon
//

import Foundation

struct NativeApplicationBundleInfo: Equatable {
    let url: URL
    let bundleIdentifier: String?
    let executableName: String?
    let displayName: String?

    var processNames: [String] {
        let candidates = [
            displayName,
            executableName,
            url.lastPathComponent,
            url.deletingPathExtension().lastPathComponent,
        ]
        .compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var seen = Set<String>()
        return candidates.filter {
            seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
        }
    }
}

enum NativeApplicationBundleDetector {
    static func application(at url: URL, fileManager: FileManager = .default) -> NativeApplicationBundleInfo? {
        let url = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        let infoURLs = [
            url
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Info.plist", isDirectory: false),
            // PlayCover and other iOS-style app bundles keep Info.plist at the
            // package root instead of using the standard macOS Contents layout.
            url.appendingPathComponent("Info.plist", isDirectory: false),
        ]
        guard let data = infoURLs.lazy.compactMap({ try? Data(contentsOf: $0) }).first,
              let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let info = propertyList as? [String: Any]
        else {
            return nil
        }

        let packageType = stringValue(info["CFBundlePackageType"])
        let executableName = stringValue(info["CFBundleExecutable"])
        let isAppBundle = packageType?.caseInsensitiveCompare("APPL") == .orderedSame
            || url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        guard isAppBundle, executableName != nil else { return nil }

        return NativeApplicationBundleInfo(
            url: url,
            bundleIdentifier: stringValue(info["CFBundleIdentifier"]),
            executableName: executableName,
            displayName: stringValue(info["CFBundleDisplayName"])
                ?? stringValue(info["CFBundleName"])
        )
    }

    static func applications(
        in rootURL: URL,
        fileManager: FileManager = .default
    ) -> [NativeApplicationBundleInfo] {
        let rootURL = rootURL.standardizedFileURL
        var applications: [NativeApplicationBundleInfo] = []
        var seenPaths = Set<String>()

        func append(_ application: NativeApplicationBundleInfo?) {
            guard let application,
                  seenPaths.insert(application.url.standardizedFileURL.path).inserted
            else {
                return
            }
            applications.append(application)
        }

        // Some Steam macOS depots are extensionless app bundles. Stardew Valley,
        // for example, installs as "Stardew Valley/Contents/Info.plist" rather
        // than "Stardew Valley.app".
        append(application(at: rootURL, fileManager: fileManager))

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return applications
        }

        for case let candidate as URL in enumerator where
            candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        {
            append(application(at: candidate, fileManager: fileManager))
        }
        return applications
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
