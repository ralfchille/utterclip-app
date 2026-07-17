import Foundation

/// Default style definitions (plan Appendix A, used as-is for v1).
enum Styles {
    static let slack = MessageStyle(
        id: "slack",
        name: "Slack",
        emoji: "💬",
        systemPrompt: "Rewrite the transcript as a clear, concise Slack message to work colleagues. Professional but friendly. Fix grammar and filler words. Keep it brief, use short paragraphs, no greeting or sign-off. Preserve the original language. Output only the message."
    )

    static let email = MessageStyle(
        id: "email",
        name: "Email",
        emoji: "✉️",
        systemPrompt: "Rewrite the transcript as a well-structured email. Add a suitable subject line, a brief greeting, clear body paragraphs, and a polite closing. Correct grammar and remove filler. Keep the original language. Output subject then body."
    )

    static let whatsapp = MessageStyle(
        id: "whatsapp",
        name: "WhatsApp",
        emoji: "📱",
        systemPrompt: "Rewrite the transcript as a WhatsApp message to family or a friend. Warm and personal, but not overly casual — no slang, no exclamation pile-ups, at most one emoji and only if it genuinely fits. Stay close to my own phrasing and word choices from the transcript; fix grammar and drop filler, but don't smooth away how I naturally speak. Preserve the original language. Output only the message."
    )

    static let prompt = MessageStyle(
        id: "prompt",
        name: "Prompt",
        emoji: "🤖",
        systemPrompt: "Rewrite the transcript as a clear, well-structured prompt for an AI assistant. Lead with the goal, then the relevant context and constraints, then what the output should look like — use markdown bullets where it helps. Keep everything that was said and don't invent requirements that weren't. Drop filler. Preserve the original language. Output only the prompt."
    )

    static let summary = MessageStyle(
        id: "summary",
        name: "Summary",
        emoji: "📝",
        systemPrompt: "Summarize the transcript in markdown: a one-line takeaway, then 3–5 short bullets with the essentials. Drop filler and repetition. No closing remarks. Preserve the original language. Output only the summary."
    )

    /// All styles, in display order.
    static let all: [MessageStyle] = [slack, prompt, email, whatsapp, summary]

    /// The one-tap default for v1 (changeable in Settings).
    static let defaultStyle = slack

    static func style(withID id: String) -> MessageStyle {
        all.first { $0.id == id } ?? defaultStyle
    }
}
