import SwiftUI
import UtterclipCore

/// The Mac app: the same `ContentView` as the iPhone app in one compact window that
/// floats above other apps, so it can sit next to whatever you are writing in.
@main
struct UtterclipMacApp: App {
    /// Window level preference; on by default because the whole point of the Mac
    /// version is to dictate into another app without hunting for this window.
    @AppStorage("floatOnTop") private var floatOnTop = true

    init() {
        // Always-warm, exactly like the iPhone app: load Whisper once at launch.
        TranscriptionService.shared.warmUp()
    }

    /// Debug builds answer `utterclip://snapshot` with a PNG of the window (see `DebugSnapshot`).
    private var root: some View {
        #if DEBUG
        ContentView().debugSnapshot()
        #else
        ContentView()
        #endif
    }

    var body: some Scene {
        // A single window (no File ▸ New): closing it and clicking the Dock icon brings
        // the same one back.
        Window("Utterclip", id: "main") {
            root
                .frame(minWidth: 380, minHeight: 600)
                .background(WindowConfigurator(floatOnTop: floatOnTop))
        }
        .defaultSize(width: 420, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu("Dictation") {
                Button("Start / Stop Dictation") {
                    NotificationCenter.default.post(name: .utterclipToggleRecording, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Continue Dictating") {
                    NotificationCenter.default.post(name: .utterclipContinueRecording, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("History…") {
                    NotificationCenter.default.post(name: .utterclipShowHistory, object: nil)
                }
                .keyboardShortcut("y", modifiers: .command)
            }

            // Standard ⌘, opens the same Settings sheet the iPhone app has.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .utterclipShowSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .windowArrangement) {
                Toggle("Float on Top", isOn: $floatOnTop)
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }
    }
}
