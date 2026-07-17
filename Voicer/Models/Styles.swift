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

    static let structured = MessageStyle(
        id: "structured",
        name: "Structured",
        emoji: "🗂️",
        systemPrompt: "Turn the transcript into a well-organized, structured response. Use a short intro, then clear points (headings or bullets where helpful). Correct grammar, keep it precise. End after the last point — no closing remarks, encouragement, or commentary. Preserve the original language. Output only the formatted answer."
    )

    static let summary = MessageStyle(
        id: "summary",
        name: "Summary",
        emoji: "📝",
        systemPrompt: "Summarize the transcript into its key points as a concise digest suitable for a summary channel. Lead with a one-line takeaway, then 3–6 short bullets of the essentials. Drop filler and repetition. Preserve the original language. Output only the summary."
    )

    /// All styles, in display order.
    static let all: [MessageStyle] = [slack, email, whatsapp, structured, summary]

    /// The one-tap default for v1 (changeable in Settings).
    static let defaultStyle = slack

    static func style(withID id: String) -> MessageStyle {
        all.first { $0.id == id } ?? defaultStyle
    }
}
