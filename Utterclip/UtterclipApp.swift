import SwiftUI
import UtterclipCore
import WidgetKit

@main
struct UtterclipApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Always-warm: load Whisper once at launch and keep it resident (plan Phase 3).
        TranscriptionService.shared.warmUp()
        // Ask iOS to wake us occasionally so the model is already loaded when the app is
        // opened; registration has to happen before launch finishes.
        WarmUpScheduler.register()
        // Widgets never refresh on their own (static timeline); make sure a new build's
        // artwork reaches already-placed widgets.
        WidgetCenter.shared.reloadAllTimelines()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Queue the next wake-up whenever the app leaves the foreground.
            if phase == .background { WarmUpScheduler.schedule() }
        }
    }
}
