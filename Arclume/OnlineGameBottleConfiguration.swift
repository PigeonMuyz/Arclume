//
//  OnlineGameBottleConfiguration.swift
//  Procyon
//

import Foundation

enum OnlineGameBottleConfiguration {
    nonisolated static let environment: [String: String] = [
        "LANG": "zh_CN.UTF-8",
        "LANGUAGE": "zh_CN:zh",
        "LC_ALL": "zh_CN.UTF-8",
        "LC_CTYPE": "zh_CN.UTF-8",
        "LC_MESSAGES": "zh_CN.UTF-8"
    ]

    private static let codePagePath =
        "System\\\\CurrentControlSet\\\\Control\\\\Nls\\\\CodePage"
    private static let languagePath =
        "System\\\\CurrentControlSet\\\\Control\\\\Nls\\\\Language"
    private static let fontSubstitutesPath =
        "Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\FontSubstitutes"
    private static let internationalPath = "Control Panel\\\\International"
    private static let keyboardLayoutPath = "Keyboard Layout\\\\Preload"
    private static let wineFontsPath = "Software\\\\Wine\\\\Fonts"
    private static let wineFontReplacementsPath =
        "Software\\\\Wine\\\\Fonts\\\\Replacements"
    private static let wineExternalFontsPath =
        "Software\\\\Wine\\\\Fonts\\\\External Fonts"
    private static let wineDebuggerPath = "Software\\\\Wine\\\\WineDbg"

    private static let configurationLock = NSLock()

    /// Applies the Chinese locale and font fallback required by the JX3 launcher.
    /// The operation is idempotent so existing Bottles can be repaired on launch.
    static func apply(to bottleURL: URL) throws {
        try apply(to: bottleURL, fontURL: BundledOnlineGameResources.chineseFontURL())
    }

    /// The font URL is injectable so registry behavior can be tested without
    /// requiring the test bundle to carry the production resource archive.
    static func apply(to bottleURL: URL, fontURL: URL?) throws {
        configurationLock.lock()
        defer { configurationLock.unlock() }

        try upsertCXBottleEnvironment(
            selectedBottle: bottleURL.absoluteString,
            values: environment
        )
        let bundledFontPath = try installBundledFont(fontURL, into: bottleURL)
        let bundledFontFamily = bundledFontPath == nil ? nil : "Noto Sans CJK SC"
        try updateSystemRegistry(
            at: bottleURL.appendingPathComponent("system.reg"),
            fontFamily: bundledFontFamily
        )
        try updateUserRegistry(
            at: bottleURL.appendingPathComponent("user.reg"),
            fontFamily: bundledFontFamily,
            externalFontPath: bundledFontPath
        )
    }

    nonisolated static func applyProcessEnvironment(
        to processEnvironment: inout [String: String]
    ) {
        for (key, value) in environment {
            processEnvironment[key] = value
        }
    }

    private static func updateSystemRegistry(at url: URL, fontFamily: String?) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        var changed = false

        if let codePage = registry.section(forPath: codePagePath, createIfMissing: true) {
            changed = upsert(
                [
                    "ACP": "936",
                    "MACCP": "10008",
                    "OEMCP": "936"
                ],
                in: codePage
            ) || changed
        }

        if let language = registry.section(forPath: languagePath, createIfMissing: true) {
            changed = upsert(
                [
                    "Default": "0804",
                    "InstallLanguage": "0804"
                ],
                in: language
            ) || changed
        }

        if let fontSubstitutes = registry.section(
            forPath: fontSubstitutesPath,
            createIfMissing: true
        ) {
            let substitutions = fontFamily.map {
                [
                    "MS Shell Dlg": $0,
                    "MS Shell Dlg 2": $0
                ]
            } ?? [
                "MS Shell Dlg": "SimSun",
                "MS Shell Dlg 2": "STHeiti"
            ]
            changed = upsert(
                substitutions,
                in: fontSubstitutes
            ) || changed
        }

