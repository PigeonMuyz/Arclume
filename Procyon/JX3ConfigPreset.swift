//
//  JX3ConfigPreset.swift
//  Procyon
//

import Foundation
import CoreFoundation

struct JX3ConfigPresetImportResult {
    let configURL: URL
}

enum JX3ConfigPresetError: LocalizedError {
    case sourceNotFound
    case unsupportedEncoding
    case invalidPreset
    case gameDirectoryNotFound

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            "找不到要导入的 config.ini 文件。"
        case .unsupportedEncoding:
            "这个 INI 不是 UTF-8 或简体中文（GBK/GB18030）编码，暂时无法安全导入。"
        case .invalidPreset:
            "这不是完整的剑网3画质 config.ini（缺少 [Main] 或 [KG3DENGINE] 段）。"
        case .gameDirectoryNotFound:
            "未找到剑网3客户端目录，请先完成启动器或游戏导入。"
        }
    }
}

enum JX3ConfigPresetImporter {
    static let recommendedConfigResourceName = "jx3-normal-config.ini"

    static func configURL(in bottleURL: URL) -> URL {
        if let gameDirectoryURL = OnlineGameDiscovery.jx3GameDirectory(in: bottleURL) {
            return gameDirectoryURL.appendingPathComponent("config.ini")
        }

        return OnlineGameMode.jx3GameDirectoryComponents.reduce(bottleURL) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        .appendingPathComponent("config.ini")
    }

    /// Replaces the game config with an externally prepared preset.
    ///
    /// The source is staged outside the game directory before directly
    /// replacing the live config. Procyon does not retain a preset backup.
    static func importPreset(
        from sourceURL: URL,
        into bottleURL: URL
    ) throws -> JX3ConfigPresetImportResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw JX3ConfigPresetError.sourceNotFound
        }

        let sourceData = try Data(contentsOf: sourceURL)
        guard let sourceContents = decodePreset(sourceData) else {
            throw JX3ConfigPresetError.unsupportedEncoding
        }
        guard isJX3Preset(sourceContents) else {
            throw JX3ConfigPresetError.invalidPreset
        }

        let targetURL = configURL(in: bottleURL)
        let targetDirectoryURL = targetURL.deletingLastPathComponent()
        guard (try? targetDirectoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw JX3ConfigPresetError.gameDirectoryNotFound
        }

        let temporaryURL = fileManager.temporaryDirectory.appendingPathComponent(
            "Procyon-JX3ConfigImport-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard let normalizedSourceData = sourceContents.data(using: .utf8) else {
            throw JX3ConfigPresetError.unsupportedEncoding
        }
        try normalizedSourceData.write(to: temporaryURL, options: .atomic)
        _ = try OnlineGameInitialConfiguration.enforceINIValue(
            at: temporaryURL,
            section: "Debug",
            key: "SkipVideoCardScoreUpdate",
            value: "1"
        )

        let preparedData = try Data(contentsOf: temporaryURL)
        try preparedData.write(to: targetURL, options: .atomic)

        return JX3ConfigPresetImportResult(configURL: targetURL)
    }

    private static func isJX3Preset(_ contents: String) -> Bool {
        let sections = contents
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
                )
            }
            .filter { $0.hasPrefix("[") && $0.hasSuffix("]") }
            .map { $0.dropFirst().dropLast().trimmingCharacters(in: .whitespaces) }

        return sections.contains {
            $0.caseInsensitiveCompare("Main") == .orderedSame
        } && sections.contains {
            $0.caseInsensitiveCompare("KG3DENGINE") == .orderedSame
        }
    }

    private static let gb18030Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    private static func decodePreset(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: gb18030Encoding)
    }

}
