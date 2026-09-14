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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.panelDismiss) private var panelDismiss

    init(title: String, initialText: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

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
            // Apple's toolbar guidance: the close button is a symbol on the leading edge and
            // carries no "Close" label, and there is exactly one primary action, prominent,
            // on the trailing edge. Text buttons on both sides was the shape before that.
            .barChrome(title: title) {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        Button(role: .close) { close() }
                    } else {
                        Button("Cancel") { close() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
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
    }

    private func close() {
        if let panelDismiss { panelDismiss() } else { dismiss() }
    }

    private func save() {
        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
        close()
    }
}
