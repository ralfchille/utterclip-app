import Foundation

/// Swaps personal identifiers for stable placeholders before text leaves the device, and
/// puts them back afterwards. Only deterministic `NSDataDetector` types are covered —
/// emails, phone numbers, links, addresses — because they're opaque to a rewriter, so the
/// result quality is unaffected. Person names are deliberately left alone: detecting them
/// is unreliable and they carry tone the rewrite needs.
public enum Redactor {
    /// One round trip's placeholders and what they stand for.
    public struct Redaction {
        /// The text with placeholders in place of the originals.
        public let text: String
        /// placeholder → original
        public let originals: [String: String]
    }

    /// `.link` covers both URLs and email addresses (as `mailto:`).
    private static let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .address]

    public static func redact(_ text: String) -> Redaction {
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return Redaction(text: text, originals: [:])
        }
        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // Assign tokens front-to-back so numbering reads naturally and a repeated value
        // reuses its token; then substitute back-to-front so earlier ranges stay valid.
        var tokenFor: [String: String] = [:]
        var originals: [String: String] = [:]
        var counters: [String: Int] = [:]
        var substitutions: [(range: NSRange, token: String)] = []
        for match in matches {
            let original = nsText.substring(with: match.range)
            let token: String
            if let existing = tokenFor[original] {
                token = existing
            } else {
                let kind = label(for: match)
                let n = (counters[kind] ?? 0) + 1
                counters[kind] = n
                token = "⟦\(kind)_\(n)⟧"
                tokenFor[original] = token
                originals[token] = original
            }
            substitutions.append((match.range, token))
        }

        var result = nsText
        for substitution in substitutions.reversed() {
            result = result.replacingCharacters(in: substitution.range, with: substitution.token) as NSString
        }
        return Redaction(text: result as String, originals: originals)
    }

    /// Restores the originals; a token the model altered or dropped simply stays as is.
    public static func restore(_ text: String, _ redaction: Redaction) -> String {
        redaction.originals.reduce(text) { partial, entry in
            partial.replacingOccurrences(of: entry.key, with: entry.value)
        }
    }

    private static func label(for match: NSTextCheckingResult) -> String {
        switch match.resultType {
        case .link: return match.url?.scheme == "mailto" ? "EMAIL" : "LINK"
        case .phoneNumber: return "PHONE"
        case .address: return "ADDRESS"
        default: return "DATA"
        }
    }
}
