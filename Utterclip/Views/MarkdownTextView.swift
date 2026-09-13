#if os(macOS)
import AppKit
import SwiftUI

/// The text view the result is edited in.
///
/// Written rather than borrowed: the editor library rebuilds the whole attributed string and
/// reassigns it on every SwiftUI update — which is every keystroke, since the text is state —
/// and each rebuild redraws the view and restores the selection. On a frame that also grows
/// as you type, that reads as a flicker. Here the text storage is never replaced; highlighting
/// is applied to it in place, and an update from outside only lands when the text genuinely
/// differs from what is on screen.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    /// Called on every keystroke, for the label and the delayed copy.
    var onChange: () -> Void = {}
    /// Called when the view loses focus: an edit is finished by clicking away.
    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> AutoGrowingTextView {
        let textView = AutoGrowingTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        Self.highlight(textView)
        // The caret belongs in the text the moment the card opens.
        DispatchQueue.main.async {
            guard textView.window?.firstResponder !== textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
        return textView
    }

    /// Only for changes that came from somewhere else — a re-style, a restore from History.
    /// Typing never reaches here, which is the point.
    func updateNSView(_ textView: AutoGrowingTextView, context: Context) {
        guard textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        Self.highlight(textView)
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        textView.invalidateIntrinsicContentSize()
    }

    /// Applies the markdown attributes to the storage in place, leaving the text untouched.
    static func highlight(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string
        let all = NSRange(location: 0, length: (text as NSString).length)
        storage.beginEditing()
        storage.setAttributes([
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
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

    /// Same appearance as the rendered result: see `MarkdownEditorRules`.
    private static let rules: [(NSRegularExpression, (NSTextStorage, NSTextCheckingResult, String) -> Void)] = [
        (headingRegex, { storage, match, text in
            let hashes = (text as NSString).substring(with: match.range).prefix { $0 == "#" }.count
            storage.addAttribute(.font, value: hashes <= 1 ? headingLevel1 : hashes == 2 ? headingLevel2 : headingLevel3,
                                 range: match.range)
        }),
        (boldEmphasisRegex, { storage, match, _ in storage.addTrait([.bold, .italic], range: match.range) }),
        (boldRegex, { storage, match, _ in storage.addTrait(.bold, range: match.range) }),
        (asteriskEmphasisRegex, { storage, match, _ in storage.addTrait(.italic, range: match.range) }),
        (underscoreEmphasisRegex, { storage, match, _ in storage.addTrait(.italic, range: match.range) }),
        (inlineCodeRegex, { storage, match, _ in
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: ResultTypography.size, weight: .regular),
                                 range: match.range)
        }),
        (unorderedListRegex, { storage, match, _ in storage.addAttribute(.foregroundColor, value: secondaryLabel, range: match.range) }),
        (orderedListRegex, { storage, match, _ in storage.addAttribute(.foregroundColor, value: secondaryLabel, range: match.range) }),
        (linkRegex, { storage, match, _ in
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
        }),
    ]

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: MarkdownTextView

        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selection = textView.selectedRange()
            MarkdownTextView.highlight(textView)
            textView.setSelectedRange(selection)
            parent.text = textView.string
            parent.onChange()
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onCommit()
        }
    }
}

/// Reports the height its text needs, so the view grows in the same layout pass as the
/// keystroke. Sizing it from SwiftUI state instead meant the frame arrived a pass late: the
/// new line was drawn into a frame still one line short, the view scrolled to keep the caret
/// visible, and then everything settled — which is what the flicker was.
final class AutoGrowingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else {
            return super.intrinsicContentSize
        }
        manager.ensureLayout(for: container)
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: ceil(manager.usedRect(for: container).height) + textContainerInset.height * 2)
    }

    /// The window is draggable by its background, which otherwise swallows a drag across the
    /// text and moves the window instead of selecting.
    override var mouseDownCanMoveWindow: Bool { false }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() } // rewrapping changes the height
    }
}

private extension NSTextStorage {
    /// Adds a trait to whatever font each run already has, so bold inside a heading stays a
    /// heading.
    func addTrait(_ traits: NSFontDescriptor.SymbolicTraits, range: NSRange) {
        enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? bodyFont
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            if let combined = NSFont(descriptor: descriptor, size: font.pointSize) {
                addAttribute(.font, value: combined, range: subrange)
            }
        }
    }
}
#endif
