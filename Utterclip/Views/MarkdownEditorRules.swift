import HighlightedTextEditor
import SwiftUI
#if os(macOS)
import AppKit
typealias EditorFont = NSFont
let secondaryLabel = NSColor.secondaryLabelColor
let primaryLabel = NSColor.labelColor
// The identity face, matching `MarkdownView`: the text must not change typeface the
// moment you tap it to edit.
let headingLevel1 = identityFont(ResultTypography.size + 4, .bold)
let headingLevel2 = identityFont(ResultTypography.size + 1, .semibold)
let headingLevel3 = identityFont(ResultTypography.size, .bold)
let bodyFont = identityFont(ResultTypography.size)
private extension NSFont {
    var bolded: NSFont { NSFont(descriptor: fontDescriptor.withSymbolicTraits(.bold), size: pointSize) ?? self }
}
#else
import UIKit
typealias EditorFont = UIFont
let secondaryLabel = UIColor.secondaryLabel
let primaryLabel = UIColor.label
// The identity face, matching `MarkdownView`: the text must not change typeface the
// moment you tap it to edit.
let headingLevel1 = identityFont(ResultTypography.size + 4, .bold)
let headingLevel2 = identityFont(ResultTypography.size + 1, .semibold)
let headingLevel3 = identityFont(ResultTypography.size, .bold)
let bodyFont = identityFont(ResultTypography.size)
private extension UIFont {
    var bolded: UIFont { fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: pointSize) } ?? self }
}
#endif


/// One spelling for both platforms; falls back to the system font if the resource is missing.
func identityFont(_ size: CGFloat, _ weight: IdentityFont.Weight = .regular) -> EditorFont {
    #if os(macOS)
    IdentityFont.nsFont(size: size, weight: weight)
    #else
    IdentityFont.uiFont(size: size, weight: weight)
    #endif
}

/// Matches the whole document, so the paragraph style below reaches every line.
let everythingRegex = try! NSRegularExpression(pattern: "[\\s\\S]+", options: [])
let headingRegex = try! NSRegularExpression(pattern: "^#{1,6}\\s.*$", options: [.anchorsMatchLines])
let boldRegex = try! NSRegularExpression(pattern: "((\\*|_){2})((?!\\1).)+\\1", options: [])
let asteriskEmphasisRegex = try! NSRegularExpression(pattern: "(?<!\\*)(\\*)((?!\\1).)+\\1(?!\\*)", options: [])
let underscoreEmphasisRegex = try! NSRegularExpression(pattern: "(?<!_)_[^_]+_(?!\\*)", options: [])
let boldEmphasisRegex = try! NSRegularExpression(pattern: "(\\*){3}((?!\\1).)+\\1{3}", options: [])
let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`]*`", options: [])
let unorderedListRegex = try! NSRegularExpression(pattern: "^(\\-|\\*)\\s", options: [.anchorsMatchLines])
let orderedListRegex = try! NSRegularExpression(pattern: "^\\d+\\.\\s", options: [.anchorsMatchLines])
let linkRegex = try! NSRegularExpression(pattern: "!?\\[([^\\[\\]]*)\\]\\((.*?)\\)", options: [])

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
            // Both on the whole document, and first: the library seeds every run with the
            // system body font, and each formatting rule re-applies whatever font it finds —
            // so the body size has to be (re)stated here, before the heading rules run.
            HighlightRule(pattern: everythingRegex, formattingRules: [
                TextFormattingRule(key: .paragraphStyle, value: roomierLines),
                TextFormattingRule(key: .font, value: bodyFont),
            ]),
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

/// Leading as extra space between lines, on top of the font's natural height — the way both
/// SwiftUI and TextKit express it. What they disagree on is the natural height itself: at 16 pt
/// TextKit lays a line out 18 pt tall where SwiftUI reckons a little over 19, so handing
/// TextKit the spacing `Text` was given left the editor's lines 1.2 pt tighter than the
/// rendered card's, and the text moved as the card turned editable. Ask each for the gap that
/// gets it to the same line height instead.
let roomierLines: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    #if os(macOS)
    style.lineSpacing = max(0, ResultTypography.lineHeight - NSLayoutManager().defaultLineHeight(for: bodyFont))
    #else
    style.lineSpacing = ResultTypography.lineSpacing
    #endif
    return style
}()

