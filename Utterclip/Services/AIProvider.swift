import Foundation

/// The cloud LLM behind a rewrite, detected from the API key's prefix so a single key
/// field serves every supported provider. Each case knows its endpoint, a fast default
/// model, and how to shape the request and read the reply.
enum AIProvider: String, CaseIterable {
    case anthropic, openAI, gemini, groq

    /// Prefix match, most specific first — `sk-ant-` must win over OpenAI's bare `sk-`.
    static func detect(_ key: String) -> AIProvider? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix("sk-ant-") { return .anthropic }
        if key.hasPrefix("gsk_") { return .groq }
        if key.hasPrefix("AIza") { return .gemini }
        if key.hasPrefix("sk-") { return .openAI }
        return nil
    }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .groq: "Groq"
        }
    }

    /// Fast, inexpensive models suited to short rewrites.
    var defaultModel: String {
        switch self {
        case .anthropic: "claude-haiku-4-5"
        case .openAI: "gpt-5-mini"
        case .gemini: "gemini-2.5-flash"
        case .groq: "llama-3.3-70b-versatile"
        }
    }

    /// The provider-specific POST for a system prompt plus one user message. Keys travel
    /// in headers only — never in the URL.
    func request(apiKey: String, system: String, user: String, maxTokens: Int = 1024) throws -> URLRequest {
        var request: URLRequest
        let body: [String: Any]
        switch self {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": defaultModel,
                "max_tokens": maxTokens,
                "temperature": 0,
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            // GPT-5 models reject a non-default temperature; minimal reasoning keeps a
            // plain rewrite fast.
            body = [
                "model": defaultModel,
                "max_completion_tokens": maxTokens,
                "reasoning_effort": "minimal",
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
            ]
        case .groq:
            request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": defaultModel,
                "max_tokens": maxTokens,
                "temperature": 0,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user],
                ],
            ]
        case .gemini:
            request = URLRequest(url: URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models/\(defaultModel):generateContent")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "system_instruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": user]]]],
                "generationConfig": [
                    "temperature": 0,
                    "maxOutputTokens": maxTokens,
                    "thinkingConfig": ["thinkingBudget": 0], // a rewrite needs no deliberation
                ],
            ]
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The reply text, or nil when the payload doesn't have the expected shape.
    func text(from data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch self {
        case .anthropic:
            return (json?["content"] as? [[String: Any]])?
                .first { $0["type"] as? String == "text" }?["text"] as? String
        case .openAI, .groq:
            let message = (json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            return message?["content"] as? String
        case .gemini:
            let content = (json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any]
            let texts = (content?["parts"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
            return texts.isEmpty ? nil : texts.joined()
        }
    }
}
