import SwiftUI

/// Row of style buttons shown after a result — tapping one re-runs the rewrite and
/// re-copies (plan Phase 6).
struct StylePickerRow: View {
    let selected: MessageStyle
    let isDisabled: Bool
    let onSelect: (MessageStyle) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StyleStore.shared.styles) { style in
                    Button {
                        onSelect(style)
                    } label: {
                        HStack(spacing: 4) {
                            Text(style.emoji)
                            Text(style.name)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(style.id == selected.id ? Color(.systemBackground) : .primary)
                        .background {
                            if style.id == selected.id {
                                Capsule().fill(.primary)
                            }
                        }
                        .glassBackground()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rewrite as \(style.name)")
                }
            }
            .padding(.horizontal)
        }
        .disabled(isDisabled)
    }
}
