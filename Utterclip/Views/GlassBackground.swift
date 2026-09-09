import SwiftUI

/// Applies Liquid Glass on iOS 26 / macOS 26 and later, falls back to an ultra-thin
/// material before that (plan §1a). The one place in the app where the availability
/// check lives.
struct GlassBackground<S: Shape>: ViewModifier {
    var shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: shape) // Liquid Glass
        } else {
            content.background(.ultraThinMaterial, in: shape) // fallback
        }
    }
}

extension View {
    func glassBackground(shape: some Shape = Capsule()) -> some View {
        modifier(GlassBackground(shape: shape))
    }
}
