import Foundation

/// Only foreground RGB values survive article conversion; never arbitrary CSS.
nonisolated enum ArticleTextColor {
    static func cssColor(_ style: String) -> String? {
        style.split(separator: ";").reversed().compactMap { declaration -> String? in
            let pair = declaration.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "color" else { return nil }
            return normalized(pair[1].replacingOccurrences(of: "!important", with: "", options: .caseInsensitive))
        }.first
    }

    static func normalized(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let names = ["red": "#ff0000", "blue": "#0000ff", "green": "#008000", "black": "#000000", "white": "#ffffff", "yellow": "#ffff00", "orange": "#ffa500", "purple": "#800080", "gray": "#808080", "grey": "#808080"]
        if let color = names[value] { return color }
        if value.range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil { return value }
        if value.range(of: "^#[0-9a-f]{3}$", options: .regularExpression) != nil {
            return "#" + value.dropFirst().map { "\($0)\($0)" }.joined()
        }
        if value.hasPrefix("rgb("), value.hasSuffix(")") {
            let components = value.dropFirst(4).dropLast().split(separator: ",", omittingEmptySubsequences: false)
            let numbers = components.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count == 3, numbers.allSatisfy({ (0...255).contains($0) }) else { return nil }
            return "#" + numbers.map { String(format: "%02x", $0) }.joined()
        }
        return nil
    }

    /// Preserve hue, lifting dark source colors to remain readable on the reader surface.
    static func readable(_ hex: String, dark: Bool) -> String {
        guard let value = UInt32(hex.dropFirst(), radix: 16) else { return hex }
        var rgb = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
        // Website body gray is not semantic emphasis; use the reader's primary text tone.
        if (rgb.max() ?? 0) - (rgb.min() ?? 0) < 0.04 { return dark ? "#eeeef2" : "#252528" }
        func luminance(_ values: [Double]) -> Double {
            let v = values.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return v[0] * 0.2126 + v[1] * 0.7152 + v[2] * 0.0722
        }
        let background = dark ? luminance([0.20, 0.20, 0.22]) : 1.0
        for _ in 0..<30 {
            let foreground = luminance(rgb)
            if (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05) >= 4.5 { break }
            rgb = rgb.map { dark ? $0 + (1 - $0) * 0.1 : $0 * 0.9 }
        }
        return "#" + rgb.map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
    }
}
