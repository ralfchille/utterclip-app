import HighlightedTextEditor
import SwiftUI
#if os(macOS)
import AppKit
private typealias EditorFont = NSFont
private let secondaryLabel = NSColor.secondaryLabelColor
private let headingLevel1 = EditorFont.preferredFont(forTextStyle: .title3).bolded
private let headingLevel2 = EditorFont.preferredFont(forTextStyle: .headline)
private let headingLevel3 = EditorFont.preferredFont(forTextStyle: .subheadline).bolded
private let bodyFont = EditorFont.preferredFont(forTextStyle: .body)
private extension NSFont {
    var bolded: NSFont { NSFont(descriptor: fontDescriptor.withSymbolicTraits(.bold), size: pointSize) ?? self }
}
#else
import UIKit
private typealias EditorFont = UIFont
private let secondaryLabel = UIColor.secondaryLabel
private let headingLevel1 = EditorFont.preferredFont(forTextStyle: .title3).bolded
private let headingLevel2 = EditorFont.preferredFont(forTextStyle: .headline)
private let headingLevel3 = EditorFont.preferredFont(forTextStyle: .subheadline).bolded
private let bodyFont = EditorFont.preferredFont(forTextStyle: .body)
private extension UIFont {
    var bolded: UIFont { fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: pointSize) } ?? self }
}
#endif

/// Matches the whole document, so the paragraph style below reaches every line.
private let everythingRegex = try! NSRegularExpression(pattern: "[\\s\\S]+", options: [])
private let headingRegex = try! NSRegularExpression(pattern: "^#{1,6}\\s.*$", options: [.anchorsMatchLines])
private let boldRegex = try! NSRegularExpression(pattern: "((\\*|_){2})((?!\\1).)+\\1", options: [])
private let asteriskEmphasisRegex = try! NSRegularExpression(pattern: "(?<!\\*)(\\*)((?!\\1).)+\\1(?!\\*)", options: [])
private let underscoreEmphasisRegex = try! NSRegularExpression(pattern: "(?<!_)_[^_]+_(?!\\*)", options: [])
private let boldEmphasisRegex = try! NSRegularExpression(pattern: "(\\*){3}((?!\\1).)+\\1{3}", options: [])
private let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`]*`", options: [])
private let unorderedListRegex = try! NSRegularExpression(pattern: "^(\\-|\\*)\\s", options: [.anchorsMatchLines])
private let orderedListRegex = try! NSRegularExpression(pattern: "^\\d+\\.\\s", options: [.anchorsMatchLines])
private let linkRegex = try! NSRegularExpression(pattern: "!?\\[([^\\[\\]]*)\\]\\((.*?)\\)", options: [])

extension Sequence where Iterator.Element == HighlightRule {
    /// Markdown highlighting that matches `MarkdownView`, so editing looks like the result:
    /// `#` = title3 bold, `##` = headline, `###`+ = subheadline bold, everything else at body
    /// size; bold and italic as traits, inline code monospaced at body size, list markers
    /// and link syntax in the secondary colour. No letter-spacing or expanded faces.
    static var utterclipMarkdown: [HighlightRule] {
        [
            // First, so the per-run font it re-applies is still the uniform base font:
            // 20 % more leading than the font's own, headings included (the multiple scales
            // with each line's font size).
            HighlightRule(pattern: everythingRegex, formattingRule: TextFormattingRule(key: .paragraphStyle, value: roomierLines)),
            HighlightRule(pattern: headingRegex, formattingRule: TextFormattingRule(key: .font, calculateValue: { content, _ in
                let level = content.prefix(while: { $0 == "#" }).count
                return level <= 1 ? headingLevel1 : level == 2 ? headingLevel2 : headingLevel3
            })),
            HighlightRule(pattern: boldEmphasisRegex, formattingRule: TextFormattingRule(fontTraits: boldItalicTraits)),
            HighlightRule(pattern: boldRegex, formattingRule: TextFormattingRule(fontTraits: boldTraitsOnly)),
            HighlightRule(pattern: asteriskEmphasisRegex, formattingRule: TextFormattingRule(fontTraits: italicTraitsOnly)),
            HighlightRule(pattern: underscoreEmphasisRegex, formattingRule: TextFormattingRule(fontTraits: italicTraitsOnly)),
            HighlightRule(pattern: inlineCodeRegex, formattingRule: TextFormattingRule(
                key: .font, value: EditorFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular))),
            HighlightRule(pattern: unorderedListRegex, formattingRule: TextFormattingRule(key: .foregroundColor, value: secondaryLabel)),
            HighlightRule(pattern: orderedListRegex, formattingRule: TextFormattingRule(key: .foregroundColor, value: secondaryLabel)),
            HighlightRule(pattern: linkRegex, formattingRule: TextFormattingRule(key: .underlineStyle, value: NSUnderlineStyle.single.rawValue)),
        ]
    }
}

/// The editor's line spacing: 1.2× the natural line height.
private let roomierLines: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = 1.2
    return style
}()

#if os(macOS)
private let boldTraitsOnly: NSFontDescriptor.SymbolicTraits = [.bold]
private let italicTraitsOnly: NSFontDescriptor.SymbolicTraits = [.italic]
private let boldItalicTraits: NSFontDescriptor.SymbolicTraits = [.bold, .italic]
#else
private let boldTraitsOnly: UIFontDescriptor.SymbolicTraits = [.traitBold]
private let italicTraitsOnly: UIFontDescriptor.SymbolicTraits = [.traitItalic]
private let boldItalicTraits: UIFontDescriptor.SymbolicTraits = [.traitBold, .traitItalic]
#endif
