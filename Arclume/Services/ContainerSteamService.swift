//
//  ContainerSteamService.swift
//  Procyon
//

import Foundation

nonisolated struct ContainerSteamLaunchRequest: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL
    let environmentOverrides: [String: String]
}

enum ContainerSteamRuntime {
    case crossOver(URL)
    case bundledWine
}

nonisolated protocol ContainerSteamProcessLaunching {
    @discardableResult
    func launch(_ request: ContainerSteamLaunchRequest) throws -> Process
}

nonisolated struct FoundationContainerSteamProcessLauncher: ContainerSteamProcessLaunching {
    @discardableResult
    func launch(_ request: ContainerSteamLaunchRequest) throws -> Process {
        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.currentDirectoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(
            request.environmentOverrides,
            uniquingKeysWith: { _, override in override }
        )
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}

nonisolated enum ContainerSteamServiceError: Error, Equatable, LocalizedError {
    case invalidAppID(Int)
    case invalidBottle(URL)
    case steamExecutableMissing(URL)
    case crossOverWineMissing(URL)

    var errorDescription: String? {
        switch self {
        case .invalidAppID(let appID):
            return L10n.format("Invalid Steam app ID: %@", String(appID))
        case .invalidBottle(let url):
            return L10n.format("Invalid CrossOver bottle: %@", url.path)
        case .steamExecutableMissing(let url):
            return L10n.format("Steam executable not found: %@", url.path)
        case .crossOverWineMissing(let url):
            return L10n.format("CrossOver Wine executable not found: %@", url.path)
        }
    }
}

nonisolated struct ContainerSteamService {
    static let standardSteamDirectoryComponents = [
        ["drive_c", "Program Files (x86)", "Steam"],
        ["drive_c", "Program Files", "Steam"],
    ]

    private let fileManager: FileManager
    private let processLauncher: any ContainerSteamProcessLaunching

    init(
        fileManager: FileManager = .default,
        processLauncher: any ContainerSteamProcessLaunching =
            FoundationContainerSteamProcessLauncher()
    ) {
        self.fileManager = fileManager
        self.processLauncher = processLauncher
    }

    func detect(in bottleURL: URL, steamOverride: URL? = nil) -> ContainerSteamDetection {
        let bottleURL = bottleURL.standardizedFileURL
        let candidates = executableCandidates(in: bottleURL, steamOverride: steamOverride)
        var matchingCandidateURL: URL?
        var detectedExecutableURL: URL?
        for candidate in candidates {
            if let resolvedURL = resolvedRegularFile(at: candidate) {
                matchingCandidateURL = candidate
                detectedExecutableURL = resolvedURL
                break
            }
        }
        guard let matchingCandidateURL, let steamExecutableURL = detectedExecutableURL else {
            return ContainerSteamDetection(
                bottleURL: bottleURL,
                status: .notFound,
                installation: nil,
                searchedExecutableURLs: candidates
            )
        }
        let overrideExecutableURL = steamOverride.map(normalizeOverride)
        let discoverySource: ContainerSteamDiscoverySource =
            matchingCandidateURL == overrideExecutableURL
            ? .override
            : .standard

        let steamRootURL = steamExecutableURL.deletingLastPathComponent()
        let configURL = steamRootURL.appendingPathComponent("config", isDirectory: true)
        let loginUsersURL = configURL.appendingPathComponent("loginusers.vdf")
        let loginUsersVDF = readVDF(at: loginUsersURL, rootKey: "users")
        let libraryFoldersVDF = readFirstVDF(
            at: [
                steamRootURL
                    .appendingPathComponent("steamapps", isDirectory: true)
                    .appendingPathComponent("libraryfolders.vdf"),
                configURL.appendingPathComponent("libraryfolders.vdf"),
            ],
            rootKey: "libraryfolders"
        )
        let users = parseUsers(loginUsersVDF.root)
        var libraries = parseLibraries(libraryFoldersVDF.root, bottleURL: bottleURL)

        if libraries.isEmpty {
            libraries = [defaultLibrary(steamRootURL: steamRootURL, bottleURL: bottleURL)]
        }

        let status: ContainerSteamDetectionStatus
        if loginUsersVDF.wasParsed && libraryFoldersVDF.wasParsed {
            status = .ready
        } else if loginUsersVDF.exists || libraryFoldersVDF.exists {
            status = .configured
        } else {
            status = .executableFound
        }

        let installation = ContainerSteamInstallation(
            bottleURL: bottleURL,
            steamRootURL: steamRootURL,
            steamExecutableURL: steamExecutableURL,
            discoverySource: discoverySource,
            users: users,
            libraries: libraries,
            hasLoginUsersConfiguration: loginUsersVDF.exists,
            hasLibraryFoldersConfiguration: libraryFoldersVDF.exists
        )

        return ContainerSteamDetection(
            bottleURL: bottleURL,
            status: status,
            installation: installation,
            searchedExecutableURLs: candidates
        )
    }

    func executableCandidates(in bottleURL: URL, steamOverride: URL? = nil) -> [URL] {
        var candidates: [URL] = []
        if let steamOverride {
            candidates.append(normalizeOverride(steamOverride))
        }
        candidates.append(
            contentsOf: Self.standardSteamDirectoryComponents.map { components in
                components.reduce(bottleURL.standardizedFileURL) { partial, component in
                    partial.appendingPathComponent(component, isDirectory: true)
                }.appendingPathComponent("Steam.exe")
            })

        var seenPaths = Set<String>()
        return candidates.filter { candidate in
            seenPaths.insert(candidate.standardizedFileURL.path.lowercased()).inserted
        }
    }

    func makeOpenSteamRequest(
        in installation: ContainerSteamInstallation,
        using crossOverAppURL: URL
    ) throws -> ContainerSteamLaunchRequest {
        try makeOpenSteamRequest(
            in: installation,
            using: .crossOver(crossOverAppURL)
        )
    }

    func makeOpenSteamRequest(
        in installation: ContainerSteamInstallation,
        using runtime: ContainerSteamRuntime
    ) throws -> ContainerSteamLaunchRequest {
        try makeLaunchRequest(
            in: installation,
            using: runtime,
            steamArguments: []
        )
    }

    func makeInstallRequest(
        appID: Int,
        in installation: ContainerSteamInstallation,
        using crossOverAppURL: URL
    ) throws -> ContainerSteamLaunchRequest {
        try makeInstallRequest(
            appID: appID,
            in: installation,
            using: .crossOver(crossOverAppURL)
        )
    }

    func makeInstallRequest(
        appID: Int,
        in installation: ContainerSteamInstallation,
        using runtime: ContainerSteamRuntime
    ) throws -> ContainerSteamLaunchRequest {
        guard appID > 0 else {
            throw ContainerSteamServiceError.invalidAppID(appID)
        }
        return try makeLaunchRequest(
            in: installation,
            using: runtime,
            steamArguments: ["steam://install/\(appID)"]
        )
    }

    @discardableResult
    func openSteam(
        in installation: ContainerSteamInstallation,
        using crossOverAppURL: URL
    ) throws -> Process {
        try processLauncher.launch(makeOpenSteamRequest(in: installation, using: crossOverAppURL))
    }

    @discardableResult
    func openSteam(
        in installation: ContainerSteamInstallation,
        using runtime: ContainerSteamRuntime
    ) throws -> Process {
        try processLauncher.launch(makeOpenSteamRequest(in: installation, using: runtime))
    }

    @discardableResult
    func install(
        appID: Int,
        in installation: ContainerSteamInstallation,
        using crossOverAppURL: URL
    ) throws -> Process {
        try processLauncher.launch(
            makeInstallRequest(appID: appID, in: installation, using: crossOverAppURL)
        )
    }

    @discardableResult
    func install(
        appID: Int,
        in installation: ContainerSteamInstallation,
        using runtime: ContainerSteamRuntime
    ) throws -> Process {
        try processLauncher.launch(
            makeInstallRequest(appID: appID, in: installation, using: runtime)
        )
    }

    private func makeLaunchRequest(
        in installation: ContainerSteamInstallation,
        using runtime: ContainerSteamRuntime,
        steamArguments: [String]
    ) throws -> ContainerSteamLaunchRequest {
        guard !installation.bottleURL.lastPathComponent.isEmpty else {
            throw ContainerSteamServiceError.invalidBottle(installation.bottleURL)
        }
        guard isRegularFile(installation.steamExecutableURL) else {
            throw ContainerSteamServiceError.steamExecutableMissing(installation.steamExecutableURL)
        }

        switch runtime {
        case .crossOver(let crossOverAppURL):
            let wineURL = crossOverAppURL
                .appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
            guard isRegularFile(wineURL) else {
                throw ContainerSteamServiceError.crossOverWineMissing(wineURL)
            }
            return ContainerSteamLaunchRequest(
                executableURL: wineURL,
                arguments: [
                    "--bottle",
                    installation.bottleURL.lastPathComponent,
                    installation.steamExecutableURL.path,
                ] + steamArguments,
                currentDirectoryURL: installation.steamRootURL,
                environmentOverrides: [
                    "CX_GRAPHICS_BACKEND": "d3dmetal",
                    "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "0",
                ]
            )
        case .bundledWine:
            guard BundledWineRuntime.ownsStandardSteamPrefix(installation.bottleURL),
                  BundledWineRuntime.isValidPrefix(at: installation.bottleURL)
            else {
                throw ContainerSteamServiceError.invalidBottle(installation.bottleURL)
            }
            let configuration = try BundledWineRuntime.makeDefaultLaunchConfiguration()
            var environment = configuration.environment
            environment["WINEPREFIX"] = installation.bottleURL.path
            return ContainerSteamLaunchRequest(
                executableURL: configuration.wineURL,
                arguments: [installation.steamExecutableURL.path] + steamArguments,
                currentDirectoryURL: installation.steamRootURL,
                environmentOverrides: environment
            )
        }
    }

    private func normalizeOverride(_ overrideURL: URL) -> URL {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: overrideURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            return overrideURL.appendingPathComponent("Steam.exe").standardizedFileURL
        }
        if overrideURL.pathExtension.caseInsensitiveCompare("exe") == .orderedSame {
            return overrideURL.standardizedFileURL
        }
        return overrideURL.appendingPathComponent("Steam.exe").standardizedFileURL
    }

    private func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private func resolvedRegularFile(at url: URL) -> URL? {
        if isRegularFile(url) {
            return url.standardizedFileURL
        }
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: url.deletingLastPathComponent(),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }
        return entries.first { entry in
            entry.lastPathComponent.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame
                && isRegularFile(entry)
        }?.standardizedFileURL
    }

    private func readVDF(at url: URL, rootKey: String) -> (
        root: [String: Any]?, exists: Bool, wasParsed: Bool
    ) {
        let exists = isRegularFile(url)
        guard exists, let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, exists, false)
        }
        let parsed = parseVDFToDict(from: contents)
        guard let root = dictionaryValue(in: parsed, forKey: rootKey) as? [String: Any] else {
            return (nil, true, false)
        }
        return (root, true, true)
    }

    private func readFirstVDF(
        at urls: [URL],
        rootKey: String
    ) -> (root: [String: Any]?, exists: Bool, wasParsed: Bool) {
        var existingResult: (root: [String: Any]?, exists: Bool, wasParsed: Bool)?
        for url in urls {
            let result = readVDF(at: url, rootKey: rootKey)
            if result.wasParsed {
                return result
            }
            if result.exists, existingResult == nil {
                existingResult = result
            }
        }
        return existingResult ?? (nil, false, false)
    }

    private func parseUsers(_ users: [String: Any]?) -> [ContainerSteamUser] {
        guard let users else { return [] }
        return users.compactMap { steamID, value -> ContainerSteamUser? in
            guard let user = value as? [String: Any] else { return nil }
            return ContainerSteamUser(
                steamID: steamID,
                accountName: stringValue(in: user, forKey: "AccountName") ?? "",
                personaName: stringValue(in: user, forKey: "PersonaName") ?? "",
                rememberPassword: boolValue(in: user, forKey: "RememberPassword"),
                mostRecent: boolValue(in: user, forKey: "MostRecent"),
                timestamp: stringValue(in: user, forKey: "Timestamp").flatMap(Int.init)
            )
        }.sorted { lhs, rhs in
            if lhs.mostRecent != rhs.mostRecent { return lhs.mostRecent }
            if lhs.rememberPassword != rhs.rememberPassword { return lhs.rememberPassword }
            if lhs.timestamp != rhs.timestamp { return (lhs.timestamp ?? 0) > (rhs.timestamp ?? 0) }
            return lhs.steamID < rhs.steamID
        }
    }

    private func parseLibraries(
        _ libraryFolders: [String: Any]?,
        bottleURL: URL
    ) -> [ContainerSteamLibrary] {
        guard let libraryFolders else { return [] }
        let sortedEntries = libraryFolders.sorted { lhs, rhs in
            if let left = Int(lhs.key), let right = Int(rhs.key) {
                return left < right
            }
            return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }

        var seen = Set<String>()
        return sortedEntries.compactMap { identifier, value -> ContainerSteamLibrary? in
            let path: String
            let label: String?
            let installedAppIDs: Set<Int>

            if let dictionary = value as? [String: Any],
                let dictionaryPath = stringValue(in: dictionary, forKey: "path")
            {
                path = dictionaryPath
                label = stringValue(in: dictionary, forKey: "label")?.nilIfEmpty
                let apps = dictionaryValue(in: dictionary, forKey: "apps") as? [String: Any]
                installedAppIDs = Set(apps?.keys.compactMap(Int.init) ?? [])
            } else if let stringPath = value as? String {
                path = stringPath
                label = nil
                installedAppIDs = []
            } else {
                return nil
            }

            let hostURL = resolveWindowsPath(path, in: bottleURL)
            let deduplicationKey =
                hostURL?.standardizedFileURL.path.lowercased() ?? path.lowercased()
            guard seen.insert(deduplicationKey).inserted else { return nil }
            return ContainerSteamLibrary(
                identifier: identifier,
                label: label,
                windowsPath: path,
                hostURL: hostURL,
                installedAppIDs: installedAppIDs
            )
        }
    }

    private func defaultLibrary(steamRootURL: URL, bottleURL: URL) -> ContainerSteamLibrary {
        ContainerSteamLibrary(
            identifier: "default",
            label: nil,
            windowsPath: windowsPath(for: steamRootURL, in: bottleURL),
            hostURL: steamRootURL,
            installedAppIDs: []
        )
    }

    private func resolveWindowsPath(_ rawPath: String, in bottleURL: URL) -> URL? {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        guard path.count >= 2 else { return nil }
        let start = path.startIndex
        let colon = path.index(after: start)
        guard path[colon] == ":" else { return nil }

        let drive = String(path[start]).lowercased() + ":"
        guard let driveRoot = driveRootURL(for: drive, in: bottleURL) else { return nil }
        let remainder = path[path.index(after: colon)...]
        let components = remainder.split { character in
            character == "\\" || character == "/"
        }
        return components.reduce(driveRoot) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: true)
        }.standardizedFileURL
    }

    private func driveRootURL(for drive: String, in bottleURL: URL) -> URL? {
        if drive.caseInsensitiveCompare("c:") == .orderedSame {
            return bottleURL.appendingPathComponent("drive_c", isDirectory: true)
                .standardizedFileURL
        }

        let linkURL =
            bottleURL
            .appendingPathComponent("dosdevices", isDirectory: true)
            .appendingPathComponent(drive.lowercased())
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path) {
            let target: URL
            if destination.hasPrefix("/") {
                target = URL(fileURLWithPath: destination, isDirectory: true)
            } else {
                target =
                    URL(
                        fileURLWithPath: destination,
                        isDirectory: true,
                        relativeTo: linkURL.deletingLastPathComponent()
                    ).absoluteURL
            }
            return target.standardizedFileURL.resolvingSymlinksInPath()
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: linkURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return nil
        }
        return linkURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func windowsPath(for hostURL: URL, in bottleURL: URL) -> String {
        let driveCURL = bottleURL.appendingPathComponent("drive_c", isDirectory: true)
            .standardizedFileURL
        let hostPath = hostURL.standardizedFileURL.path
        let driveCPath = driveCURL.path
        guard hostPath == driveCPath || hostPath.hasPrefix(driveCPath + "/") else {
            return hostPath
        }
        let relativePath = String(hostPath.dropFirst(driveCPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "\\")
        return relativePath.isEmpty ? "C:\\" : "C:\\\(relativePath)"
    }

    private func dictionaryValue(in dictionary: [String: Any], forKey key: String) -> Any? {
        dictionary.first(where: { candidate, _ in
            candidate.caseInsensitiveCompare(key) == .orderedSame
        })?.value
    }

    private func stringValue(in dictionary: [String: Any], forKey key: String) -> String? {
        dictionaryValue(in: dictionary, forKey: key) as? String
    }

    private func boolValue(in dictionary: [String: Any], forKey key: String) -> Bool {
        guard let value = stringValue(in: dictionary, forKey: key)?.lowercased() else {
            return false
        }
        return value == "1" || value == "true" || value == "yes"
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
