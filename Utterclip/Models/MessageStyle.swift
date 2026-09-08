import Foundation

/// A rewrite style: a named system prompt the rewriter applies to the raw transcript.
/// Built-ins come from `Styles`; user-added ones are persisted by `StyleStore`.
struct MessageStyle: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let systemPrompt: String
}
