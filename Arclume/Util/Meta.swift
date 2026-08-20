//
//  Meta.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//

import Foundation

func getGamesMeta(from: URL, isNativeSteamLibrary: Bool = false) throws -> [GamesMeta] {
    /**
     scans a folder and returns an array of steam games meta
    */
    var array: [GamesMeta] = []
    let scanURL = steamAppsFolderURL(for: from) ?? from.standardizedFileURL
    try withSecurityScope(for: from) {
        let f = FileManager.default
        let urls = try f.contentsOfDirectory(at: scanURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]).filter { $0.pathExtension.caseInsensitiveCompare("acf") == .orderedSame }
        try urls.forEach { url in
            let file  = try readFile(at: url)
            let parsed = parseVDFToDict(from: file)
            let meta = mapDictToGamesMeta(from: parsed["AppState"] as! [String: Any])
            meta.gameURL = scanURL.appendingPathComponent("common").appendingPathComponent(meta.installdir)
            let nativeApplications = NativeApplicationBundleDetector.applications(in: meta.gameURL!)
            meta.isFromNativeSteamLibrary = isNativeSteamLibrary
            meta.isNative = isNativeSteamLibrary
                || (meta.isDownloaded() && !nativeApplications.isEmpty)
            meta.appNames = getAppNames(isNative: meta.isNative, gameURL: meta.gameURL)
            meta.nativeAppBundleIdentifier = nativeApplications
                .compactMap(\.bundleIdentifier)
                .first
            meta.libraryFolder = scanURL
            array.append(meta)
        }
    }
    return array
}

func getMeta(_ gameMetaArray: [GamesMeta], byID: String) -> GamesMeta? {
    /**
     find the corresponding meta by id where the id is the unique id and not the steam app id
     */
    return gameMetaArray.first(where: { $0.id == byID })
}

func mapDictToGamesMeta(from: [String:Any]) -> GamesMeta {
    let meta = GamesMeta(
        appid: from["appid"] as? String ?? "unknown",
        installdir: from["installdir"] as? String ?? "",
        bytesDownloaded: from["BytesDownloaded"] as? String ?? "0",
        BytesTodownload: from["BytesToDownload"] as? String ?? "0"
    )
    meta.name = from["name"] as? String
    meta.StateFlags = from["StateFlags"] as? String
    meta.UpdateResult = from["UpdateResult"] as? String
    meta.BytesToStage = from["BytesToStage"] as? String
    meta.BytesStaged = from["BytesStaged"] as? String
    return meta
}
