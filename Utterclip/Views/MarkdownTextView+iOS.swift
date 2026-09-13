#if os(iOS)
import SwiftUI
import UIKit

/// The phone's half of the in-place editor: the same idea as the Mac's, so the two behave
/// alike. The text storage is never replaced — highlighting is applied to it in place — and
/// the view reports the height its text needs, so it grows in the same layout pass as the
/// keystroke rather than a beat later.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    /// Called on every keystroke, for the label and the delayed copy.
    var onChange: () -> Void = {}
    /// Called when the field gives up focus: Done, or a tap outside.
    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> AutoGrowingTextView {
        let textView = AutoGrowingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false // it grows instead; the screen scrolls
        textView.autocorrectionType = .yes
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.text = text
        MarkdownHighlighter.apply(to: textView.textStorage)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        // A Done above the keyboard: on a phone there is often nothing outside the card left
        // to tap once the keyboard is up.
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        let done = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator,
                                   action: #selector(Coordinator.finish))
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        toolbar.sizeToFit()
        textView.inputAccessoryView = toolbar
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
            textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
        }
        return textView
    }

    /// Only for changes that came from somewhere else — a re-style, a restore from History.
    /// Typing never reaches here, which is the point.
    func updateUIView(_ textView: AutoGrowingTextView, context: Context) {
        guard textView.text != text else { return }
        let selection = textView.selectedRange
        textView.text = text
        MarkdownHighlighter.apply(to: textView.textStorage)
        let length = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        textView.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: MarkdownTextView

        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            let selection = textView.selectedRange
            MarkdownHighlighter.apply(to: textView.textStorage)
            textView.selectedRange = selection
            parent.text = textView.text
            parent.onChange()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onCommit()
        }

        @objc func finish() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

/// Reports the height its text needs, so the card grows with the typing instead of chasing it.
final class AutoGrowingTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        // Before the first layout there is no width to wrap against. Guessing one is far
        // better than reporting nothing: a zero height makes the view invisible, and SwiftUI
        // has no reason to ask again.
        let width = bounds.width > 0
            ? bounds.width
            : max(120, (window?.bounds.width ?? UIScreen.main.bounds.width) - 64)
        let fitted = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric,
                      height: max(ceil(fitted.height), ResultTypography.lineHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth { // rewrapping changes the height
            lastWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    private var lastWidth: CGFloat = 0
}
#endif
