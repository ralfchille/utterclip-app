import Foundation
import SwiftData
import os

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

    /// Records this device's phase. Cheap and idempotent; a no-op when sync is off.
    public static func publish(phase: String, dictationID: UUID?) {
        guard store.isSyncing else { return }
        let mine = DeviceIdentity.id
        let descriptor = FetchDescriptor<DeviceActivity>(predicate: #Predicate { $0.deviceID == mine })
        let existing = (try? store.context.fetch(descriptor)) ?? []
        let record: DeviceActivity
        if let first = existing.first {
            record = first
            for extra in existing.dropFirst() { store.context.delete(extra) } // imported twice
        } else {
            record = DeviceActivity(deviceID: mine, deviceName: DeviceIdentity.kind)
            store.context.insert(record)
        }
        record.deviceName = DeviceIdentity.kind
        record.phase = phase
        record.dictationID = dictationID
        record.updatedAt = .now
        store.save()
    }

    // MARK: - Reading the other devices

    /// Re-saves this device's record with a new timestamp. A save starts a CloudKit export
    /// cycle, and the mirroring import rides along with it — the quickest way to pull the
    /// other devices' latest records when no push has arrived.
    public static func touch() {
        guard store.isSyncing else { return }
        let mine = DeviceIdentity.id
        let descriptor = FetchDescriptor<DeviceActivity>(predicate: #Predicate { $0.deviceID == mine })
        if let record = try? store.context.fetch(descriptor).first {
            record.updatedAt = .now
        } else {
            store.context.insert(DeviceActivity(deviceID: mine, deviceName: DeviceIdentity.kind))
        }
        store.save()
    }

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
/// keeps it current. A dictation mirrored from another device is copied to the clipboard only
/// while the window is visible; otherwise it waits for the next show.
@MainActor
public enum WindowPresence {
    public static var isVisible = true
    /// A mirrored result arrived while the window was hidden and has not been shown yet.
    public static var hasUnseenMirroredResult = false
}