#if os(macOS)
let boldTraitsOnly: NSFontDescriptor.SymbolicTraits = [.bold]
let italicTraitsOnly: NSFontDescriptor.SymbolicTraits = [.italic]
let boldItalicTraits: NSFontDescriptor.SymbolicTraits = [.bold, .italic]
#else
let boldTraitsOnly: UIFontDescriptor.SymbolicTraits = [.traitBold]
let italicTraitsOnly: UIFontDescriptor.SymbolicTraits = [.traitItalic]
let boldItalicTraits: UIFontDescriptor.SymbolicTraits = [.traitBold, .traitItalic]
#endif


/// Applies the markdown attributes to a text storage in place, leaving the characters alone.
/// Shared by both platforms' in-place editors, so the phone and the Mac highlight identically.
enum MarkdownHighlighter {
    static func apply(to storage: NSTextStorage) {
        let text = storage.string
        let all = NSRange(location: 0, length: (text as NSString).length)
        storage.beginEditing()
        storage.setAttributes([
            .font: bodyFont,
            .foregroundColor: primaryLabel,
            .paragraphStyle: roomierLines,
        ], range: all)
        for (pattern, apply) in rules {
            pattern.enumerateMatches(in: text, options: [], range: all) { match, _, _ in
                guard let match else { return }
                apply(storage, match, text)
            }
        }
        storage.endEditing()
    }

    private static let rules: [(NSRegularExpression, (NSTextStorage, NSTextCheckingResult, String) -> Void)] = [
        (headingRegex, { storage, match, text in
            let hashes = (text as NSString).substring(with: match.range).prefix { $0 == "#" }.count
            storage.addAttribute(.font, value: hashes <= 1 ? headingLevel1 : hashes == 2 ? headingLevel2 : headingLevel3,
                                 range: match.range)
        }),
        (boldEmphasisRegex, { storage, match, _ in storage.addTrait(boldItalicTraits, range: match.range) }),
        (boldRegex, { storage, match, _ in storage.addTrait(boldTraitsOnly, range: match.range) }),
        (asteriskEmphasisRegex, { storage, match, _ in storage.addTrait(italicTraitsOnly, range: match.range) }),
        (underscoreEmphasisRegex, { storage, match, _ in storage.addTrait(italicTraitsOnly, range: match.range) }),
        (inlineCodeRegex, { storage, match, _ in
            storage.addAttribute(.font, value: EditorFont.monospacedSystemFont(ofSize: ResultTypography.size, weight: .regular),
                                 range: match.range)
        }),
        (unorderedListRegex, { storage, match, _ in
            storage.addAttribute(.foregroundColor, value: secondaryLabel, range: match.range)
        }),
        (orderedListRegex, { storage, match, _ in
            storage.addAttribute(.foregroundColor, value: secondaryLabel, range: match.range)
        }),
        (linkRegex, { storage, match, _ in
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
        }),
    ]
}

private extension NSTextStorage {
    /// Adds a trait to whatever font each run already has, so bold inside a heading stays a
    /// heading.
    func addTrait(_ traits: EditorFont.SymbolicTraitsType, range: NSRange) {
        enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? EditorFont) ?? bodyFont
            #if os(macOS)
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            if let combined = NSFont(descriptor: descriptor, size: font.pointSize) {
                addAttribute(.font, value: combined, range: subrange)
            }
            #else
            if let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits)) {
                addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: subrange)
            }
            #endif
        }
    }
}

extension EditorFont {
    #if os(macOS)
    typealias SymbolicTraitsType = NSFontDescriptor.SymbolicTraits
    #else
    typealias SymbolicTraitsType = UIFontDescriptor.SymbolicTraits
    #endif
}
