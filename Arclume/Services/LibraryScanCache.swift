import Foundation

/// Value-only bridge between disk scanning and the main-actor library model.
nonisolated struct LibraryManifestRecord: Codable, Sendable, Equatable {
    var fields: [String: String]
    var library: URL
    var gameURL: URL?
    var isNative: Bool
    var nativeLibrary: Bool?
    var appNames: [String]
    var bundleIdentifier: String?
    var manifestURL: URL?
    var contents: Data?
    var directoryExists: Bool = false

    @MainActor init(_ meta: GamesMeta) {
        fields = ["appid": meta.appid, "installdir": meta.installdir,
                  "BytesDownloaded": meta.BytesDownloaded ?? "0", "BytesToDownload": meta.BytesToDownload ?? "0"]
        fields["name"] = meta.name
        fields["StateFlags"] = meta.StateFlags
        fields["UpdateResult"] = meta.UpdateResult
        fields["BytesToStage"] = meta.BytesToStage
        fields["BytesStaged"] = meta.BytesStaged
        library = meta.libraryFolder
        gameURL = meta.gameURL
        isNative = meta.isNative
        nativeLibrary = meta.isFromNativeSteamLibrary
        appNames = meta.appNames
        bundleIdentifier = meta.nativeAppBundleIdentifier
    }

    init(fields: [String: String], library: URL, gameURL: URL, isNative: Bool,
         nativeLibrary: Bool, appNames: [String], bundleIdentifier: String?,
         manifestURL: URL, contents: Data, directoryExists: Bool) {
        self.fields = fields; self.library = library; self.gameURL = gameURL
        self.isNative = isNative; self.nativeLibrary = nativeLibrary; self.appNames = appNames
        self.bundleIdentifier = bundleIdentifier; self.manifestURL = manifestURL
        self.contents = contents; self.directoryExists = directoryExists
    }

    @MainActor func model() -> GamesMeta {
        let result = mapDictToGamesMeta(from: fields)
        result.libraryFolder = library
        result.gameURL = gameURL
        result.isNative = isNative
        result.isFromNativeSteamLibrary = nativeLibrary
        result.appNames = appNames
        result.nativeAppBundleIdentifier = bundleIdentifier
        return result
    }
}

/// Unchanged manifests reuse executable discovery, including across app launches.
/// A failed listing is not an empty library; callers retain their previous records.
actor SteamLibraryScanner {
    private var cached: [URL: LibraryManifestRecord] = [:]

    func seed(_ records: [LibraryManifestRecord]) {
        for record in records {
            if let url = record.manifestURL { cached[url] = record }
        }
    }

    func scan(_ folder: URL, native: Bool) throws -> [LibraryManifestRecord] {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let child = folder.appendingPathComponent("steamapps", isDirectory: true)
        let root = (folder.lastPathComponent.lowercased() == "steamapps" || !fm.fileExists(atPath: child.path))
            ? folder.standardizedFileURL : child.standardizedFileURL
        let files = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                               options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "acf" }.sorted { $0.path < $1.path }
        var result: [LibraryManifestRecord] = []
        for url in files {
            try Task.checkCancellation()
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8),
                      let state = parseVDFToDict(from: text)["AppState"] as? [String: Any],
                      let appID = state["appid"] as? String, Int(appID) != nil,
                      let directory = state["installdir"] as? String,
                      !directory.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                let gameURL = root.appendingPathComponent("common").appendingPathComponent(directory)
                // Malformed manifests must never send recursive discovery outside this library.
                guard gameURL.standardizedFileURL.path.hasPrefix(root.appendingPathComponent("common").path + "/")
                else { throw CocoaError(.fileReadCorruptFile) }
                let exists = fm.fileExists(atPath: gameURL.path)
                if let previous = cached[url], previous.contents == data,
                   previous.nativeLibrary == native, previous.directoryExists == exists {
                    result.append(previous)
                    continue
                }
                var fields = state.compactMapValues { $0 as? String }
                if !exists { fields["StateFlags"] = "0" }
                let applications = NativeApplicationBundleDetector.applications(in: gameURL)
                let isNative = native || !applications.isEmpty
                var names = applications.flatMap(\.processNames)
                if !isNative, let enumerator = fm.enumerator(at: gameURL, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let executable as URL in enumerator where executable.pathExtension.lowercased() == "exe" {
                        names.append(executable.lastPathComponent)
                    }
                }
                let record = LibraryManifestRecord(fields: fields, library: root, gameURL: gameURL,
                    isNative: isNative, nativeLibrary: native, appNames: Array(Set(names)).sorted(),
                    bundleIdentifier: applications.compactMap(\.bundleIdentifier).first,
                    manifestURL: url, contents: data, directoryExists: exists)
                cached[url] = record
                result.append(record)
            } catch is CancellationError { throw CancellationError() }
            catch {
                // Steam may be atomically replacing/writing a manifest. Retry next scan.
                if let previous = cached[url] { result.append(previous) }
            }
        }
        let present = Set(files)
        cached = cached.filter { $0.key.deletingLastPathComponent() != root || present.contains($0.key) }
        return result
    }
}

struct LibrarySnapshot: Codable {
    static let defaultsKey = "librarySnapshot.v1"
    var version = 1
    var context: String
    var games: [Game]
    var records: [LibraryManifestRecord]
    var metadata: [LibraryManifestRecord]
    var folders: [String]
    var ownership: [Int: Set<SteamClientKind>]
    var sessions: [SteamClientKind: String]

    static func read(from defaults: UserDefaults, context: String) -> Self? {
        guard let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.version == 1, snapshot.context == context else { return nil }
        return snapshot
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        if data != defaults.data(forKey: Self.defaultsKey) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

extension LibraryPageGlobals {
    func restoreSnapshot(context: String) {
        guard !hasLibrarySnapshot, !ArclumeTestEnvironment.isTesting,
              let defaults = UserDefaults(suiteName: suiteName),
              let snapshot = LibrarySnapshot.read(from: defaults, context: context) else { return }
        games = snapshot.games
        gamesMeta = snapshot.metadata.map { $0.model() }
        folders = snapshot.folders
        scanRecords = snapshot.records
        ownershipByAppID = snapshot.ownership
        ownershipSessionCacheKeys = snapshot.sessions
        hasLibrarySnapshot = true
    }

    func saveSnapshot(context: String) {
        guard !ArclumeTestEnvironment.isTesting, let defaults = UserDefaults(suiteName: suiteName) else { return }
        LibrarySnapshot(context: context, games: games, records: scanRecords,
            metadata: gamesMeta.map(LibraryManifestRecord.init), folders: folders,
            ownership: ownershipByAppID, sessions: ownershipSessionCacheKeys).save(to: defaults)
    }

    func applyScannedGames(_ updated: [Game]) {
        // Game contains legacy nested models. Compare their canonical persisted representation
        // instead of rebuilding every card when the scan has no changes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard (try? encoder.encode(games)) != (try? encoder.encode(updated)) else { return }
        let selectedWasScanned = selectedGame.map { selection in games.contains { $0.id == selection.id } } ?? false
        games = updated
        if let selectedGame, let replacement = updated.first(where: { $0.id == selectedGame.id }) {
            self.selectedGame = replacement
        } else if selectedWasScanned && !isLaunchingGame {
            showDetailView = false
            selectedGame = nil
        }
    }
}