        if changed {
            try registry.save()
        }
    }

    private static func updateUserRegistry(
        at url: URL,
        fontFamily: String?,
        externalFontPath: String?
    ) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let registry = WineRegistryFile(fileURL: url)
        try registry.load()
        var changed = false

        if let international = registry.section(
            forPath: internationalPath,
            createIfMissing: true
        ) {
            changed = upsert(
                [
                    "Locale": "00000804",
                    "LocaleName": "zh-CN",
                    "iCountry": "86",
                    "sCountry": "China",
                    "sLanguage": "CHS"
                ],
                in: international
            ) || changed
        }

        if let keyboardLayout = registry.section(
            forPath: keyboardLayoutPath,
            createIfMissing: true
        ) {
            changed = upsert(["1": "00000804"], in: keyboardLayout) || changed
        }

        if let wineFonts = registry.section(forPath: wineFontsPath, createIfMissing: true) {
            changed = upsert(["Codepages": "936,936"], in: wineFonts) || changed
        }

        // WineDbg normally presents one modal dialog for every crashing child
        // process. The JX3 launcher starts several CEF helpers, so a single
        // non-fatal helper crash can otherwise bury the game under dialogs.
        // Procyon still preserves the launch log and copied macOS crash report.
        if let wineDebugger = registry.section(
            forPath: wineDebuggerPath,
            createIfMissing: true
        ) {
            changed = upsertDwords(
                ["ShowCrashDialog": 0],
                in: wineDebugger
            ) || changed
        }

        if let replacements = registry.section(
            forPath: wineFontReplacementsPath,
            createIfMissing: true
        ) {
            let replacementsByFamily = fontFamily.map {
                [
                    "SimSun": $0,
                    "NSimSun": $0,
                    "Microsoft YaHei": $0,
                    "Microsoft YaHei UI": $0
                ]
            } ?? [
                "SimSun": "STSong",
                "NSimSun": "STSong",
                "Microsoft YaHei": "STHeiti",
                "Microsoft YaHei UI": "STHeiti"
            ]
            changed = upsert(
                replacementsByFamily,
                in: replacements
            ) || changed
        }

        if let externalFonts = registry.section(
            forPath: wineExternalFontsPath,
            createIfMissing: true
        ) {
            changed = upsert(
                [
                    "STSong (TrueType)":
                        "Z:\\\\System\\\\Library\\\\Fonts\\\\Supplemental\\\\Songti.ttc",
                    "STHeiti (TrueType)":
                        "Z:\\\\System\\\\Library\\\\Fonts\\\\STHeiti Medium.ttc"
                ],
                in: externalFonts
            ) || changed
            if let fontFamily, let externalFontPath {
                changed = upsert(
                    ["\(fontFamily) (TrueType)": externalFontPath],
                    in: externalFonts
                ) || changed
            }
        }

        if changed {
            try registry.save()
        }
    }

    private static func upsert(
        _ values: [String: String],
        in section: WineRegSection
    ) -> Bool {
        var changed = false
        for (key, value) in values where section.getValue(forKey: key) != value {
            section.addOrSetValue(forKey: key, stringValue: value)
            changed = true
        }
        return changed
    }

    private static func upsertDwords(
        _ values: [String: UInt32],
        in section: WineRegSection
    ) -> Bool {
        var changed = false
        for (key, value) in values where section.getValue(forKey: key) != String(value) {
            section.addOrSetDword(forKey: key, value: value)
            changed = true
        }
        return changed
    }

    private static func installBundledFont(_ fontURL: URL?, into bottleURL: URL) throws -> String? {
        guard let fontURL else { return nil }

        let fontsDirectory = bottleURL
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("windows", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fontsDirectory,
            withIntermediateDirectories: true
        )

        let destination = fontsDirectory.appendingPathComponent(
            BundledOnlineGameResources.chineseFontName
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: fontURL, to: destination)

        // Wine registry files use two backslashes for a Windows path.
        return "C:\\\\windows\\\\Fonts\\\\\(BundledOnlineGameResources.chineseFontName)"
    }
}
