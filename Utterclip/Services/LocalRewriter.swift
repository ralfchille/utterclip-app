import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device rewrite through Apple's Foundation Models (iOS 26, Apple Intelligence):
/// nothing leaves the phone and no API key is needed. Quality sits a notch below the
/// cloud models — fine for Plain and light restyling, weaker on nuanced tone and German.
struct LocalRewriter: Rewriter {
    /// True when the system model can run here right now.
    static var isAvailable: Bool { unavailabilityReason == nil }

    /// Why the on-device model can't be used on this device, or nil if it can.
    static var unavailabilityReason: String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { return "Needs iOS 26." }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading its model."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
        #else
        return "Needs iOS 26."
        #endif
    }

    func rewrite(_ text: String, style: MessageStyle) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { throw AppError.rewriteFailed("On-device rewriting needs iOS 26.") }
        if let reason = Self.unavailabilityReason { throw AppError.rewriteFailed(reason) }

        // Small models follow "write in English" far better than "same language as the
        // transcript", and Apple's drifts to the device language otherwise. Pin the detected
        // language explicitly, then verify the result.
        let language = Self.dominantLanguage(of: text)
        var instructions = RewritePrompt.system(for: style)
        var prompt = RewritePrompt.user(for: text)
        if let language {
            let name = Self.name(of: language)
            instructions += "\n\nThe transcript is in \(name). The output must be in \(name) — not the device language, not the language of the style instructions."
            prompt += "\n\nWrite the output in \(name)."
        }
        let session = LanguageModelSession(instructions: instructions)
        do {
            var content = try await Self.generate(session, prompt)
            if let language, let produced = Self.dominantLanguage(of: content), produced != language {
                // One correction in the same session; then fail loudly rather than hand back
                // a translation.
                content = try await Self.generate(
                    session,
                    "That was in \(Self.name(of: produced)). Redo it in \(Self.name(of: language)) — same content, same style.")
                if let again = Self.dominantLanguage(of: content), again != language {
                    throw AppError.rewriteFailed(
                        "The on-device model answered in \(Self.name(of: again)) instead of \(Self.name(of: language)). Try again, or use a cloud engine for this one.")
                }
            }
            guard !content.isEmpty else { throw AppError.rewriteFailed("The on-device model returned nothing.") }
            return content
        } catch let error as AppError {
            throw error
        } catch is CancellationError {
            throw CancellationError() // the user tapped ✕
        } catch {
            throw AppError.rewriteFailed("On-device model: \(error.localizedDescription)")
        }
        #else
        throw AppError.rewriteFailed("On-device rewriting isn't available in this build.")
        #endif
    }

    #if canImport(FoundationModels)
    /// Guided generation: the model fills a field instead of composing a reply, which removes
    /// most of the "Sure, here's your text:" framing small models add.
    @available(iOS 26, *)
    private static func generate(_ session: LanguageModelSession, _ prompt: String) async throws -> String {
        let response = try await session.respond(
            to: prompt,
            generating: Rewrite.self,
            options: GenerationOptions(sampling: .greedy))
        return stripChatter(response.content.text)
    }
    #endif

    /// The dominant language when the recognizer is reasonably sure; nil for short or mixed
    /// text, so a wrong guess never forces the wrong language.
    static func dominantLanguage(of text: String) -> NLLanguage? {
        guard text.count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
              (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) >= 0.6 else { return nil }
        return language
    }

    /// English name for prompting, e.g. "German".
    static func name(of language: NLLanguage) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue) ?? language.rawValue
    }

    /// Safety net for what guided generation doesn't catch: a one-line preamble about the
    /// rewrite, and a result quoted as a whole. Deliberately conservative — the cloud
    /// models don't need it and dictated text must survive untouched.
    static func stripChatter(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstBreak = text.firstIndex(of: "\n") {
            let firstLine = text[..<firstBreak].trimmingCharacters(in: .whitespaces)
            let lowered = firstLine.lowercased()
            let talksAboutRewrite = ["here", "rewritten", "rewrite", "version", "transcript"]
                .contains { lowered.contains($0) }
            if firstLine.hasSuffix(":"), talksAboutRewrite {
                text = text[text.index(after: firstBreak)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let quotePairs: [(open: Character, close: Character)] = [("\"", "\""), ("“", "”"), ("„", "“")]
        for pair in quotePairs where text.count >= 2 && text.first == pair.open && text.last == pair.close {
            let inner = text.dropFirst().dropLast()
            if !inner.contains(pair.open) && !inner.contains(pair.close) {
                text = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            break
        }
        return text
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private struct Rewrite {
    @Guide(description: "The rewritten transcript and nothing else — no introduction, no commentary, no surrounding quotation marks.")
    var text: String
}
#endif
