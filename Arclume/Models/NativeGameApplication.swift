//
//  NativeGameApplication.swift
//  Procyon
//

import Foundation

nonisolated struct NativeGameApplication: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleIdentifier: String?

    var id: String {
        url.standardizedFileURL.path
    }

    @MainActor
    func makeGame() -> Game {
        var game = Game.emptyGame
        game.id = "native-app:\(id)"
        game.isNative = true
        game.isInstalled = true
        game.appNames = [url.lastPathComponent]
        game.appExeURL = url
        game.isCustom = true
        game.isNativeAppImport = true
        game.nativeAppBundleIdentifier = bundleIdentifier
        game.type = "game"
        game.name = name
        game.headerImage = ""
        game.platforms = Platforms(windows: false, mac: true, linux: false)
        return game
    }
}

nonisolated enum NativeGameScanner {
    static let gamesCategory = "public.app-category.games"

    static func scanStandardLocations(fileManager: FileManager = .default) -> [NativeGameApplication] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Applications",
                isDirectory: true
            )
        ]

        var seenPaths = Set<String>()
        var applications: [NativeGameApplication] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            let options: FileManager.DirectoryEnumerationOptions = [
                .skipsHiddenFiles,
                .skipsPackageDescendants
            ]
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: options
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                      let application = gameApplication(at: url),
                      seenPaths.insert(application.id).inserted
                else {
                    continue
                }
                applications.append(application)
            }
        }

        return applications.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func gameApplication(at url: URL) -> NativeGameApplication? {
        guard let bundle = Bundle(url: url),
              let category = bundle.object(
                forInfoDictionaryKey: "LSApplicationCategoryType"
              ) as? String,
              category.caseInsensitiveCompare(gamesCategory) == .orderedSame
        else {
            return nil
        }

        let displayName = (
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ) ?? (
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ) ?? url.deletingPathExtension().lastPathComponent

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        return NativeGameApplication(
            url: url.standardizedFileURL,
            name: name,
            bundleIdentifier: bundle.bundleIdentifier
        )
    }
}
