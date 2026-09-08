import Foundation

/// A rewrite style: a named system prompt the rewriter applies to the raw transcript.
/// Built-ins come from `Styles`; user-added ones are persisted by `StyleStore`.
public struct MessageStyle: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let systemPrompt: String

    public init(id: String, name: String, systemPrompt: String) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
    }
}
