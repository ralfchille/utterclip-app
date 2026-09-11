import SwiftUI
import UtterclipCore

/// The confirm step for a dictation started with the global shortcut: the text is ready and on
/// the clipboard, and this says where it will go. Clicking the bar (or Return) sends it; the ✕
/// inside it leaves the text on the clipboard and nothing else happens. Until then the result
/// above stays editable, so a transcription that came out wrong can be fixed or re-styled
/// before it lands in someone else's document.
///
/// It sits directly under the record button, where the eye already is after clicking stop.
struct PasteBackBar: View {
    let appName: String
    let paste: () -> Void
    let dismiss: () -> Void

    var body: some View {
        Button(action: paste) {
            HStack(spacing: 8) {
                Image(systemName: "return")
                    .font(.caption.weight(.semibold))
                Text("Paste into \(appName)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 28) // room for the ✕ that sits on top
            }
            .foregroundStyle(Color.appBackground)
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(.primary))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction) // Return, wherever the focus is in the window
        .overlay(alignment: .trailing) {
            // Its own target inside the bar: cancel without sending.
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appBackground.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.appBackground.opacity(0.16)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 7)
            .accessibilityLabel("Keep it on the clipboard")
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}
