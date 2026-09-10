import Foundation

/// A rewrite style: a named system prompt the rewriter applies to the raw transcript.
/// Built-ins come from `Styles`; user-added ones are persisted by `StyleStore`.
public struct MessageStyle: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let systemPrompt: String
    /// The style's output is Markdown worth keeping: the result card offers the Markdown
    /// copy switch. Off (most styles): results are always copied as plain text and the
    /// switch stays out of the way.
    public let usesMarkdown: Bool

    public init(id: String, name: String, systemPrompt: String, usesMarkdown: Bool = false) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.usesMarkdown = usesMarkdown
    }

    // Styles saved by 1.0 have no `usesMarkdown`; they decode as plain-text styles.
    private enum CodingKeys: String, CodingKey { case id, name, systemPrompt, usesMarkdown }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        usesMarkdown = try c.decodeIfPresent(Bool.self, forKey: .usesMarkdown) ?? false
    }
}
