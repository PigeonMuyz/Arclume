//
//  Locale.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//

import Foundation
import AppKit

enum L10n {
    nonisolated private static var selectedLanguage: AppLanguage {
        let storedValue = UserDefaults(suiteName: suiteName)?
            .string(forKey: "appLanguage")
        return AppLanguage(rawValue: storedValue ?? "") ?? .system
    }

    nonisolated private static var selectedBundle: Bundle {
        guard let localization = selectedLanguage.resourceLocalization,
              let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return .main
        }
        return bundle
    }

    nonisolated static func string(_ key: String) -> String {
        if selectedLanguage == .english {
            return key
        }
        return selectedBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: selectedLanguage.locale,
            arguments: arguments
        )
    }
}

func showFolder(url: URL) {
    let targetURL: URL = url
    NSWorkspace.shared.open(targetURL)
}
