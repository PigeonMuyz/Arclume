import Foundation
import cmark_gfm
import cmark_gfm_extensions
import SwiftSoup

/// The reader consumes converted Markdown, never the original site's executable HTML.
nonisolated enum ArticleReaderDocument {
    private static let registeredExtensions: Void = cmark_gfm_core_extensions_ensure_registered()

    private static func render(_ markdown: String) throws -> String {
        _ = registeredExtensions
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { throw JX3ArticleContentError.invalidResponse }
        defer { cmark_parser_free(parser) }
        for name in ["autolink", "strikethrough", "table"] {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let tree = cmark_parser_finish(parser) else { throw JX3ArticleContentError.invalidResponse }
        defer { cmark_node_free(tree) }
        // Raw spans are only an intermediate representation. Nothing is displayed until
        // the separate SwiftSoup tag/attribute whitelist and color validator have run.
        guard let html = cmark_render_html(tree, CMARK_OPT_UNSAFE, cmark_parser_get_syntax_extensions(parser)) else {
            throw JX3ArticleContentError.invalidResponse
        }
        defer { free(html) }
        return String(cString: html)
    }

    static func make(markdown: String) throws -> String {
        try Task.checkCancellation()
        let rendered = try render(markdown)
        let whitelist = try Whitelist.relaxed().addTags("span", "del").addAttributes("span", "style")
        let cleaned = try SwiftSoup.clean(rendered, whitelist) ?? ""
        let document = try SwiftSoup.parseBodyFragment(cleaned)
        for element in try document.select("a[href], img[src]") {
            let image = element.tagName() == "img"
            let attribute = image ? "src" : "href"
            let schemes = image ? ["https", "http"] : ["https", "http", "mailto"]
            let value = try element.attr(attribute)
            guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
                  schemes.contains(scheme), url.user == nil, url.password == nil,
                  scheme == "mailto" || url.host != nil else {
                try element.removeAttr(attribute)
                continue
            }
        }
        for span in try document.select("span[style]") {
            let color = ArticleTextColor.cssColor(try span.attr("style"))
            try span.removeAttr("style")
            if let color {
                let light = ArticleTextColor.readable(color, dark: false)
                let dark = ArticleTextColor.readable(color, dark: true)
                try span.attr("style", "--source-color:\(color);--text-light:\(light);--text-dark:\(dark)")
                try span.addClass("source-color")
            }
        }
        for image in try document.select("img") {
            try image.attr("loading", "lazy").attr("decoding", "async").attr("referrerpolicy", "no-referrer")
        }
        try Task.checkCancellation()
        let body = try document.body()?.html() ?? ""
        return """
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="no-referrer">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src https: http:; base-uri 'none'; form-action 'none'">
        <style>
        :root { color-scheme: light dark; }
        html { background: #fafafa; }
        body { margin: 0; padding: 24px; font: 15px/1.65 -apple-system, BlinkMacSystemFont, sans-serif; color: #252528; overflow-wrap: anywhere; }
        p { margin: 0 0 18px; } h1,h2,h3,h4,h5,h6 { font-size: 18px; line-height: 1.5; margin: 22px 0 12px; }
        body > :first-child { margin-top: 0; } body > :last-child { margin-bottom: 0; }
        ul,ol { padding-left: 24px; margin: 0 0 18px; } li p { margin-bottom: 6px; }
        a { color: #315fbc; text-decoration: underline; } .source-color { color: var(--text-light); }
        img { max-width: 100%; height: auto; } pre { overflow-x: auto; white-space: pre; }
        blockquote { margin: 18px 0; padding-left: 16px; border-left: 3px solid #8888; }
        table { border-collapse: collapse; width: 100%; } th,td { border: 1px solid #8886; padding: 8px; }
        @media (prefers-color-scheme: dark) { html { background: #373739; } body { color: #eeeef2; } a { color: #abcaff; } .source-color { color: var(--text-dark); } }
        </style></head><body>\(body)</body></html>
        """
    }

    static func prepare(markdown: String) async throws -> String {
        let task = Task.detached(priority: .userInitiated) { try make(markdown: markdown) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
