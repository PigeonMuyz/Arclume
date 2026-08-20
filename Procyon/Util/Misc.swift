//
//  Util.swift
//  Procyon
//
//  Created by Italo Mandara on 03/02/2026.
//

import UniformTypeIdentifiers
import Combine

let AUTOFILL_CUSTOM_GAME_ENABLED: Bool = {
    let env = ProcessInfo.processInfo.environment["PROCYON_AUTOFILL_CUSTOM_GAME_ENABLED"]?.lowercased()
    switch env {
    case "1", "true", "yes":
        return true
    case "0", "false", "no":
        return false
    default:
        return false
    }
}()

let LIB_ROOT = "lib64"

let DEFAULT_BOTTLE_PATH = "Library/Application Support/CrossOver/Bottles/"
// A Steam library manifest is the source of truth for a locally installed app.
// Do not hide apps here: demos and Steam tools need to remain discoverable.
let BLACKLIST: Set<String> = []
let DEBUG_ENABLED: Bool = {
    let env = ProcessInfo.processInfo.environment["PROCYON_DEBUG"]?.lowercased()
    switch env {
    case "1", "true", "yes":
        return true
    case "0", "false", "no":
        return false
    default:
        return false
    }
}()
let useLogger: Bool = false

func prettyPrinted(dict: Dictionary<String, Any>) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
       let str = String(data: data, encoding: .utf8) {
        return str
    }
    return "{}"
}

func steamAppsFolderURL(for url: URL) -> URL? {
    let candidate = url.standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        return nil
    }

    if candidate.lastPathComponent.caseInsensitiveCompare("steamapps") == .orderedSame {
        return candidate
    }

    let nestedSteamApps = candidate.appendingPathComponent("steamapps", isDirectory: true)
    if FileManager.default.fileExists(atPath: nestedSteamApps.path, isDirectory: &isDirectory),
       isDirectory.boolValue {
        return nestedSteamApps.standardizedFileURL
    }

    // Also accept a non-standard folder that already contains manifests.
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: candidate,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
    ) else {
        return nil
    }
    return entries.contains(where: { extractAppIDRegex(from: $0.lastPathComponent) != nil })
        ? candidate
        : nil
}

@discardableResult
func addSteamFolderPaths(_ url: URL) -> URL? {
    guard let steamAppsURL = steamAppsFolderURL(for: url) else {
        console.warn("\(url.path()) is not a Steam library or steamapps folder")
        return nil
    }

    do {
        let ids = try getIDsFromFolder(dest: steamAppsURL)
        if ids.isEmpty {
            console.warn("\(steamAppsURL) has no installed games")
        }
    } catch {
        console.warn("Failed to validate steam folder \(steamAppsURL.path())")
        console.error(String(reflecting: error))
        return nil
    }

    do {
        try persistFolderAccess(url: steamAppsURL)
        return steamAppsURL
    } catch {
        console.error("Failed to save steam folder")
        console.error(String(reflecting: error))
        return nil
    }
}

func removeSteamFolderPath(_ path: String) {
    let url = URL(string: path)!
    removePersistedFolderAccess(url: url)
}

func getSteamFolderPaths() -> [String] {
    return resolvePersistedFolders().map { $0.absoluteString }
}

func extractAppIDRegex(from filename: String) -> String? {
    let pattern = #"^appmanifest_(\d+)\.acf$"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
    guard let match = regex?.firstMatch(in: filename, options: [], range: range),
          match.numberOfRanges == 2,
          let idRange = Range(match.range(at: 1), in: filename) else { return nil }
    return String(filename[idRange])
}

func extractFolderNameRegex(_ path: String) -> String {
    let pattern = #"^file:\/\/\/Volumes\/(.+)\/steamapps\/$"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let decodedpath = path.removingPercentEncoding ?? path
    let range = NSRange(decodedpath.startIndex..<decodedpath.endIndex, in: decodedpath)
    guard let match = regex?.firstMatch(in: decodedpath, options: [], range: range),
          match.numberOfRanges == 2,
          let idRange = Range(match.range(at: 1), in: decodedpath) else { return decodedpath }
    return String(decodedpath[idRange])
}

//let id = extractAppIDRegex(from: "appmanifest_8870.acf") // "8870"

