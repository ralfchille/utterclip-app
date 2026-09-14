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
    /// Esc on a hardware keyboard; the phone's own keyboard has no such key.
    var onCancel: () -> Void = {}

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
        textView.onCancel = onCancel
        MarkdownHighlighter.apply(to: textView.textStorage)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.inputAccessoryView = Self.doneButton(target: context.coordinator,
                                                      action: #selector(Coordinator.finish))
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

    /// One round button floating above the keyboard, right-aligned: the app's own language —
    /// label-primary fill, inverted glyph, like the selected style pill — rather than a grey
    /// system bar stuck to the keys. The transparent strip below it holds it clear of them.
    private static func doneButton(target: Any, action: Selector) -> UIView {
        let diameter: CGFloat = 48
        let gapAboveKeyboard: CGFloat = 14
        let container = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                             height: diameter + gapAboveKeyboard))
        container.backgroundColor = .clear

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.image = UIImage(systemName: "checkmark",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        let button = UIButton(configuration: configuration)
        button.addTarget(target, action: action, for: .touchUpInside)
        button.accessibilityLabel = "Done editing"
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowRadius = 10
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: diameter),
            button.heightAnchor.constraint(equalToConstant: diameter),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
        return container
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

        /// The check button: give up focus, which lowers the keyboard and commits through
        /// `textViewDidEndEditing`. Return still inserts a newline.
        @objc func finish() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }

    }
}

/// Reports the height its text needs, so the card grows with the typing instead of chasing it.
final class AutoGrowingTextView: UITextView {
    /// Esc on a hardware keyboard, the same as on the Mac. The on-screen keyboard has no
    /// such key, so on a phone this never fires and the check button is the way out.
    var onCancel: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelEdit))]
    }

    @objc private func cancelEdit() { onCancel?() }

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
