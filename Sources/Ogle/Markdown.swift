import Foundation
import Yams
import cmark_gfm
import cmark_gfm_extensions

enum Markdown {
    static let fileExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    /// Renders GitHub Flavored Markdown with cmark-gfm, the parser GitHub itself uses.
    /// Raw HTML is passed through and sanitized by the web view before display.
    static func html(from data: Data) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        // Source positions (data-sourcepos) let the preview follow the editor's scrolling.
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS
        let parser = cmark_parser_new(options)
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "autolink", "tagfilter", "tasklist"] {
            cmark_parser_attach_syntax_extension(parser, cmark_find_syntax_extension(name))
        }
        let frontMatter = frontMatter(in: data)
        (frontMatter?.markdown ?? data).withUnsafeBytes { bytes in
            cmark_parser_feed(parser, bytes.bindMemory(to: CChar.self).baseAddress, bytes.count)
        }
        let document = cmark_parser_finish(parser)
        defer { cmark_node_free(document) }
        let html = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser))!
        defer { free(html) }
        return (frontMatter?.table ?? "") + String(cString: html)
    }

    /// YAML front matter as GitHub shows it: a table of the mapping between a `---` line at the
    /// start and the next `---` or `...` line, with the Markdown after it. The front matter's
    /// lines stay in the Markdown as blank ones so that source positions still match the file.
    /// Front matter that isn't a YAML mapping is left to Markdown, as on GitHub.
    private static func frontMatter(in data: Data) -> (table: String, markdown: Data)? {
        guard data.starts(with: "---".utf8) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard lines[0].wholeMatch(of: /---[ \t]*/) != nil,
              let close = lines.dropFirst().firstIndex(where: { $0.wholeMatch(of: /(---|\.\.\.)[ \t]*/) != nil }),
              case .mapping(let mapping)? = try? Yams.compose(yaml: lines[1..<close].joined(separator: "\n"))
        else { return nil }
        let rows = mapping.map { "<tr><th>\(html($0.key))</th><td>\(html($0.value))</td></tr>" }
        let table = "<table class=\"front-matter\" data-sourcepos=\"1:1-\(close + 1):\(lines[close].count)\"><tbody>\(rows.joined())</tbody></table>\n"
        return (table, Data((String(repeating: "\n", count: close) + text[lines[close].endIndex...]).utf8))
    }

    /// A nested mapping is a table with a row of keys over a row of values, a sequence a table
    /// of one row, and a scalar its text as written, with its URLs linked.
    private static func html(_ node: Node) -> String {
        switch node {
        case .scalar(let scalar):
            return linked(scalar.string)
        case .alias(let alias):
            return escaped("*\(alias.anchor.rawValue)")
        case .sequence(let sequence):
            return "<table><tbody><tr>\(sequence.map { "<td>\(html($0))</td>" }.joined())</tr></tbody></table>"
        case .mapping(let mapping):
            let keys = mapping.map { "<th>\(html($0.key))</th>" }.joined()
            let values = mapping.map { "<td>\(html($0.value))</td>" }.joined()
            return "<table><thead><tr>\(keys)</tr></thead><tbody><tr>\(values)</tr></tbody></table>"
        }
    }

    private static func linked(_ text: String) -> String {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var html = ""
        var rest = text.startIndex
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let range = Range(match.range, in: text)!
            html += escaped(text[rest..<range.lowerBound])
            html += "<a href=\"\(escaped(match.url!.absoluteString))\">\(escaped(text[range]))</a>"
            rest = range.upperBound
        }
        return html + escaped(text[rest...])
    }

    private static func escaped(_ text: some StringProtocol) -> String {
        String(text).replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
            .replacing("\"", with: "&quot;")
    }
}