func getIDsFromFolder(dest: URL) throws -> [String] {
    /**
     scans a folder and returns an array of steam games ids
     */
//    try withSecurityScope(for: dest) {
        let f = FileManager.default
        let scanURL = steamAppsFolderURL(for: dest) ?? dest.standardizedFileURL
        let urls = try f.contentsOfDirectory(at: scanURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        return urls
        .filter { acfFileURL in
            acfFileURL.pathExtension.caseInsensitiveCompare("acf") == .orderedSame
        }
        .map { acfFileURL in
            extractAppIDRegex(from: acfFileURL.lastPathComponent) ?? "0"
        }
        .filter {
            gameID in !BLACKLIST.contains(gameID)
        }
//    } ?? []
}

func getIsNative(fromURL: URL) -> Bool {
    !NativeApplicationBundleDetector.applications(in: fromURL).isEmpty
}

func safeShell(_ command: String) throws {
    if DEBUG_ENABLED {
        console.log(try safeShellWithOutput(command))
        return
    }
    let task = Process()
    
    task.standardInput = FileHandle.nullDevice
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")

    try task.run()
}

func safeShellWithOutput(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()
    
    task.standardInput = nil
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")

    try task.run()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    return output
}

let DEFAULT_STEAM_MAC_PATH = "/Library/Application Support/Steam/"
let DEFAULT_STEAM_MAC_CONFIG_PATH = DEFAULT_STEAM_MAC_PATH + "config/"
let DEFAULT_STEAM_WINE_PATH = "/drive_c/Program Files (x86)/Steam/"
let DEFAULT_STEAM_WINE_CONFIG_PATH = DEFAULT_STEAM_WINE_PATH + "config/"

func getSteamUserID (usingURL: URL) -> String? {
    let steamLoginUsersPath = usingURL.appendingPathComponent("loginusers.vdf")
    guard let steamSettingsFile = try? String(contentsOfFile: steamLoginUsersPath.path(percentEncoded: false), encoding: .utf8) else { return nil }
    let parsed = parseVDFToDict(from: steamSettingsFile)
    let users = parsed["users"] as? [String: Any]
    return users?.keys.first?.description
}

func getSteamUserDataFallback (usingPath: URL) -> UserInfo? {
    let steamLoginUsersPath = usingPath.appendingPathComponent("loginusers.vdf")
    guard let steamSettingsFile = try? String(contentsOfFile: steamLoginUsersPath.path(percentEncoded: false), encoding: .utf8) else { return nil }
    let parsed = parseVDFToDict(from: steamSettingsFile)
    let users = parsed["users"] as? [String: Any]
    if let key = users?.keys.first {
        let user = users![key] as? [String: Any]
        let personaName = user?["PersonaName"] as? String ?? ""
        let avatar = usingPath
            .appendingPathComponent(DEFAULT_STEAM_WINE_CONFIG_PATH)
            .appendingPathComponent("avatarcache")
            .appendingPathComponent(key)
            .appendingPathExtension("png")
            .absoluteString
        let fallbackProfileData = UserInfo(
            steamID: "",
            communityVisibilityState: 0,
            profileState: 0,
            personaName: personaName,
            profileURL: "",
            avatar: avatar,
            avatarMedium: avatar,
            avatarFull: avatar,
            avatarHash: "",
            lastLogOff: 0,
            personaState: 0,
            primaryClanID: "",
            timeCreated: 0,
            personaStateFlags: 0,
            locCountryCode: nil,
            locStateCode: nil
        )
        return fallbackProfileData
    }
    return nil
}

func getSteamLibraryFolders(bottleURL: URL, from: URL) -> [URL] {
    let f = FileManager.default
    var steamLibraries: [URL] = []
    let drives = getBottleDrives(bottleURL: bottleURL)
    console.log("drives: \(String(describing: drives))")
    let steamSettingsPaths = [
        from.appendingPathComponent("libraryfolders.vdf"),
        f.homeDirectoryForCurrentUser
            .appendingPathComponent(DEFAULT_STEAM_MAC_CONFIG_PATH)
            .appendingPathComponent("libraryfolders.vdf")
    ].filter{ f.fileExists(atPath: $0.path(percentEncoded: false)) }
    for steamSettingsPath in steamSettingsPaths {
        do {
            let steamSettingsFile = try String(contentsOfFile: steamSettingsPath.path(percentEncoded: false), encoding: .utf8)
            let parsed = parseVDFToDict(from: steamSettingsFile)
            if let libraries = parsed["libraryfolders"] as? [String: Any] {
                for (_, value) in libraries { // Refactor this mess
                    if let val = (value as? [String: Any]) {
                        if let path = val["path"] as? String{
                            let driveAlias = String(path.split(separator: ":\\")[0]) + ":"
                            let splitPath = path.split(separator: ":")
                            if (splitPath.count > 1){
                                let partial = splitPath[1].replacingOccurrences(of: "\\\\", with: "/")
                                if let newPath = drives[driveAlias]?.appendingPathComponent(partial).appendingPathComponent("/steamapps") {
                                    steamLibraries.append(newPath)
                                } else {
                                    console.log("couldn't find Windows Steam config")
                                }
                            } else {
                                let macNewPath = URL(fileURLWithPath: path).appendingPathComponent("/steamapps")
                                steamLibraries.append(macNewPath)
                            }
                        }
                    }
                }
            }
        } catch {
            console.error(String(reflecting: error))
            return []
        }
    }
    console.log("all steam libraries \(steamLibraries.debugDescription)")
    return steamLibraries
}

func validateAddSteamFolder(_ url: URL, to folders: inout [String]) {
    guard let steamAppsURL = addSteamFolderPaths(url) else {
        return
    }
    let steamAppsPath = steamAppsURL.absoluteString
    if folders.contains(steamAppsPath) {
        console.log("\(steamAppsPath) folder exists!")
        return
    }
    folders.append(steamAppsPath)
}

func mapPersonaState(_ state: Int) -> String {
    let states = [
        L10n.string("Offline"),
        L10n.string("Online"),
        L10n.string("Busy"),
        L10n.string("Away"),
        L10n.string("Snooze"),
        L10n.string("Looking to trade"),
        L10n.string("Looking to play")
    ]
    if (0..<states.count).contains(state){
        return states[state]
    }
    return L10n.string("Unknown")
}

func localizedSteamContentType(_ type: String) -> String {
    switch type.lowercased() {
    case "game":
        return L10n.string("Game")
    case "demo":
        return L10n.string("Demo")
    case "tool":
        return L10n.string("Steam tool")
    case "dlc":
        return L10n.string("DLC")
    case "mod":
        return L10n.string("Mod")
    case "video":
        return L10n.string("Video")
    default:
        return type
    }
}

func getAppNames(isNative: Bool, gameURL: URL?) -> [String] {
    let f = FileManager.default
    var results: [String] = []
    if(gameURL == nil) {
        return []
    }

    if isNative {
        return NativeApplicationBundleDetector.applications(in: gameURL!, fileManager: f)
            .flatMap(\.processNames)
            .reduce(into: [String]()) { names, candidate in
                guard !names.contains(where: {
                    $0.caseInsensitiveCompare(candidate) == .orderedSame
                }) else {
                    return
                }
                names.append(candidate)
            }
    }

    guard let enumerator = f.enumerator(at: gameURL!, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
        return []
    }
    for case let fileURL as URL in enumerator  {
        if(fileURL.pathExtension.caseInsensitiveCompare("exe") == .orderedSame) {
            results.append(fileURL.lastPathComponent)
        }
    }
    return results
}

private struct SteamCloudSyncWatcher {
    private let appID: Int
    private let logURL: URL
    private let startingByteCount: Int

    init?(appID: Int, steamRootURL: URL) {
        let logURL = steamRootURL.appendingPathComponent("logs/cloud_log.txt")
        guard FileManager.default.fileExists(atPath: logURL.path) else { return nil }

        self.appID = appID
        self.logURL = logURL
        self.startingByteCount = (try? Data(contentsOf: logURL).count) ?? 0
    }

    func waitForCompletion() async {
        let appMarker = "[AppID \(appID)]"
        let deadline = Date().addingTimeInterval(60)

        while Date() < deadline {
            if let data = try? Data(contentsOf: logURL) {
                let offset = min(startingByteCount, data.count)
                let newLogContent = String(
                    decoding: Data(data.dropFirst(offset)),
                    as: UTF8.self
                )
                if newLogContent.split(separator: "\n").contains(where: {
                    $0.contains(appMarker) && $0.contains("Successfully synced")
                }) {
                    console.log("\(appID): Steam Cloud sync complete")
                    return
                }
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        console.warn("\(appID): Steam Cloud sync timed out")
    }
}

func getGameTracker(
    appNames: [String],
    cxAppPath: String?,
    bottleName: String,
    onLoad: @escaping () -> Void,
    onTerminate: @escaping () -> Void,
    isNative: Bool,
    stopSteamOnTermination: Bool = true,
    steamAppID: Int? = nil,
    steamRootURL: URL? = nil,
    minimumStableDuration: UInt64 = 0
) async throws -> TerminationObserver {
    let cloudSyncWatcher = !isNative
        ? steamAppID.flatMap { appID in
            steamRootURL.flatMap { SteamCloudSyncWatcher(appID: appID, steamRootURL: $0) }
        }
        : nil
    let tOb = TerminationObserver(then: { output in
        console.log(output.userInfo?.description ?? "no userInfo")
        let terminatedAppProcessName = output.userInfo?[AnyHashable("NSApplicationName")] as? String ?? "unknown"
        let terminatedAppPath = output.userInfo?[AnyHashable("NSApplicationPath")] as? String ?? "unknown"
        let terminatedAppName = String(terminatedAppPath.split(separator: "/").last ?? "unknown")
        if (appNames.contains(terminatedAppName) || appNames.contains(terminatedAppProcessName)) {
            console.log("\(appNames) -> \(terminatedAppName) or \(terminatedAppProcessName) has been terminated, closing steam...")
            Task {
                if stopSteamOnTermination {
                    if let cloudSyncWatcher {
                        await cloudSyncWatcher.waitForCompletion()
                    }
                    do {
                        try await quitSteam(
                            cxAppPath: cxAppPath ?? "",
                            bottleName: bottleName,
                            isNative: isNative
                        )
                        if !isNative {
                            try await closeWineActivities()
                        }
                    } catch {
                        console.error("Failed to stop game runtime: \(String(reflecting: error))")
                    }
                }
                onTerminate()
                console.log("onTerminate() was called")
            }
        }
    })
    try await trackPlaying(apps: appNames, then: {
        console.log("found game \(appNames.joined(separator: ", ")), loading...")
        onLoad()
    }, onTimeout: {
        console.log("\(appNames.joined(separator: ", ")), timeout...")
        onTerminate()
    }, isNative: isNative, minimumStableDuration: minimumStableDuration)
    return tOb
}

func isSameFile(_ file1URL: URL, _ file2URL: URL) -> Bool {
    let f = FileManager.default
    do {
        let attrs1 = try f.attributesOfItem(atPath: file1URL.path())
        let attrs2 = try f.attributesOfItem(atPath: file2URL.path())
        let sameSize = attrs1[.size] as? Int == attrs2[.size] as? Int
        let sameDate = attrs1[.modificationDate] as? Date == attrs2[.modificationDate] as? Date
        if(sameSize && sameDate) {
            // just comparing attributes for now
            return true
        }
    } catch {
        console.error("couldn't get file attributes")
        console.error(String(reflecting: error))
        return false
    }
    return false
}

func getSystemWOW64URL(from: URL) -> URL {
    return from
        .appending(path: "drive_c")
        .appending(path: "windows")
        .appending(path: "syswow64")
}

func getSystem32URL(from: URL) -> URL {
    return from
        .appending(path: "drive_c")
        .appending(path: "windows")
        .appending(path: "system32")
}

func cpyd8d9DLLs(to url: URL, enable: Bool = true) throws -> Void {
    let f = FileManager.default
    let files = ["d3d9.dll", "d3d8.dll"]
    
    func copyByBitness(dllsUrl: URL, file: String, is32Bit: Bool) throws {
        let dllPathComponentByBitness = "drive_c" + (is32Bit ? "/windows/SysWOW64": "/windows/System32")
        let dllPath = dllsUrl.appendingPathComponent(file)
        let dllDest = url.appendingPathComponent(dllPathComponentByBitness).appendingPathComponent(file) // the logic seems flipped but it's actually how the winwos logic works System32 is for 64 bits libs
        console.log("\(file) exists")
        if(enable) {
            if(!isSameFile(dllPath, dllDest)){
                if(!f.fileExists(atPath: dllDest.appendingPathExtension("old").path())){
                    try? f.moveItem(at: dllDest, to: dllDest.appendingPathExtension("old"))
                } else {
                    try? f.removeItem(at: dllDest)
                }
                try f.copyItem(at: dllPath, to: dllDest)
            } else {
                console.log("already patched with the latest dx9 skipping copy")
            }
        } else {
            if(!f.fileExists(atPath: dllDest.path())){
                try? f.removeItem(at: dllDest)
            }
            try f.copyItem(at: dllDest.appendingPathExtension("old"), to: dllDest)
        }
        
    }
    
    for file in files {
        if let dllsUrl = Bundle.main.url(forResource: "d9vk/x32", withExtension: nil) {
            try copyByBitness(dllsUrl: dllsUrl, file: file, is32Bit: true)
        } else {
            console.log("Couldn't find \(file)")
        }
        if let dllsUrl = Bundle.main.url(forResource: "d9vk/x64", withExtension: nil) {
            try copyByBitness(dllsUrl: dllsUrl, file: file, is32Bit: false)
        } else {
            console.log("Couldn't find \(file)")
        }
    }
}

class TarDownloader: NSObject, URLSessionDownloadDelegate {
    /**
     Class that takes 3 mandatory arguments
     fromUrl: the http url from where we download
     onProgress: (Double) called as the download progresses progress is passed to the function
     onComplete: (URL) called when download + extraction is complete the URL
     onError: (Error) called at any point there's an error
     */
    var fromUrl: URL
    var downloadDir: URL
    private let fallbackURLs: [URL]
    private let asset: DependencyAsset?
    private let useManualArchive: Bool
    private var candidateIndex = 0
    private var session: URLSession?
    var onProgress: (Double) -> Void
    var onComplete: (URL) -> Void
    var onError: (Error) -> Void
    
    init(
        fromUrl: URL,
        fallbackURLs: [URL] = [],
        asset: DependencyAsset? = nil,
        useManualArchive: Bool = true,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (URL) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.downloadDir = TarDownloader.getDownloadsDir()
        self.fromUrl = fromUrl
        self.fallbackURLs = fallbackURLs
        self.asset = asset
        self.useManualArchive = useManualArchive
        self.onProgress = onProgress
        self.onError = onError
        self.onComplete = onComplete
        super.init()
    }
    
    public static func getDownloadsDir() -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("\(appName)/downloads")
    }
    
    public static func deleteAllDownloadCache() {
        let downloadDir = TarDownloader.getDownloadsDir()
        try? FileManager.default.removeItem(at: downloadDir)
        deleteUsrDefOptionStartsWith(prefix: "downloads")
    }
    
    func download() {
        let f = FileManager.default
        try? f.createDirectory(at: downloadDir, withIntermediateDirectories: true, attributes: nil)
        if useManualArchive, let manualArchive = asset.flatMap(DependencyArchiveStore.importedArchive(for:)) {
            extract(manualArchive, sourceDescription: "manual import")
            return
        }
        startDownload()
    }

    private func startDownload() {
        console.log(self.fromUrl.debugDescription)
        if let lastDownloadedPath = readUsrDefOptionString(key: cacheKey) {
            if lastDownloadedPath == self.fromUrl.path(percentEncoded: false) {
                console.log("download cache found, skipping download")
                return self.onComplete(self.downloadDir)
            }
        }
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        session?.downloadTask(with: fromUrl).resume()
    }
    
    private var cacheKey: String {
        namespacedKey("downloads", asset?.rawValue ?? fromUrl.lastPathComponent)
    }

    private func extract(_ archiveURL: URL, sourceDescription: String) {
        DispatchQueue.global(qos: .utility).async {
            do {
                try SafeArchiveExtractor.extract(archiveURL, to: self.downloadDir)
                DispatchQueue.main.async {
                    self.onProgress(100)
                    self.onComplete(self.downloadDir)
                }
            } catch {
                console.error("Archive extraction failed for \(sourceDescription): \(String(reflecting: error))")
                DispatchQueue.main.async {
                    if sourceDescription == "manual import" {
                        self.onError(error)
                    } else {
                        self.tryNextDownload(after: error)
                    }
                }
            }
        }
    }

    private func tryNextDownload(after error: Error) {
        guard candidateIndex < fallbackURLs.count else {
            onError(error)
            return
        }
        fromUrl = fallbackURLs[candidateIndex]
        candidateIndex += 1
        startDownload()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100
        DispatchQueue.main.async {
            self.onProgress(progress) // percentage
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let f = FileManager.default
        let destination = downloadDir.appendingPathComponent(fromUrl.lastPathComponent)
        
        do {
            if f.fileExists(atPath: destination.path) {
                try f.removeItem(at: destination)
            }
            try f.moveItem(at: location, to: destination)
            persistUsrDefOptionString(key: cacheKey, value: fromUrl.path(percentEncoded: false))
            extract(destination, sourceDescription: fromUrl.absoluteString)
        } catch {
            DispatchQueue.main.async { self.tryNextDownload(after: error) }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            DispatchQueue.main.async { self.tryNextDownload(after: error) }
        }
    }
    
    func clearTemp() {
        try? FileManager.default.removeItem(at: downloadDir )
    }
}
