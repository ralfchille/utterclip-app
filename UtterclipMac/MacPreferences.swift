import Foundation
import Observation

/// Mac-only settings that stay on this device: they describe how this Mac behaves, not what
/// the user dictates, so they are deliberately outside the iCloud-synced defaults.
@Observable
@MainActor
final class MacPreferences {
    static let shared = MacPreferences()

    private static let shortcutKey = "globalShortcut"
    private static let openNearFieldKey = "openNearTextField"
    private static let pasteBackKey = "pasteBack"
    private static let expandedKey = "windowExpanded"

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Self.shortcutKey: GlobalHotkey.Shortcut.controlOptionCommandSpace.rawValue,
            Self.openNearFieldKey: true,
            Self.pasteBackKey: true,
        ])
    }

    /// The system-wide dictation shortcut; nil means off.
    var shortcut: GlobalHotkey.Shortcut? {
        get { defaults.string(forKey: Self.shortcutKey).flatMap(GlobalHotkey.Shortcut.init(rawValue:)) }
        set {
            defaults.set(newValue?.rawValue ?? "", forKey: Self.shortcutKey)
            GlobalHotkey.shared.register(newValue)
        }
    }

    /// Open the window beside the text field you are typing in (needs Accessibility access);
    /// otherwise beside the pointer.
    var opensNearTextField: Bool {
        get { defaults.bool(forKey: Self.openNearFieldKey) }
        set { defaults.set(newValue, forKey: Self.openNearFieldKey) }
    }

    /// After a dictation started with the shortcut, hand the text back to the app it came
    /// from with a ⌘V (needs the same Accessibility access).
    var pastesBack: Bool {
        get { defaults.bool(forKey: Self.pasteBackKey) }
        set { defaults.set(newValue, forKey: Self.pasteBackKey) }
    }

    /// The roomier of the two window sizes. Two fixed sizes rather than a remembered one:
    /// the small one to dictate into, the large one to read and edit in.
    var isWindowExpanded: Bool {
        get { defaults.bool(forKey: Self.expandedKey) }
        set { defaults.set(newValue, forKey: Self.expandedKey) }
    }
}
