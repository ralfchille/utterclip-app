import Foundation
import os

/// Cloud rewrite engine (plan Phase 5). Which API it calls follows from the stored key —
/// see `AIProvider.detect` — so one key field serves every supported provider. The
/// prompting itself is `RewritePrompt`, shared with the on-device `LocalRewriter`.
struct CloudRewriter: Rewriter {
    /// Key source — the user's key from the Keychain (plan §5a).
    let keyProvider: () -> String?

    func rewrite(_ text: String, style: MessageStyle) async throws -> String {
        guard let apiKey = keyProvider(), !apiKey.isEmpty else { throw AppError.noApiKey }
        guard let provider = AIProvider.detect(apiKey) else {
            throw AppError.rewriteFailed(
                "Unrecognized API key. Supported: Anthropic (sk-ant-…), OpenAI (sk-…), Google Gemini (AIza…), Groq (gsk_…).")
        }
        let request = try provider.request(
            apiKey: apiKey,
            system: RewritePrompt.system(for: style),
            user: RewritePrompt.user(for: text))

        let data: Data
        let response: URLResponse
        let start = ContinuousClock.now
        do {
            (data, response) = try await URLSession.shared.data(for: request)
            Logger(subsystem: "com.ralfchille.utterclip", category: "rewrite")
                .info("Rewrite via \(provider.displayName, privacy: .public) took \(ContinuousClock.now - start, privacy: .public)")
        } catch is CancellationError {
            throw CancellationError() // the user tapped ✕ — not a network problem
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AppError.rewriteFailed("Network error — raw transcript is still on your clipboard.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.rewriteFailed("Unexpected response.")
        }
        guard http.statusCode == 200 else {
            let detail = Self.errorMessage(from: data)
            // 401/403 everywhere, plus Gemini's 400 "API key not valid": the key is the problem.
            if http.statusCode == 401 || http.statusCode == 403
                || detail?.localizedCaseInsensitiveContains("api key") == true {
                throw AppError.noApiKey
            }
            throw AppError.rewriteFailed(detail ?? "HTTP \(http.statusCode)")
        }

        guard let content = provider.text(from: data) else {
            throw AppError.rewriteFailed("Could not parse the response.")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All supported providers report errors as `{"error": {"message": …}}`.
    private static func errorMessage(from data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["error"] as? [String: Any])?["message"] as? String
    }
}
