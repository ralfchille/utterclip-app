import AppIntents

/// Puts "Start dictating" in the Shortcuts app, in Siri and — the reason it is here — in the
/// list the Action button offers under Shortcut, so the button can be given to Utterclip
/// without anyone having to build a shortcut by hand.
///
/// The button can also be pointed at the Dictate *control* (Action button → Controls), which
/// the widget extension has offered since iOS 18; this is the other half of that, for people
/// who look under Shortcut instead.
@available(iOS 18.0, *)
struct UtterclipShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start dictating with \(.applicationName)",
                "New dictation in \(.applicationName)",
                "Dictate with \(.applicationName)",
            ],
            shortTitle: "Start dictating",
            systemImageName: "mic.fill"
        )
    }
}
