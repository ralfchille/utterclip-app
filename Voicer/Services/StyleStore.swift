import Foundation
import Observation

/// User-editable style prompts. Defaults come from `Styles`; edits are stored as
/// per-style overrides in UserDefaults so a reset always recovers the original.
@Observable
@MainActor
final class StyleStore {
    static let shared = StyleStore()

    private static let overridesKey = "stylePromptOverrides"

    /// style id → custom system prompt
    private var overrides: [String: String] {
        didSet { UserDefaults.standard.set(overrides, forKey: Self.overridesKey) }
    }

    private init() {
        overrides = UserDefaults.standard
            .dictionary(forKey: Self.overridesKey) as? [String: String] ?? [:]
    }

    /// All styles with any custom prompts applied, in display order.
    var styles: [MessageStyle] {
        Styles.all.map { style in
            guard let custom = overrides[style.id] else { return style }
            return MessageStyle(
                id: style.id, name: style.name, systemPrompt: custom)
        }
    }

    func style(withID id: String) -> MessageStyle {
        styles.first { $0.id == id } ?? styles[0]
    }

    func isCustomized(_ id: String) -> Bool {
        overrides[id] != nil
    }

    func setPrompt(_ prompt: String, for id: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Styles.style(withID: id).systemPrompt {
            overrides[id] = nil
        } else {
            overrides[id] = trimmed
        }
    }

    func resetPrompt(for id: String) {
        overrides[id] = nil
    }
}
