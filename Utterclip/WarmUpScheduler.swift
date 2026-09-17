#if os(iOS)
import BackgroundTasks
import UtterclipCore
import os

/// Keeps a warm process around. iOS terminates a suspended app that holds the ~220 MB Whisper
/// model, and CoreML re-specializes it for the Neural Engine on every cold launch — tens of
/// seconds the user waits through. A background refresh task asks iOS to wake the app while
/// the phone is idle: the wake relaunches it (which warms the model in `UtterclipApp.init`)
/// and it is then suspended already warm, so the next open is instant.
///
/// Opportunistic by design: iOS grants these based on how often the app is actually used, and
/// never in Low Power Mode. Missing one costs nothing — the app just warms up on launch as
/// before.
enum WarmUpScheduler {
    static let taskIdentifier = "com.ralfchille.voicer.warm"
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "warm-schedule")

    /// Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task)
        }
    }

    /// Queues the next wake-up. Called when the app goes to the background and again from
    /// every wake, so the chain keeps itself alive.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // The earliest iOS may run it; it usually waits longer and picks its own moment.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.notice("Could not schedule a warm-up wake: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule() // chain the next one first, whatever happens below
        let work = Task { @MainActor in
            let service = TranscriptionService.shared
            service.warmUp() // a no-op when this wake found the process already warm
            // Wait for it, but never past the system's budget.
            let deadline = ContinuousClock.now.advanced(by: .seconds(25))
            while service.state == .cold || service.state == .warming, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(250))
            }
            let ready = service.state == .ready
            logger.notice("Background warm-up finished; model ready: \(ready, privacy: .public)")
            task.setTaskCompleted(success: ready)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
#endif
