#if os(iOS)
import AppIntents
import Foundation

/// Opens Utterclip straight into a recording. Behind the Control Center / Lock Screen /
/// Action button control, and behind the "Start dictating" shortcut.
///
/// Compiled into both the app and the widget extension: the control needs it, and so does the
/// app, whose `AppShortcutsProvider` is what offers it to Shortcuts, Siri and the Action
/// button's shortcut list.
///
/// iOS 18 and up, which is what controls need anyway. The app itself still runs on 17, just
/// without this.
@available(iOS 18.0, *)
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start dictating"
    static let description = IntentDescription("Opens Utterclip and starts recording.")
    static let openAppWhenRun = true

    /// `openAppWhenRun` brings the app up and this then runs in it, so asking the view
    /// directly is enough. It used to hand back an `OpenURLIntent` for `utterclip://record`
    /// instead, which iOS refuses — custom schemes are not allowed there — and the refusal
    /// arrived as a notification banner even though the recording had already started.
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            PendingDictation.isRequested = true
            NotificationCenter.default.post(name: .utterclipStartRecording, object: nil)
        }
        return .result()
    }
}

/// On a cold launch the intent can run before the view is listening, and a notification posted
/// then lands nowhere. The view reads this as it appears and starts the recording itself.
@MainActor
enum PendingDictation {
    static var isRequested = false

    /// True once, for whoever asks first.
    static func take() -> Bool {
        defer { isRequested = false }
        return isRequested
    }
}
#endif
