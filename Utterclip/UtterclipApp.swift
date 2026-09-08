import SwiftUI

@main
struct UtterclipApp: App {
    init() {
        // Always-warm: load Whisper once at launch and keep it resident (plan Phase 3).
        TranscriptionService.shared.warmUp()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
