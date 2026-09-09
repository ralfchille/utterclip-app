import Foundation
import os

/// Preferences that follow the user through iCloud: the style edits and the few settings in
/// `StyleStore` and `RecorderViewModel`. `UserDefaults` stays the source every read uses;
/// this wrapper mirrors writes into the iCloud key-value store and copies remote changes
/// back into `UserDefaults`, then tells the stores to reload.
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

    /// Sync is on and this process can reach the key-value store (entitlement + account).
    public private(set) var isActive = false

    private let local = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "settings-sync")

    private init() {
        guard SyncPreference.isEnabled, SyncPreference.hasICloudAccount else { return }
        // No entitlement → the store logs and ignores writes; `synchronize()` then returns
        // false, which is our signal to stay local.
        guard cloud.synchronize() else {
            Self.logger.notice("iCloud key-value store unavailable; settings stay on this device.")
            return
        }
        isActive = true
        reconcileAtLaunch()
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in self?.applyRemoteChange(note) }
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
        guard isActive, Self.syncedKeys.contains(key) else { return }
        if let value {
            cloud.set(value, forKey: key)
        } else {
            cloud.removeObject(forKey: key)
        }
        cloud.synchronize()
    }

    // MARK: - Reconciliation

    /// First launch with sync: the cloud wins where it has a value (another device already
    /// synced), local values fill the gaps and go up.
    private func reconcileAtLaunch() {
        var pulled = 0, pushed = 0
        for key in Self.syncedKeys {
            if let remote = cloud.object(forKey: key) {
                if !Self.equal(remote, local.object(forKey: key)) {
                    local.set(remote, forKey: key); pulled += 1
                }
            } else if let mine = local.object(forKey: key) {
                cloud.set(mine, forKey: key); pushed += 1
            }
        }
        if pushed > 0 { cloud.synchronize() }
        if pulled > 0 {
            Self.logger.notice("Settings reconciled from iCloud: \(pulled, privacy: .public) pulled, \(pushed, privacy: .public) pushed.")
            NotificationCenter.default.post(name: Self.didChangeRemotely, object: nil)
        }
    }

    private func applyRemoteChange(_ note: Notification) {
        let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            Self.logger.error("iCloud key-value store quota exceeded; settings no longer sync.")
            return
        }
        let changed = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? [])
            .filter(Self.syncedKeys.contains)
        guard !changed.isEmpty else { return }
        for key in changed {
            local.set(cloud.object(forKey: key), forKey: key) // nil removes
        }
        NotificationCenter.default.post(name: Self.didChangeRemotely, object: nil)
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as? NSObject)?.isEqual(b) ?? false
        default: return false
        }
    }
}
