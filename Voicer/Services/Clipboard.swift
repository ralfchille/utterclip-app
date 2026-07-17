import UIKit
import UniformTypeIdentifiers

/// UIPasteboard wrapper (plan Phase 4).
enum Clipboard {
    /// Plain-text copy — used for the raw transcript fast path.
    static func copy(_ string: String) {
        UIPasteboard.general.string = string
    }

    /// Copies rewritten output with rich representations alongside the plain text, so
    /// pasting into Google Docs, Mail, Word etc. yields real headings, bullets and bold
    /// instead of literal markdown characters. Plain-text targets still get the raw text.
    @MainActor
    static func copyFormatted(_ markdown: String) {
        let html = MarkdownHTML.render(markdown)
        var item: [String: Any] = [
            UTType.utf8PlainText.identifier: markdown,
            UTType.html.identifier: html,
        ]
        // RTF for editors that prefer it (TextEdit, Pages). HTML→NSAttributedString
        // import is main-thread-only, hence @MainActor.
        if let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ),
           let rtf = try? attributed.data(
               from: NSRange(location: 0, length: attributed.length),
               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
           ) {
            item[UTType.rtf.identifier] = rtf
        }
        UIPasteboard.general.setItems([item])
    }
}

/// Converts the markdown subset the rewrite styles produce (headings, bullet/numbered
/// lists, bold, italic, inline code) to HTML for the pasteboard.
enum MarkdownHTML {
    static func render(_ markdown: String) -> String {
        var html = ""
        var openList: String? // "ul" | "ol"
        var paragraph: [String] = []

        func closeList() {
            if let list = openList {
                html += "</\(list)>"
                openList = nil
            }
        }
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html += "<p>" + paragraph.joined(separator: "<br>") + "</p>"
            paragraph = []
        }
        func startList(_ kind: String) {
            flushParagraph()
            if openList != kind {
                closeList()
                html += "<\(kind)>"
                openList = kind
            }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                closeList()
                continue
            }
            if let (level, text) = heading(line) {
                flushParagraph()
                closeList()
                html += "<h\(level)>\(inline(text))</h\(level)>"
                continue
            }
            if let text = listItem(line, markers: ["- ", "* ", "• "]) {
                startList("ul")
                html += "<li>\(inline(text))</li>"
                continue
            }
            if let text = orderedItem(line) {
                startList("ol")
                html += "<li>\(inline(text))</li>"
                continue
            }
            closeList()
            paragraph.append(inline(line))
        }
        flushParagraph()
        closeList()
        return "<html><body>\(html)</body></html>"
    }

    private static func heading(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        let level = min(hashes.count, 6)
        let text = line.dropFirst(hashes.count)
        guard text.first == " " else { return nil }
        return (level, String(text.dropFirst()))
    }

    private static func listItem(_ line: String, markers: [String]) -> String? {
        for marker in markers where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let range = line.range(of: #"^\d{1,3}\. "#, options: .regularExpression) else {
            return nil
        }
        return String(line[range.upperBound...])
    }

    private static func inline(_ text: String) -> String {
        var s = escape(text)
        s = s.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#, with: "<b>$1</b>", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, with: "<i>$1</i>", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        return s
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
