import Foundation
import CryptoKit

/// Prefix-scoped localization only; deliberately excludes JX3 keyboard,
/// debugger and graphics preferences.
nonisolated enum SteamContainerLocalization {
    static let fontFileName = "NotoSansCJKsc-Regular.otf"
    static let preparationRevision = 1
    static let preparationMarkerName = ".arclume-steam-fonts.json"

    struct PreparationStamp: Codable, Equatable, Sendable {
        let revision: Int
        let fontSHA256: String
        let runtimePath: String
        let runtimeVersion: String
        let runtimeModified: Date
        let prefixCreated: Date
    }

    static func preparationStamp(in bottle: URL, fontURL: URL, wineURL: URL,
                                 runtimeVersion: String) throws -> PreparationStamp {
        let manager = FileManager.default
        let wine = wineURL.resolvingSymlinksInPath()
        let wineAttributes = try manager.attributesOfItem(atPath: wine.path)
        let prefixAttributes = try manager.attributesOfItem(atPath: bottle.appendingPathComponent("drive_c/windows").path)
        guard let modified = wineAttributes[.modificationDate] as? Date,
              let created = prefixAttributes[.creationDate] as? Date else { throw CocoaError(.fileReadUnknown) }
        return PreparationStamp(revision: preparationRevision, fontSHA256: try digest(fontURL),
            runtimePath: wine.path, runtimeVersion: runtimeVersion, runtimeModified: modified, prefixCreated: created)
    }

    static func isPrepared(in bottle: URL, stamp: PreparationStamp) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: bottle.appendingPathComponent("system.reg").path),
              manager.fileExists(atPath: bottle.appendingPathComponent("user.reg").path),
              let data = try? Data(contentsOf: bottle.appendingPathComponent(preparationMarkerName)),
              let saved = try? JSONDecoder().decode(PreparationStamp.self, from: data), saved == stamp else { return false }
        return (try? digest(bottle.appendingPathComponent("drive_c/windows/Fonts/\(fontFileName)"))) == stamp.fontSHA256
    }

    static func markPrepared(in bottle: URL, stamp: PreparationStamp) throws {
        try JSONEncoder().encode(stamp).write(to: bottle.appendingPathComponent(preparationMarkerName), options: .atomic)
    }

    private static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func prepareFiles(in bottle: URL, fontURL: URL, fontLinks: String, fontSubstitutes: String) throws -> URL {
        let manager = FileManager.default
        guard manager.fileExists(atPath: bottle.appendingPathComponent("system.reg").path),
              manager.fileExists(atPath: bottle.appendingPathComponent("user.reg").path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fonts = bottle.appendingPathComponent("drive_c/windows/Fonts", isDirectory: true)
        try manager.createDirectory(at: fonts, withIntermediateDirectories: true)
        let target = fonts.appendingPathComponent(fontFileName)
        if !manager.contentsEqual(atPath: fontURL.path, andPath: target.path) {
            let staging = fonts.appendingPathComponent(".arclume-font-\(UUID().uuidString).otf")
            defer { try? manager.removeItem(at: staging) }
            try manager.copyItem(at: fontURL, to: staging)
            if manager.fileExists(atPath: target.path) {
                _ = try manager.replaceItemAt(target, withItemAt: staging)
            } else {
                try manager.moveItem(at: staging, to: target)
            }
        }

        let directory = manager.temporaryDirectory.appendingPathComponent("Arclume-SteamFonts-\(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        let registry = directory.appendingPathComponent("chinese-fonts.reg")
        do {
            // UTF-16LE BOM is understood by reg.exe in both Wine architectures.
            var data = Data([0xff, 0xfe])
            data.append(try registryText(fontLinks: fontLinks, fontSubstitutes: fontSubstitutes).data(using: .utf16LittleEndian)!)
            try data.write(to: registry, options: .atomic)
            return registry
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    // Real Latin families take precedence over FontSubstitutes in this Wine.
    // A substitution also disables SystemLink for that name. Remove only our
    // previous Noto substitutions, then prepend Noto to existing fallback lists.
    static let linkedFamilies = ["Tahoma", "Arial", "Segoe UI", "MS Sans Serif", "Microsoft Sans Serif", "System"]

    static func exportedValues(_ text: String) -> [String: String] {
        let lines = text.replacingOccurrences(of: "\\\r\n", with: "")
            .replacingOccurrences(of: "\\\n", with: "").components(separatedBy: .newlines)
        var values: [String: String] = [:]
        for line in lines where line.hasPrefix("\"") {
            guard let end = line.range(of: "\"=") else { continue }
            values[String(line[line.index(after: line.startIndex)..<end.lowerBound])] =
                String(line[end.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return values
    }

    static func registryText(fontLinks: String, fontSubstitutes: String) throws -> String {
        let existingLinks = exportedValues(fontLinks)
        let existingSubstitutes = exportedValues(fontSubstitutes)
        let aliases = ["MS Shell Dlg", "MS Shell Dlg 2", "SimSun", "NSimSun", "Microsoft YaHei", "Microsoft YaHei UI"]
        let substitutions = aliases.map { "\"\($0)\"=\"Noto Sans CJK SC\"" }.joined(separator: "\r\n")
        let cleanup = linkedFamilies.filter { existingSubstitutes[$0] == "\"Noto Sans CJK SC\"" }
            .map { "\"\($0)\"=-" }.joined(separator: "\r\n")
        let fallback = "\(fontFileName),Noto Sans CJK SC"
        let links = try linkedFamilies.map { family in
            var entries: [String] = []
            if let value = existingLinks[family] {
                guard value.hasPrefix("hex(7):") else { throw CocoaError(.fileReadCorruptFile) }
                let tokens = value.dropFirst(7).split(separator: ",")
                let bytes = tokens.compactMap { UInt8($0.trimmingCharacters(in: .whitespaces), radix: 16) }
                guard bytes.count == tokens.count, bytes.count.isMultiple(of: 2),
                      let decoded = String(data: Data(bytes), encoding: .utf16LittleEndian) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                entries = decoded.components(separatedBy: "\0").filter { !$0.isEmpty && $0.caseInsensitiveCompare(fallback) != .orderedSame }
            }
            let data = ([fallback] + entries).joined(separator: "\0") + "\0\0"
            let hex = data.data(using: .utf16LittleEndian)!.map { String(format: "%02x", $0) }.joined(separator: ",")
            return "\"\(family)\"=hex(7):\(hex)"
        }.joined(separator: "\r\n")
        return """
        Windows Registry Editor Version 5.00

        [HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]
        "Noto Sans CJK SC (OpenType)"="NotoSansCJKsc-Regular.otf"

        [HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes]
        \(substitutions)
        \(cleanup)

        [HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink]
        \(links)

        [HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\External Fonts]
        "Noto Sans CJK SC (TrueType)"="C:\\\\windows\\\\Fonts\\\\NotoSansCJKsc-Regular.otf"

        [HKEY_CURRENT_USER\\Software\\Wine\\Fonts]
        "Codepages"="936,936"

        [HKEY_CURRENT_USER\\Control Panel\\International]
        "Locale"="00000804"
        "LocaleName"="zh-CN"
        "sLanguage"="CHS"
        "sCountry"="China"
        "iCountry"="86"

        [HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Nls\\CodePage]
        "ACP"="936"
        "OEMCP"="936"
        "MACCP"="10008"

        [HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Nls\\Language]
        "Default"="0804"
        "InstallLanguage"="0804"

        """
    }
}
