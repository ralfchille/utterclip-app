import SwiftUI
import UtterclipCore

/// The small capsule that says the phone has something: "iPhone · Recording…" with a pulsing
/// dot while it works, "New from iPhone" plus the first words once the result is here. A tap
/// pulls the dictation into this window; before that a tap only wobbles. Mac only in practice
/// (the phone never watches other devices).
struct PhoneUpdateBlob: View {
    let update: RecorderViewModel.PhoneUpdate
    let claim: () -> Void

    @State private var pulsing = false
    @State private var bounce = false
    @State private var wobble = 0.0

    var body: some View {
        Button {
            if update.isReady {
                claim()
            } else {
                withAnimation(.spring(duration: 0.3, bounce: 0.6)) { wobble = wobble == 0 ? 1 : 0 }
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(update.isReady ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 8, height: 8)
                    .opacity(update.isReady ? 1 : (pulsing ? 0.25 : 1))
                Text(update.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if let preview = update.preview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 320)
            .fixedSize(horizontal: false, vertical: true)
            .glassBackground(shape: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(bounce ? 1.06 : 1)
        .rotationEffect(.degrees(wobble == 0 ? 0 : 2), anchor: .center)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .accessibilityLabel(update.isReady ? "New dictation from \(update.deviceName). Tap to open it here." : update.title)
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

    private func startPulsing() {
        guard !update.isReady else { return }
        pulsing = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulsing = true }
    }
}
