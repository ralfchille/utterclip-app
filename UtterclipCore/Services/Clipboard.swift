import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pasteboard wrapper (plan Phase 4). Copies are always plain text — rich
/// (HTML/RTF) items broke pasting into plain-line inputs via Universal Clipboard.
public enum Clipboard {
    public static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #endif
    }
}

/// Strips the markdown subset the rewrite styles produce down to readable plain text:
/// headings become plain lines, list markers become "• ", bold/italic/code markers are
/// removed. Numbered lists pass through as-is.
public enum MarkdownStripper {
    public static func plainText(_ markdown: String) -> String {
        markdown.components(separatedBy: .newlines).map { rawLine -> String in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let text = headingText(line) { return stripInline(text) }
            for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
                return "• " + stripInline(String(line.dropFirst(marker.count)))
            }
            return stripInline(line)
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func headingText(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        let text = line.dropFirst(hashes.count)
        guard text.first == " " else { return nil }
        return String(text.dropFirst())
    }

    private static func stripInline(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        return s
    }
}
