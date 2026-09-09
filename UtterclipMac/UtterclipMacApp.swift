import SwiftUI
import UtterclipCore

/// The Mac app lives in the menu bar (`LSUIElement`, no Dock tile): a status item opens
/// one compact window with the same `ContentView` as the iPhone app; closing that window
/// only hides it. `AppDelegate` owns the status item and the window.
@main
struct UtterclipMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Always-warm, exactly like the iPhone app: load Whisper once at launch.
        TranscriptionService.shared.warmUp()
    }

    var body: some Scene {
        // An agent app needs a scene but not a visible one; the window is AppKit-managed so
        // it can survive "close" (see MainWindowController). ⌘, is re-routed below.
        Settings { EmptyView() }
            .commands {
                // Key equivalents while the window is key; the status-bar menu lists the same.
                CommandMenu("Dictation") {
                    Button("Start / Stop Dictation") { AppCommand.toggleRecording.perform() }
                        .keyboardShortcut("r", modifiers: .command)
                    Button("Continue Dictating") { AppCommand.continueRecording.perform() }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                    Divider()
                    Button("History…") { AppCommand.showHistory.perform() }
                        .keyboardShortcut("y", modifiers: .command)
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { AppCommand.showSettings.perform() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

/// Everything a menu item, shortcut or URL can ask the app to do. Each command brings the
/// window forward (a hidden window is where the action would otherwise happen unseen) and
/// posts the notification `ContentView` listens for.
enum AppCommand {
    case toggleRecording, startRecording, continueRecording, showHistory, showSettings

    @MainActor
    func perform() {
        AppDelegate.shared?.showWindow()
        let name: Notification.Name = switch self {
        case .toggleRecording: .utterclipToggleRecording
        case .startRecording: .utterclipStartRecording
        case .continueRecording: .utterclipContinueRecording
        case .showHistory: .utterclipShowHistory
        case .showSettings: .utterclipShowSettings
        }
        NotificationCenter.default.post(name: name, object: nil)
    }
}
