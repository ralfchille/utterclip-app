import CoreData
import Foundation
import SwiftData
import os

/// The one SwiftData store CloudKit mirrors into the user's private database. History and the
/// synced settings share it, so both ride on the same container, the same push subscription
/// and the same change notifications. Local-only when sync is off or the account setup fails;
/// in memory as the last resort, so the app still runs.
@MainActor
public final class CloudStore {
    public static let shared = CloudStore()

    /// Posted on the main queue whenever the store changed underneath us (a CloudKit import
    /// landing, or another context saving). Consumers re-read what they care about.
    public static let didChange = Notification.Name("utterclip.cloudStoreDidChange")

    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }
    /// Attached to CloudKit (false when sync is off or the setup fell back to local).
    public let isSyncing: Bool

    private var remoteChangeObserver: NSObjectProtocol?
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "cloud-store")

    private init() {
        let schema = Schema([Dictation.self, SyncedSetting.self, DeviceActivity.self])
        let url = Self.directory().appendingPathComponent("Utterclip.store")
        var made: (ModelContainer, Bool)?
        if SyncPreference.isEnabled {
            let cloud = ModelConfiguration("Utterclip", schema: schema, url: url,
                                           cloudKitDatabase: .private(SyncPreference.containerIdentifier))
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                made = (container, true)
            } else {
                Self.logger.error("CloudKit-backed store unavailable; continuing local-only.")
            }
        }
        if made == nil {
            let local = ModelConfiguration("Utterclip", schema: schema, url: url, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [local]) {
                made = (container, false)
            } else {
                Self.logger.fault("Store on disk unavailable; using an in-memory store.")
                let memory = ModelConfiguration("Utterclip", schema: schema, isStoredInMemoryOnly: true)
                made = (try! ModelContainer(for: schema, configurations: [memory]), false)
            }
        }
        (container, isSyncing) = made!
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in NotificationCenter.default.post(name: CloudStore.didChange, object: nil) }
        }
    }

    public func save() {
        do {
            try context.save()
        } catch {
            Self.logger.error("Store save failed: \(error, privacy: .public)")
        }
    }

    /// Application Support: iOS hands out a per-app container; macOS shares
    /// ~/Library/Application Support, so the files get their own folder there.
    public static func directory() -> URL {
        var support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if os(macOS)
        support.appendPathComponent(Bundle.main.bundleIdentifier ?? "Utterclip")
        #endif
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }
}
