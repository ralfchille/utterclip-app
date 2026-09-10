import SwiftUI
import HighlightedTextEditor

/// Editor for quick tweaks to transcribed or formatted text: full screen on iOS, in place
/// inside the window on macOS.
///
/// Uses HighlightedTextEditor with our own rules (`utterclipMarkdown`) so headings and
/// emphasis show at the same sizes as in the result view, while the content remains
/// plain, editable markdown — which keeps the rest of the pipeline (clipboard,
/// `MarkdownStripper`) working on the same string the user sees. The edit is only committed on "Done"; "Cancel"
/// discards it, so a mistaken tap never destroys the result.
struct EditorView: View {
    let title: String
    let onSave: (String) -> Void

    @State private var text: String
    @Environment(\.dismiss) private var dismiss

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
                    Button("Cancel") { dismiss() }
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
            .barChrome(title: title) {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(.primary)
    }

    private func save() {
        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
