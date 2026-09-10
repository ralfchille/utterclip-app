import Foundation
import SwiftData
import os
#if canImport(UIKit)
import UIKit
#endif

/// Publishes this device's dictation phase to the synced store (both platforms), and lets
/// the Mac read what the other devices are up to. Together with the synced `Dictation`
/// records this is what makes the Mac window mirror a dictation made on the phone.
@MainActor
public enum ActivitySync {
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "activity-sync")
    private static var store: CloudStore { CloudStore.shared }
    /// Activity older than this is nobody's "current" state any more.
    public static let freshness: TimeInterval = 5 * 60

    /// A snapshot of another device's most recent activity.
    public struct Remote: Equatable {
        public let deviceID: String
        public let deviceName: String
        public let phase: String
        public let dictationID: UUID?
        public let updatedAt: Date

        public var isInProgress: Bool { ["recording", "transcribing", "rewriting"].contains(phase) }

        /// Finished over there, but the dictation record has not reached this device yet.
        @MainActor public var awaitsDictation: Bool {
            guard phase == "done", let id = dictationID else { return false }
            return HistoryStore.shared.entry(id: id) == nil
        }

        /// "Recording on iPhone…", "Transcribing on iPhone…", "Fetching the result from iPhone…".
        public var statusText: String {
            switch phase {
            case "recording": return "Recording on \(deviceName)…"
            case "transcribing": return "Transcribing on \(deviceName)…"
            case "rewriting": return "Rewriting on \(deviceName)…"
            case "done": return "Fetching the result from \(deviceName)…"
            default: return "Working on \(deviceName)…"
            }
        }
    }

    // MARK: - Publishing

    /// Records this device's phase as a new record; a no-op when sync is off. Append-only on
    /// purpose: CloudKit exports of *updates* to one long-lived record silently stalled on the
    /// phone, while inserts always went through. Older records of this device are pruned so
    /// the zone stays small; readers take the newest per device.
    public static func publish(phase: String, dictationID: UUID?) {
        guard store.isSyncing else { return }
        let mine = DeviceIdentity.id
        store.context.insert(DeviceActivity(deviceID: mine, deviceName: DeviceIdentity.kind, phase: phase, dictationID: dictationID))
        prune(mine: mine)
        store.save()
        if phase == "done" { ExportKeepAlive.hold() }
    }

    /// Keeps this device's newest few records and drops the rest (older than a minute).
    private static func prune(mine: String) {
        let descriptor = FetchDescriptor<DeviceActivity>(
            predicate: #Predicate { $0.deviceID == mine },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let own = try? store.context.fetch(descriptor) else { return }
        let cutoff = Date().addingTimeInterval(-60)
        for (index, record) in own.enumerated() where index >= 3 && record.updatedAt < cutoff {
            store.context.delete(record)
        }
    }

    // MARK: - Reading the other devices


    /// The other devices' most recent activity, if it is fresh enough to still be "current"
    /// (`within` seconds; five minutes by default — long enough to cover a slow sync, short
    /// enough that a finished dictation from this morning is History, not the current state).
    public static func latestRemote(within: TimeInterval = freshness) -> Remote? {
        guard store.isSyncing else { return nil }
        let mine = DeviceIdentity.id
        var descriptor = FetchDescriptor<DeviceActivity>(
            predicate: #Predicate { $0.deviceID != mine },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let record = try? store.context.fetch(descriptor).first,
              record.updatedAt > Date().addingTimeInterval(-within) else { return nil }
        return Remote(deviceID: record.deviceID, deviceName: record.deviceName, phase: record.phase,
                      dictationID: record.dictationID, updatedAt: record.updatedAt)
    }

    /// The newest dictation another device finished after `date`, if any.
    public static func latestRemoteDictation(after date: Date) -> HistoryEntry? {
        let mine = DeviceIdentity.id
        return HistoryStore.shared.entries.first { entry in
            guard let origin = entry.originDevice, origin != mine else { return false }
            return entry.date > date
        }
    }

    /// "iPhone" / "iPad" / "Mac" for a device id, from its activity record.
    public static func deviceName(for deviceID: String) -> String? {
        var descriptor = FetchDescriptor<DeviceActivity>(predicate: #Predicate { $0.deviceID == deviceID })
        descriptor.fetchLimit = 1
        return try? store.context.fetch(descriptor).first?.deviceName
    }
}

/// Whether this app's window is on screen — always on iOS; on the Mac the window controller
/// keeps it current. Paces how often the Mac refreshes the synced store.
@MainActor
public enum WindowPresence {
    public static var isVisible = true
}

/// iOS: a dictation is usually followed by locking the phone or switching apps, and a
/// suspended app never gets to run its CloudKit export — the Mac then waits for a result
/// that is still on the phone. A short background task keeps the process alive long enough
/// for Core Data to export the finished dictation and the "done" record. No-op on macOS.
@MainActor
enum ExportKeepAlive {
    #if canImport(UIKit) && !os(watchOS)
    private static var task: UIBackgroundTaskIdentifier = .invalid
    private static var release: Task<Void, Never>?

    static func hold(seconds: TimeInterval = 25) {
        end()
        task = UIApplication.shared.beginBackgroundTask(withName: "utterclip.cloudkit-export") { end() }
        release = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            end()
        }
    }

    private static func end() {
        release?.cancel(); release = nil
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
    #else
    static func hold(seconds: TimeInterval = 25) {}
    #endif
}
