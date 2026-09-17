import SwiftUI
import HighlightedTextEditor

/// Editor for quick tweaks to transcribed or formatted text: full screen on iOS, in place
/// inside the window on macOS.
///
/// Uses HighlightedTextEditor with our own rules (`utterclipMarkdown`) so headings and
/// emphasis show at the same sizes as in the result view, while the content remains
/// plain, editable markdown — which keeps the rest of the pipeline (clipboard,
/// `MarkdownStripper`) working on the same string the user sees. The edit is only committed by
/// the confirming action; closing discards it, so a mistaken tap never destroys the result.
struct EditorView: View {
    let title: String
    let onSave: (String) -> Void

    @State private var text: String
    @State private var isConfirmingDiscard = false
    /// What was there when the editor opened, so closing can tell whether anything is at stake.
    private let original: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.panelDismiss) private var panelDismiss

    init(title: String, initialText: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        self.original = initialText
        _text = State(initialValue: initialText)
    }

    private var hasChanges: Bool { text != original }

    var body: some View {
        SheetNavigation {
            VStack(spacing: 0) {
                #if os(macOS)
                MacHeader(title: title) {
                    Button("Cancel") { close() }
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                    Button("Done") { save() }
                        .font(.body.weight(.semibold))
                }
                #endif
                HighlightedTextEditor(text: $text, highlightRules: .utterclipMarkdown)
                    .padding(.horizontal, 12) // breathing room so text isn't flush to the edges
                    .editorTopInset()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.appBackground)
            .ignoreHiddenTitleBar()
            // The same places History and Settings put theirs — both trailing on iOS — with
            // the primary action furthest out, and symbols rather than words.
            .barChrome(title: title) {
                ToolbarItem(placement: .sheetCancel) {
                    Group {
                        if #available(iOS 26.0, macOS 26.0, *) {
                            Button(role: .close) { close() }
                        } else {
                            Button("Cancel") { close() }
                        }
                    }
                    // Anchored to the button, like History's Clear, so it rises from there
                    // rather than arriving in the middle of the screen.
                    .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard,
                                        titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismissNow() }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .sheetConfirm) {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        Button { save() } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .buttonStyle(.glassProminent)
                    } else {
                        Button("Done") { save() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .tint(.primary)
        // A swipe down would go around the question, so it waits while there is something
        // to lose; the close button is then the way out, and it asks.
        .interactiveDismissDisabled(hasChanges)
    }

    private func close() {
        if hasChanges { isConfirmingDiscard = true } else { dismissNow() }
    }

    private func dismissNow() {
        if let panelDismiss { panelDismiss() } else { dismiss() }
    }

    private func save() {
        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
        dismissNow()   // confirming is not discarding; it never asks
    }
}
