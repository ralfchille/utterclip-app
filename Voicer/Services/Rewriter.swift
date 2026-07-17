import Foundation

/// Swappable rewrite engine (plan Phase 5). v1 ships `CloudRewriter`; a future on-device
/// `LocalRewriter` (MLX) conforms to the same protocol with no UI change.
protocol Rewriter {
    func rewrite(_ text: String, style: MessageStyle) async throws -> String
}
