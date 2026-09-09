import SwiftUI
import UtterclipCore

/// Row of style buttons shown after a result — tapping one re-runs the rewrite and
/// re-copies (plan Phase 6).
struct StylePickerRow: View {
    let selected: MessageStyle
    let isDisabled: Bool
    let onSelect: (MessageStyle) -> Void

    /// Pill height plus a little air, so the GeometryReader has a definite height.
    private static let rowHeight: CGFloat = 40

    var body: some View {
        // The row is at least as wide as its container, so a set of pills that fits sits
        // centred; a wider set grows past the container and scrolls, starting at the left.
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                pills
                    .padding(.horizontal)
                    .frame(minWidth: geometry.size.width, minHeight: Self.rowHeight)
            }
        }
        .frame(height: Self.rowHeight)
        .disabled(isDisabled)
    }

    private var pills: some View {
            HStack(spacing: 8) {
                ForEach(StyleStore.shared.styles) { style in
                    Button {
                        onSelect(style)
                    } label: {
                        Text(style.name)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(style.id == selected.id ? Color.appBackground : .primary)
                            // Flat capsules per the Figma style picker: solid primary when selected,
                            // systemGray6 otherwise — no glass layer, so no shadow and no washed-out black.
                            .background(
                                Capsule().fill(style.id == selected.id ? Color.primary : Color.pillFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rewrite as \(style.name)")
                }
            }
    }
}
