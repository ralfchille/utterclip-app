import Foundation
import Observation

/// The rewrite styles the app offers: the built-ins from `Styles` (with any user-edited
/// prompts applied as overrides, so a reset always recovers the original) plus styles the
/// user added, up to `maxStyles` in total. Everything persists in UserDefaults and, through
/// `SyncedDefaults`, follows the user to their other devices.
@Observable
@MainActor
public final class StyleStore {
    public static let shared = StyleStore()

    /// Hard cap on the picker row, built-ins included.
    public static let maxStyles = 7

    private static let overridesKey = "stylePromptOverrides"
    private static let nameOverridesKey = "styleNameOverrides"
    private static let customStylesKey = "customStyles"
    private static let hiddenBuiltInsKey = "hiddenBuiltInStyles"
    private static let markdownOverridesKey = "styleMarkdownOverrides"

    /// built-in style id → custom system prompt
    private var overrides: [String: String] = [:] {
        didSet { if !isReloading { defaults.set(overrides, forKey: Self.overridesKey) } }
    }

    /// built-in style id → custom display name
    private var nameOverrides: [String: String] = [:] {
        didSet { if !isReloading { defaults.set(nameOverrides, forKey: Self.nameOverridesKey) } }
    }

    /// built-in style id → Markdown switch, where it differs from the built-in's default
    private var markdownOverrides: [String: Bool] = [:] {
        didSet { if !isReloading { defaults.set(markdownOverrides, forKey: Self.markdownOverridesKey) } }
    }

    /// User-added styles, in creation order.
    private var customStyles: [MessageStyle] = [] {
        didSet {
            if !isReloading {
                defaults.set(try? JSONEncoder().encode(customStyles), forKey: Self.customStylesKey)
            }
        }
    }

    /// Built-ins the user deleted; `restoreDeletedDefaults()` brings them back.
    private var hiddenBuiltIns: Set<String> = [] {
        didSet { if !isReloading { defaults.set(Array(hiddenBuiltIns), forKey: Self.hiddenBuiltInsKey) } }
    }

    private let defaults = SyncedDefaults.shared
    /// Set while values are copied in from disk, so the `didSet`s don't echo them back out.
    private var isReloading = false
    private var remoteChangeObserver: NSObjectProtocol?

    private init() {
        reload()
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: SyncedDefaults.didChangeRemotely, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    /// Reads everything from `UserDefaults` — at launch, and again after another device's
    /// changes were copied in.
    private func reload() {
        isReloading = true
        defer { isReloading = false }
        overrides = defaults.dictionary(forKey: Self.overridesKey) as? [String: String] ?? [:]
        nameOverrides = defaults.dictionary(forKey: Self.nameOverridesKey) as? [String: String] ?? [:]
        customStyles = defaults.data(forKey: Self.customStylesKey)
            .flatMap { try? JSONDecoder().decode([MessageStyle].self, from: $0) } ?? []
        hiddenBuiltIns = Set(defaults.stringArray(forKey: Self.hiddenBuiltInsKey) ?? [])
        markdownOverrides = defaults.dictionary(forKey: Self.markdownOverridesKey) as? [String: Bool] ?? [:]
    }

    /// All visible styles in display order: built-ins that weren't deleted (with custom
    /// names/prompts applied), then user-added.
    public var styles: [MessageStyle] {
        let builtIns = Styles.all.filter { !hiddenBuiltIns.contains($0.id) }.map { style in
            MessageStyle(
                id: style.id,
                name: nameOverrides[style.id] ?? style.name,
                systemPrompt: overrides[style.id] ?? style.systemPrompt,
                usesMarkdown: markdownOverrides[style.id] ?? style.usesMarkdown)
        }
        return builtIns + customStyles
    }

    public var canAddStyle: Bool { styles.count < Self.maxStyles }

    public func styleIfPresent(withID id: String) -> MessageStyle? {
        styles.first { $0.id == id }
    }

    /// Falls back to the first visible style (or the app default if none is left), so a
    /// stale id still yields something usable.
    public func style(withID id: String) -> MessageStyle {
        styleIfPresent(withID: id) ?? styles.first ?? Styles.defaultStyle
    }

    /// True for user-added styles: editable name, deletable. Built-ins are neither.
    public func isCustom(_ id: String) -> Bool {
        customStyles.contains { $0.id == id }
    }

    /// True when a built-in's name, prompt or Markdown switch differs from its default.
    public func isCustomized(_ id: String) -> Bool {
        overrides[id] != nil || nameOverrides[id] != nil || markdownOverrides[id] != nil
    }

    // MARK: - Built-in styles

    public func setName(_ name: String, for id: String) {
        guard !isCustom(id) else { return } // custom styles are edited via updateStyle
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Styles.style(withID: id).name {
            nameOverrides[id] = nil
        } else {
            nameOverrides[id] = trimmed
        }
    }

    public func setPrompt(_ prompt: String, for id: String) {
        guard !isCustom(id) else { return } // custom styles are edited via updateStyle
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Styles.style(withID: id).systemPrompt {
            overrides[id] = nil
        } else {
            overrides[id] = trimmed
        }
    }

    /// Built-in or custom: whether the style's results offer the Markdown copy switch.
    public func setUsesMarkdown(_ on: Bool, for id: String) {
        if let index = customStyles.firstIndex(where: { $0.id == id }) {
            let style = customStyles[index]
            customStyles[index] = MessageStyle(id: id, name: style.name, systemPrompt: style.systemPrompt, usesMarkdown: on)
        } else if on == Styles.style(withID: id).usesMarkdown {
            markdownOverrides[id] = nil
        } else {
            markdownOverrides[id] = on
        }
    }

    /// Restores a built-in's default name, prompt and Markdown switch.
    public func resetToDefault(for id: String) {
        overrides[id] = nil
        nameOverrides[id] = nil
        markdownOverrides[id] = nil
    }

    // MARK: - User-added styles

    /// Adds a style if there is room and both fields are non-blank; returns it, else nil.
    @discardableResult
    public func addStyle(name: String, prompt: String, usesMarkdown: Bool = false) -> MessageStyle? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAddStyle, !name.isEmpty, !prompt.isEmpty else { return nil }
        let style = MessageStyle(id: "custom-\(UUID().uuidString)", name: name, systemPrompt: prompt, usesMarkdown: usesMarkdown)
        customStyles.append(style)
        return style
    }

    public func updateStyle(id: String, name: String, prompt: String, usesMarkdown: Bool? = nil) {
        guard let index = customStyles.firstIndex(where: { $0.id == id }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !prompt.isEmpty else { return }
        customStyles[index] = MessageStyle(
            id: id, name: name, systemPrompt: prompt,
            usesMarkdown: usesMarkdown ?? customStyles[index].usesMarkdown)
    }

    // MARK: - Deleting

    /// Any visible style can be deleted except the last one — the rewrite flow needs one.
    public func canDelete(_ id: String) -> Bool {
        styles.count > 1 && styleIfPresent(withID: id) != nil
    }

    public var hasHiddenBuiltIns: Bool { !hiddenBuiltIns.isEmpty }

    /// User-added styles are removed; built-ins are hidden so they can be restored.
    public func removeStyle(id: String) {
        guard canDelete(id) else { return }
        if isCustom(id) {
            customStyles.removeAll { $0.id == id }
        } else {
            hiddenBuiltIns.insert(id)
        }
    }

    /// Brings deleted built-ins back; their name/prompt overrides, if any, still apply.
    public func restoreDeletedDefaults() {
        hiddenBuiltIns = []
    }
}
