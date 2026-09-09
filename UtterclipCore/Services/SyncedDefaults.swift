import Foundation
import SwiftData
import os

/// Preferences that follow the user: the style edits and the few settings in `StyleStore`
/// and `RecorderViewModel`. `UserDefaults` stays the source every read uses; this wrapper
/// mirrors writes into `SyncedSetting` records in the CloudKit-backed store and copies
/// remote changes back into `UserDefaults`, then tells the stores to reload.
///
/// Why CloudKit rather than the iCloud key-value store: the key-value store rides on iCloud
/// Drive, which a managed Mac can have switched off by policy; CloudKit does not.
///
/// Not synced on purpose: the on-device-model toggle (a per-device capability), the Mac's
/// window preferences, and the sync switch itself.
@MainActor
public final class SyncedDefaults {
    public static let shared = SyncedDefaults()

    /// Posted on the main queue after remote values were copied into `UserDefaults`.
    public static let didChangeRemotely = Notification.Name("utterclip.syncedDefaultsDidChangeRemotely")

    /// Everything that travels. Key names are the 1.0 `UserDefaults` names, unchanged.
    public static let syncedKeys: Set<String> = [
        "stylePromptOverrides", "styleNameOverrides", "customStyles", "hiddenBuiltInStyles",
        "defaultStyleID", "copyAsMarkdown", "redactPersonalData",
    ]

    /// Sync is on and the store is attached to CloudKit.
    public var isActive: Bool { store.isSyncing }

    private let local = UserDefaults.standard
    private let store = CloudStore.shared
    private var observer: NSObjectProtocol?
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "settings-sync")

    private init() {
        reconcile(postIfChanged: false)
        observer = NotificationCenter.default.addObserver(
            forName: CloudStore.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile(postIfChanged: true) }
        }
    }

    // MARK: - Reads and writes (the stores use these instead of UserDefaults directly)

    public func object(forKey key: String) -> Any? { local.object(forKey: key) }
    public func string(forKey key: String) -> String? { local.string(forKey: key) }
    public func bool(forKey key: String) -> Bool { local.bool(forKey: key) }
    public func data(forKey key: String) -> Data? { local.data(forKey: key) }
    public func dictionary(forKey key: String) -> [String: Any]? { local.dictionary(forKey: key) }
    public func stringArray(forKey key: String) -> [String]? { local.stringArray(forKey: key) }

    public func set(_ value: Any?, forKey key: String) {
        local.set(value, forKey: key)
        guard Self.syncedKeys.contains(key) else { return }
        let encoded = Self.encode(value)
        if let record = records()[key] {
            guard record.value != encoded else { return }
            record.value = encoded
            record.updatedAt = .now
        } else {
            store.context.insert(SyncedSetting(key: key, value: encoded))
        }
        store.save()
    }

    // MARK: - Reconciliation

    /// Brings `UserDefaults` and the store in step. A record wins over the local value (it is
    /// what the other devices agreed on); keys with no record yet are seeded from local so the
    /// other devices get them. Duplicated records for one key (both devices created it before
    /// their first sync) collapse to the newest.
    private func reconcile(postIfChanged: Bool) {
        let all = records()
        var changed = false
        var seeded = false
        for key in Self.syncedKeys {
            if let record = all[key] {
                let remote = Self.decode(record.value)
                if !Self.equal(remote, local.object(forKey: key)) {
                    local.set(remote, forKey: key)
                    changed = true
                }
            } else if let mine = local.object(forKey: key) {
                store.context.insert(SyncedSetting(key: key, value: Self.encode(mine)))
                seeded = true
            }
        }
        if seeded { store.save() }
        if changed && postIfChanged {
            NotificationCenter.default.post(name: Self.didChangeRemotely, object: nil)
        }
    }

    /// The current record per key, newest first; older duplicates are deleted on the way.
    private func records() -> [String: SyncedSetting] {
        let descriptor = FetchDescriptor<SyncedSetting>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let fetched = try? store.context.fetch(descriptor) else { return [:] }
        var byKey: [String: SyncedSetting] = [:]
        var pruned = false
        for record in fetched {
            if byKey[record.key] == nil {
                byKey[record.key] = record
            } else {
                store.context.delete(record)
                pruned = true
            }
        }
        if pruned { store.save() }
        return byKey
    }

    // MARK: - Encoding

    private static func encode(_ value: Any?) -> Data? {
        guard let value else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: ["v": value], format: .binary, options: 0)
    }

    private static func decode(_ data: Data?) -> Any? {
        guard let data,
              let wrapped = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return wrapped["v"]
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as? NSObject)?.isEqual(b) ?? false
        default: return false
        }
    }
}
