import SwiftUI
import WidgetKit

@main
struct UtterclipApp: App {
    init() {
        // Always-warm: load Whisper once at launch and keep it resident (plan Phase 3).
        TranscriptionService.shared.warmUp()
        // Widgets never refresh on their own (static timeline); make sure a new build's
        // artwork reaches already-placed widgets.
        WidgetCenter.shared.reloadAllTimelines()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
