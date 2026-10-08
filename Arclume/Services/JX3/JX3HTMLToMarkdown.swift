import Foundation

/// Conventions used by the official JX3 article APIs, layered on the generic renderer.
/// Fetching/caching articles and presenting Markdown are intentionally separate concerns.
nonisolated enum JX3HTMLToMarkdown {
    static func convert(_ html: String, articleURL: URL, preserveTextColors: Bool = false) throws -> String {
        try HTMLToMarkdown.convert(html, baseURL: articleURL, rules: [JX3ArticleRule()], preserveTextColors: preserveTextColors)
    }
}

nonisolated struct JX3ArticleRule: HTMLMarkdownRule {
    func replacement(for block: HTMLMarkdownBlock) -> HTMLMarkdownReplacement? {
        let text = block.text
        guard !text.isEmpty, !text.contains("\n") else { return nil }
        if text.count <= 40, text.hasPrefix("【"), text.hasSuffix("】"),
           !text.dropFirst().dropLast().contains("】") {
            return .heading(level: 2, text: String(text.dropFirst().dropLast()))
        }
        if text.count <= 60, text.hasPrefix("◎") {
            return .heading(level: 3, text: String(text.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        // Do not promote arbitrary numbered prose: the official subsection format is
        // short, numbered with 、, and blue. Other source styles are discarded.
        if text.count <= 30, text.range(of: "^[0-9]+、[^。！？]+$", options: .regularExpression) != nil,
           block.styles.contains(where: isBlue) {
            return .heading(level: 4, text: text)
        }
        if text.hasPrefix("·") || text.hasPrefix("•"), let marker = text.first,
           let index = block.markdown.firstIndex(of: marker) {
            var markdown = block.markdown
            markdown.remove(at: index)
            return .unorderedItem(markdown: markdown.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func isBlue(_ style: String) -> Bool {
        style.range(
            of: "(?:^|;)\\s*color\\s*:\\s*(?:#0000ff|#00f|blue|rgb\\(\\s*0\\s*,\\s*0\\s*,\\s*255\\s*\\))\\s*(?:;|$)",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
