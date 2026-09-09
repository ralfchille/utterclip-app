import Foundation

/// Default style definitions (plan Appendix A, used as-is for v1).
public enum Styles {
    public static let plain = MessageStyle(
        id: "plain",
        name: "Plain",
        systemPrompt: "Correct the transcript without rewriting it: fix grammar, spelling, punctuation, capitalization, and obvious transcription mistakes, and drop stutters and filler sounds (um, uh). Keep my wording, sentence order, and tone exactly as spoken — do not rephrase, shorten, restructure, or add anything. Preserve the original language. Output only the corrected text."
    )

    public static let slack = MessageStyle(
        id: "slack",
        name: "Slack",
        systemPrompt: "Rewrite the transcript as a clear, concise Slack message to work colleagues. Professional but friendly. Fix grammar and filler words. Keep it brief, use short paragraphs, no greeting or sign-off. Preserve the original language. Output only the message."
    )

    public static let email = MessageStyle(
        id: "email",
        name: "Email",
        systemPrompt: "Rewrite the transcript as a well-structured email. Add a suitable subject line, a brief greeting, clear body paragraphs, and a polite closing. Correct grammar and remove filler. Keep the original language. Output subject then body."
    )

    public static let whatsapp = MessageStyle(
        id: "whatsapp",
        name: "WhatsApp",
        systemPrompt: "Rewrite the transcript as a WhatsApp message to family or a friend. Warm and personal, but not overly casual — no slang, no exclamation pile-ups, at most one emoji and only if it genuinely fits. Stay close to my own phrasing and word choices from the transcript; fix grammar and drop filler, but don't smooth away how I naturally speak. Preserve the original language. Output only the message."
    )

    public static let prompt = MessageStyle(
        id: "prompt",
        name: "Prompt",
        systemPrompt: "Rewrite the transcript as a prompt for an AI assistant, structured under four markdown headings in this order: ## The job — what to do, stated plainly; ## The why — the context and motivation behind it; ## The guardrails — constraints, things to avoid, non-negotiables; ## Done means — what a finished, acceptable result looks like. Use short bullets under each heading. Fill every section only from what was said; if the transcript gives nothing for a section, write a single line saying it was not specified rather than inventing content. Drop filler. Preserve the original language. Output only the prompt."
    )

    /// All styles, in display order.
    public static let all: [MessageStyle] = [plain, slack, whatsapp, prompt, email]

    /// The style selected when the app is first opened (changeable in Settings). Plain: the
    /// least opinionated rewrite, so a first dictation comes back as what was said, tidied.
    public static let defaultStyle = plain

    public static func style(withID id: String) -> MessageStyle {
        all.first { $0.id == id } ?? defaultStyle
    }
}
