//
//  SteamTextFormatter.swift
//  Procyon
//

import Foundation

/// Converts the HTML fragments returned by the Steam Store API into text that
/// is safe to display with SwiftUI's `Text` view.
nonisolated enum SteamTextFormatter {
    private static let discardedElementNames = [
        "script", "style", "video", "audio", "iframe", "object", "picture", "svg",
    ]

    /// Preserves useful paragraph and list boundaries while discarding markup
    /// and embedded content. This method never loads remote resources.
    static func plainText(fromHTML html: String) -> String {
        guard !html.isEmpty else { return "" }

        var text = html
        for elementName in discardedElementNames {
            text = replacingMatches(
                in: text,
                pattern: "(?is)<\\s*\(elementName)\\b[^>]*>.*?<\\s*/\\s*\(elementName)\\s*>",
                with: "\n"
            )
        }

        text = replacingMatches(in: text, pattern: "(?is)<!--.*?-->", with: "")
        text = replacingMatches(
            in: text,
            pattern: "(?is)<\\s*(?:source|track|embed|img)\\b[^>]*?/?>",
            with: ""
        )
        text = replacingMatches(in: text, pattern: "(?is)<\\s*br\\s*/?\\s*>", with: "\n")
        text = replacingMatches(in: text, pattern: "(?is)<\\s*li\\b[^>]*>", with: "\n• ")
        text = replacingMatches(in: text, pattern: "(?is)<\\s*/\\s*li\\s*>", with: "\n")
        text = replacingMatches(
            in: text,
            pattern: "(?is)<\\s*/?\\s*(?:p|div|section|article|blockquote|h[1-6]|ul|ol|table|tr|pre)\\b[^>]*>",
            with: "\n"
        )
        text = replacingMatches(in: text, pattern: "(?is)<[^>]+>", with: "")
        text = decodeHTMLEntities(in: text)

        return normalizedWhitespace(in: text)
    }

    /// Steam requirement fragments usually repeat the section title inside a
    /// leading `<strong>` element. The view already supplies that title, so it
    /// is removed before converting the remaining requirement list.
    static func requirementText(fromHTML html: String) -> String {
        let withoutRepeatedHeading = replacingMatches(
            in: html,
            pattern: "(?is)^\\s*<(?:strong|b)\\b[^>]*>.*?</(?:strong|b)>\\s*(?:<\\s*br\\s*/?\\s*>)?",
            with: ""
        )
        return plainText(fromHTML: withoutRepeatedHeading)
    }

    /// Returns only language names. Steam appends an HTML footnote after a
    /// `<br>` and marks full-audio languages with `<strong>*</strong>`.
    static func supportedLanguages(fromHTML html: String) -> [String] {
        let languageListHTML: String
        if let footnoteRange = html.range(
            of: "<\\s*br\\s*/?\\s*>",
            options: [.regularExpression, .caseInsensitive]
        ) {
            languageListHTML = String(html[..<footnoteRange.lowerBound])
        } else {
            languageListHTML = html
        }

        var seen = Set<String>()
        return plainText(fromHTML: languageListHTML)
            .components(separatedBy: CharacterSet(charactersIn: ",，;；"))
            .compactMap { rawLanguage in
                let language = rawLanguage
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !language.isEmpty, seen.insert(language).inserted else { return nil }
                return language
            }
    }

    private static func replacingMatches(
        in source: String,
        pattern: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return expression.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: replacement
        )
    }

    private static func decodeHTMLEntities(in source: String) -> String {
        let namedEntities = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "nbsp": " ", "ensp": " ", "emsp": " ", "ndash": "–", "mdash": "—",
            "hellip": "…", "bull": "•", "middot": "·", "copy": "©", "reg": "®",
            "trade": "™", "times": "×", "lsquo": "‘", "rsquo": "’",
            "ldquo": "“", "rdquo": "”",
        ]

        var result = ""
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard source[cursor] == "&",
                  let semicolon = source[cursor...].firstIndex(of: ";"),
                  source.distance(from: cursor, to: semicolon) <= 16 else {
                result.append(source[cursor])
                cursor = source.index(after: cursor)
                continue
            }

            let entityStart = source.index(after: cursor)
            let entity = String(source[entityStart..<semicolon])
            if let decoded = decodedEntity(entity, namedEntities: namedEntities) {
                result.append(decoded)
                cursor = source.index(after: semicolon)
            } else {
                result.append(contentsOf: source[cursor...semicolon])
                cursor = source.index(after: semicolon)
            }
        }
        return result
    }

    private static func decodedEntity(
        _ entity: String,
        namedEntities: [String: String]
    ) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            guard let value = UInt32(entity.dropFirst(2), radix: 16),
                  let scalar = UnicodeScalar(value) else { return nil }
            return String(scalar)
        }
        if entity.hasPrefix("#") {
            guard let value = UInt32(entity.dropFirst()),
                  let scalar = UnicodeScalar(value) else { return nil }
            return String(scalar)
        }
        return namedEntities[entity.lowercased()]
    }

    private static func normalizedWhitespace(in source: String) -> String {
        let canonicalNewlines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        let lines = canonicalNewlines.components(separatedBy: "\n").map { line in
            replacingMatches(in: line, pattern: "[\\t ]+", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }

        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
