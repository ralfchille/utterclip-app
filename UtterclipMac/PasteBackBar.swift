import SwiftUI
import UtterclipCore

/// The confirm step for a dictation started with the global shortcut: the text is ready and on
/// the clipboard, and this says where it will go. Return sends it; the ✕ leaves it on the
/// clipboard and nothing else happens. Until then the result above stays editable, so a
/// transcription that came out wrong can be fixed or re-styled before it lands in someone
/// else's document.
struct PasteBackBar: View {
    let appName: String
    let paste: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: paste) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.caption.weight(.semibold))
                    Text("Paste into \(appName)")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text("⏎")
                        .font(.caption.weight(.semibold))
                        .opacity(0.6)
                }
                .foregroundStyle(Color.appBackground)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(.primary))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction) // Return, wherever the focus is in the window

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.pillFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Keep it on the clipboard")
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}
