import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// Puts the finished dictation into the app you started it from: the shortcut remembers which
/// app was in front, and once the text is on the clipboard that app is brought back and sent
/// ⌘V. The round trip is what makes dictating into someone else's text field feel direct
/// rather than "switch, dictate, switch back, paste".
///
/// Only ever armed by the global shortcut — opening the window from the menu bar has no
/// target to return to — and only with Accessibility access, which posting a key needs.
@MainActor
final class PasteBack {
    static let shared = PasteBack()

    private var target: NSRunningApplication?
    private var armedAt: Date?
    /// A dictation that never finished should not paste into whatever you are doing an hour
    /// later.
    private static let validity: TimeInterval = 5 * 60
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "paste-back")

    private init() {}

    /// Remembers the app in front, before Utterclip takes focus.
    func arm() {
        disarm()
        guard MacPreferences.shared.pastesBack, FocusedField.isAllowed else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        target = front
        armedAt = .now
    }

    func disarm() {
        target = nil
        armedAt = nil
    }

    /// The dictation settled and its text is on the clipboard: hand it back.
    func deliver() {
        guard let target, let armedAt, Date().timeIntervalSince(armedAt) < Self.validity,
              AXIsProcessTrusted() else {
            disarm()
            return
        }
        disarm()
        Self.logger.notice("Pasting into \(target.localizedName ?? "the previous app", privacy: .public).")
        AppDelegate.shared?.hideWindowForPasteBack()
        target.activate()
        Task { @MainActor in
            // The other app needs a moment to become key before it can receive the keystroke.
            try? await Task.sleep(for: .milliseconds(180))
            Self.sendPaste()
        }
    }

    private static func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
