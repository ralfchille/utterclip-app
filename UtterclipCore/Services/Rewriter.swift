import Foundation

/// Swappable rewrite engine (plan Phase 5). `CloudRewriter` (API key) and `LocalRewriter`
/// (Apple Foundation Models) both conform, so the UI never cares which one runs.
public protocol Rewriter {
    func rewrite(_ text: String, style: MessageStyle) async throws -> String
}
