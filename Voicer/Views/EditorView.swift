import SwiftUI
import HighlightedTextEditor

/// Full-screen editor for quick tweaks to transcribed or formatted text.
///
/// Uses HighlightedTextEditor's `.markdown` preset so headings and emphasis stay
/// visually distinct while the content remains plain, editable markdown — which
/// keeps the rest of the pipeline (clipboard, `MarkdownStripper`) working on the
/// same string the user sees. The edit is only committed on "Done"; "Cancel"
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
        NavigationStack {
            HighlightedTextEditor(text: $text, highlightRules: .markdown)
                .padding(.horizontal, 12) // breathing room so text isn't flush to the edges
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .tint(.primary)
    }
}
