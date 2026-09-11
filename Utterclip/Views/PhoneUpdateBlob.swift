import SwiftUI
import UtterclipCore

/// The small capsule that says the phone has something. Two states, deliberately different:
/// - in progress ("iPhone · Recording…"): quiet, secondary text on a faint fill, a pulsing dot,
///   not interactive — pure information;
/// - landed ("New from iPhone" + first words): solid label-primary capsule with inverted text,
///   a spring in, one bounce, and a click pulls the dictation into this window.
/// A stale in-progress capsule (the phone stopped syncing) shows a ✕ and clears on click.
struct PhoneUpdateBlob: View {
    let update: RecorderViewModel.PhoneUpdate
    let claim: () -> Void
    let dismiss: () -> Void

    @State private var pulsing = false
    @State private var bounce = false

    var body: some View {
        Group {
            if update.isReady {
                Button(action: claim) { content }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
                    .accessibilityLabel("New dictation from \(update.deviceName). Click to open it here.")
            } else {
                content
                    .allowsHitTesting(false) // information only until the text has landed
                    .accessibilityLabel(update.title)
            }
        }
        // Always dismissable: the phone's business is not always the Mac's, and this sits in
        // the window until the phone goes quiet on its own.
        .overlay(alignment: .trailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(update.isReady
                        ? AnyShapeStyle(Color.appBackground.opacity(0.6))
                        : AnyShapeStyle(.secondary))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .accessibilityLabel("Dismiss")
        }
        .scaleEffect(bounce ? 1.06 : 1)
        .onAppear { startPulsing() }
        .onChange(of: update.isReady) { _, ready in
            if ready {
                // The little dance when the text lands.
                withAnimation(.spring(duration: 0.35, bounce: 0.6)) { bounce = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(.spring(duration: 0.35, bounce: 0.5)) { bounce = false }
                }
            } else {
                startPulsing()
            }
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(update.isReady ? AnyShapeStyle(Color.appBackground) : AnyShapeStyle(.secondary))
                .frame(width: 8, height: 8)
                .opacity(update.isReady ? 1 : (pulsing ? 0.25 : 1))
            Text(update.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(update.isReady ? AnyShapeStyle(Color.appBackground) : AnyShapeStyle(.secondary))
            if let preview = update.preview {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(Color.appBackground.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 26) // room for the ✕ that sits on top
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // No width of its own: it hugs short text and truncates long text at whatever the
        // window leaves, so it never reaches past the style pills' margin.
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if update.isReady {
                Capsule().fill(.primary)
            } else {
                Capsule().fill(Color.pillFill)
            }
        }
        .contentShape(Capsule())
    }

    private func startPulsing() {
        guard !update.isReady else { return }
        pulsing = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulsing = true }
    }
}
