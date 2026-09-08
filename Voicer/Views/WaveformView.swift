import SwiftUI

/// WhatsApp-style live waveform: one capsule per mic sample, entering on the right
/// and sliding left as new samples arrive. Quiet samples stay dots; speech grows
/// them into vertical lines.
struct WaveformView: View {
    let levels: [LevelSample]

    private static let barWidth: CGFloat = 3
    private static let spacing: CGFloat = 3
    private static let maxHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(levels) { sample in
                Capsule()
                    .fill(.primary)
                    .frame(
                        width: Self.barWidth,
                        height: max(Self.barWidth, CGFloat(sample.value) * Self.maxHeight)
                    )
            }
        }
        .frame(width: 240, height: Self.maxHeight, alignment: .trailing)
        .clipped()
        // Deliberately not animated: animating the per-tick insert/remove makes
        // neighboring bars overlap mid-slide and the strip shimmers. Discrete
        // steps at the sampling rate read as a smooth scroll.
        .transaction { $0.animation = nil }
    }
}
