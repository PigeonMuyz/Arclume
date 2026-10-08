import Foundation
import SwiftSoup

/// Offline conversion of article HTML. No WebView, resource loading or script execution.
/// Rules receive semantic blocks, so source-specific conventions stay out of the renderer.
nonisolated protocol HTMLMarkdownRule {
    func replacement(for block: HTMLMarkdownBlock) -> HTMLMarkdownReplacement?
}

nonisolated struct HTMLMarkdownBlock {
    let tag: String
    let text: String
    let markdown: String
    let styles: [String]
}

nonisolated enum HTMLMarkdownReplacement {
    case heading(level: Int, text: String)
    case unorderedItem(markdown: String)
}

nonisolated enum HTMLToMarkdown {
    struct Limits {
        var maximumInputBytes = 2 * 1_024 * 1_024
        var maximumNodes = 50_000
        var maximumDepth = 128
    }

    enum ConversionError: Error, Equatable {
        case inputTooLarge
        case documentTooComplex
        case entityDeclarationsNotAllowed
    }

    static func convert(
        _ html: String,
        baseURL: URL? = nil,
        rules: [any HTMLMarkdownRule] = [],
        limits: Limits = Limits(),
        preserveTextColors: Bool = false
    ) throws -> String {
        guard html.utf8.count <= limits.maximumInputBytes else {
            throw ConversionError.inputTooLarge
        }
        guard !html.isEmpty else { return "" }
        // Reject entity declarations; parsing is explicitly HTML-only and offline.
        guard html.range(of: "<!\\s*ENTITY\\b", options: [.regularExpression, .caseInsensitive]) == nil else {
            throw ConversionError.entityDeclarationsNotAllowed
        }
        let document = try SwiftSoup.parse(html, "", Parser.htmlParser())
        var pending: [(SwiftSoup.Node, Int)] = [(document, 0)]
        var count = 0
        while let (node, depth) = pending.popLast() {
            count += 1
            guard count <= limits.maximumNodes, depth <= limits.maximumDepth else {
                throw ConversionError.documentTooComplex
            }
            pending.append(contentsOf: node.getChildNodes().map { ($0, depth + 1) })
        }
        return Renderer(baseURL: baseURL, rules: rules, preserveTextColors: preserveTextColors).render(document).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Renderer {
        let baseURL: URL?
        let rules: [any HTMLMarkdownRule]
        let preserveTextColors: Bool
        private let discarded: Set<String> = [
            "head", "script", "style", "noscript", "iframe", "object", "embed", "svg", "math",
            "form", "input", "button", "select", "textarea", "template",
        ]
        private let blocks: Set<String> = [
            "p", "div", "section", "article", "main", "header", "footer", "aside",
            "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "pre", "table", "blockquote",
        ]

        func render(_ node: SwiftSoup.Node) -> String {
            if let text = node as? TextNode {
                return colored(escape(collapse(text.getWholeText())), node: node)
            }
            guard let element = node as? Element else { return "" }
            let tag = element.tagName().lowercased()
            guard !discarded.contains(tag), !element.hasAttr("hidden") else { return "" }
            switch tag {
            case "br": return "  \n"
            case "hr": return "\n\n---\n\n"
            case "pre":
                let text = visibleText(element).replacingOccurrences(of: "\r\n", with: "\n")
                let fence = String(repeating: "`", count: max(3, longestBacktickRun(text) + 1))
                return "\n\n\(fence)\n\(text)\(text.hasSuffix("\n") ? "" : "\n")\(fence)\n\n"
            case "code":
                let text = collapse(visibleText(element))
                let fence = String(repeating: "`", count: max(1, longestBacktickRun(text) + 1))
                let padding = text.hasPrefix("`") || text.hasSuffix("`") || text.hasPrefix(" ") ? " " : ""
                return "\(fence)\(padding)\(text)\(padding)\(fence)"
            case "img":
                guard let url = safeURL(attribute(element, "src"), image: true) else { return "" }
                return "![\(escape(collapse(attribute(element, "alt") ?? "")))](<\(url)>)"
            case "a":
                let content = children(element)
                let label = trimmed(content)
                guard let url = safeURL(attribute(element, "href")) else { return content }
                let leading = content.first?.isWhitespace == true ? " " : ""
                let trailing = content.last?.isWhitespace == true ? " " : ""
                return leading + "[\(label.isEmpty ? escape(url) : label)](<\(url)>)" + trailing
            case "video", "audio":
                let source = attribute(element, "src")
                    ?? elements(element, named: "source").first.flatMap { attribute($0, "src") }
                guard let url = safeURL(source, image: true) else { return "" }
                return block("[\(tag == "video" ? "视频" : "音频")](<\(url)>)")
            case "ul", "ol": return renderList(element, ordered: tag == "ol")
            case "table": return renderTable(element)
            default: break
            }
            let content = children(element)
            let clean = trimmed(content)
            if (tag == "p" || tag == "div"), !hasBlockDescendant(element), !hasMediaDescendant(element) {
                let semantic = HTMLMarkdownBlock(tag: tag, text: trimmed(collapse(visibleText(element))), markdown: clean, styles: styles(element))
                for rule in rules {
                    switch rule.replacement(for: semantic) {
                    case let .heading(level, text):
                        let colorNode = element.getChildNodes().first(where: { sourceColor($0) != nil }) ?? element
                        return block(String(repeating: "#", count: min(6, max(1, level))) + " " + colored(escape(text), node: colorNode))
                    case let .unorderedItem(markdown): return block("- " + markdown)
                    case nil: continue
                    }
                }
            }
            switch tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                return block(String(repeating: "#", count: Int(tag.suffix(1)) ?? 1) + " " + clean)
            case "strong", "b":
                if preserveTextColors { return clean.isEmpty ? content : "<strong>\(content)</strong>" }
                return clean.isEmpty ? content : wrapInline(content, marker: "**")
            case "em", "i": return clean.isEmpty ? content : wrapInline(content, marker: "*")
            case "del", "s", "strike": return clean.isEmpty ? content : wrapInline(content, marker: "~~")
            case "blockquote": return block(clean.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n"))
            case "td", "th": return block(clean)
            default: return blocks.contains(tag) ? block(clean) : content
            }
        }

        private func children(_ node: SwiftSoup.Node) -> String { node.getChildNodes().map(render).joined() }
        private func sourceColor(_ node: SwiftSoup.Node) -> String? {
            var cursor: SwiftSoup.Node? = node
            while let current = cursor {
                if let element = current as? Element {
                    if let color = ArticleTextColor.cssColor(attribute(element, "style") ?? "") { return color }
                    if element.tagName().lowercased() == "font",
                       let color = ArticleTextColor.normalized(attribute(element, "color") ?? "") { return color }
                }
                cursor = current.parent()
            }
            return nil
        }
        private func colored(_ text: String, node: SwiftSoup.Node) -> String {
            guard preserveTextColors, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let color = sourceColor(node) else { return text }
            return "<span style=\"color:\(color)\">\(text)</span>"
        }
        private func elements(_ node: SwiftSoup.Node, named name: String) -> [Element] {
            node.getChildNodes().compactMap { $0 as? Element }.filter { $0.tagName().lowercased() == name }
        }
        private func attribute(_ node: Element, _ name: String) -> String? {
            guard node.hasAttr(name) else { return nil }
            return try? node.attr(name)
        }
        private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
        private func block(_ value: String) -> String { value.isEmpty ? "" : "\n\n" + value + "\n\n" }
        private func collapse(_ value: String) -> String {
            value.replacingOccurrences(of: "[\\t\\r\\n \u{00A0}]+", with: " ", options: .regularExpression)
        }
        private func escape(_ value: String) -> String {
            var result = ""
            for character in value {
                if "\\`*_{}[]<>#+-!|~".contains(character) { result.append("\\") }
                result.append(character)
            }
            return result.replacingOccurrences(of: "^(\\s*[0-9]+)\\.", with: "$1\\\\.", options: .regularExpression)
        }
        private func wrapInline(_ value: String, marker: String) -> String {
            let leading = value.first?.isWhitespace == true ? " " : ""
            let trailing = value.last?.isWhitespace == true ? " " : ""
            return leading + marker + trimmed(value) + marker + trailing
        }
        private func longestBacktickRun(_ value: String) -> Int {
            var longest = 0
            var current = 0
            for character in value {
                current = character == "`" ? current + 1 : 0
                longest = max(longest, current)
            }
            return longest
        }
        private func safeURL(_ value: String?, image: Bool = false) -> String? {
            guard let value, !value.isEmpty,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  let url = URL(string: value.trimmingCharacters(in: .whitespaces), relativeTo: baseURL)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(),
                  (image ? ["https", "http"] : ["https", "http", "mailto"]).contains(scheme),
                  scheme == "mailto" || (url.host != nil && url.user == nil && url.password == nil)
            else { return nil }
            return url.absoluteString.replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
        }
        private func hasBlockDescendant(_ node: SwiftSoup.Node) -> Bool {
            node.getChildNodes().contains { blocks.contains($0.nodeName().lowercased()) || hasBlockDescendant($0) }
        }
        private func hasMediaDescendant(_ node: SwiftSoup.Node) -> Bool {
            node.getChildNodes().contains { ["img", "video", "audio", "br"].contains($0.nodeName().lowercased()) || hasMediaDescendant($0) }
        }
        private func visibleText(_ node: SwiftSoup.Node) -> String {
            if discarded.contains(node.nodeName().lowercased()) || (node as? Element)?.hasAttr("hidden") == true { return "" }
            if let text = node as? TextNode { return text.getWholeText() }
            return node.getChildNodes().map(visibleText).joined()
        }
        private func styles(_ node: SwiftSoup.Node) -> [String] {
            let own = (node as? Element).flatMap { attribute($0, "style") }
            return (own.map { [$0] } ?? []) + node.getChildNodes().flatMap(styles)
        }
        private func renderList(_ element: Element, ordered: Bool) -> String {
            let start = max(1, Int(attribute(element, "start") ?? "1") ?? 1)
            let items = elements(element, named: "li").enumerated().map { index, item in
                let number = start.addingReportingOverflow(index)
                let marker = ordered ? "\(number.overflow ? Int.max : number.partialValue). " : "- "
                let lines = trimmed(children(item)).components(separatedBy: "\n")
                return marker + lines.enumerated().map { offset, line in
                    offset == 0 || line.isEmpty ? line : String(repeating: " ", count: marker.count) + line
                }.joined(separator: "\n")
            }
            return block(items.joined(separator: "\n"))
        }
        private func renderTable(_ table: Element) -> String {
            let rows = tableRows(table)
            let caption = elements(table, named: "caption").map { block(trimmed(children($0))) }.joined()
            guard !rows.isEmpty else { return caption }
            // Spanning/nested tables cannot be faithfully represented as GFM tables.
            // Preserve their cell contents as paragraphs instead of inventing columns.
            if rows.flatMap({ $0.getChildNodes() }).contains(where: {
                guard let cell = $0 as? Element else { return false }
                return cell.hasAttr("rowspan") || cell.hasAttr("colspan")
                    || (try? cell.select("table").isEmpty()) == false
            }) {
                return caption + rows.map { block(trimmed(children($0))) }.joined()
            }
            var cells = rows.map { row in
                row.getChildNodes().compactMap { node -> String? in
                    guard ["th", "td"].contains(node.nodeName().lowercased()) else { return nil }
                    return escapeTablePipes(trimmed(children(node)).components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " "))
                }
            }.filter { !$0.isEmpty }
            guard let width = cells.map(\.count).max(), width > 0 else { return "" }
            if !rows[0].getChildNodes().contains(where: { $0.nodeName().lowercased() == "th" }) { cells.insert(Array(repeating: "", count: width), at: 0) }
            var lines = cells.map { "| " + ($0 + Array(repeating: "", count: width - $0.count)).joined(separator: " | ") + " |" }
            lines.insert("| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |", at: 1)
            return caption + block(lines.joined(separator: "\n"))
        }
        private func escapeTablePipes(_ value: String) -> String {
            var result = ""
            var backslashes = 0
            for character in value {
                if character == "|", backslashes.isMultiple(of: 2) { result.append("\\") }
                result.append(character)
                backslashes = character == "\\" ? backslashes + 1 : 0
            }
            return result
        }
        private func tableRows(_ node: SwiftSoup.Node) -> [Element] {
            node.getChildNodes().flatMap { child -> [Element] in
                guard let child = child as? Element else { return [] }
                if child.tagName().lowercased() == "tr" { return [child] }
                return ["thead", "tbody", "tfoot"].contains(child.tagName().lowercased()) ? tableRows(child) : []
            }
        }
    }
}
