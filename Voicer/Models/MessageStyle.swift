import Foundation

/// A rewrite style: a named system prompt the rewriter applies to the raw transcript.
struct MessageStyle: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let systemPrompt: String
}
