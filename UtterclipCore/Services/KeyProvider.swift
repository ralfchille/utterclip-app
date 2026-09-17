import Foundation
import Security
import os

/// Keychain-backed API key storage (plan §5a). The key is entered once in Settings and
/// lives only in the Keychain — never in the repo, never logged.
///
/// Since 1.1 the item sits in a keychain access group both apps declare and is marked
/// synchronizable, so iCloud Keychain carries it to the user's other devices (end-to-end
/// encrypted by Apple). A build without the group entitlement (unsigned local build) or with
/// sync turned off keeps the key per device, exactly as 1.0 did. The 1.0 item is migrated
/// silently on first use.
public struct KeyProvider {
    public static let shared = KeyProvider()

    // Unchanged across the rename so the key saved before it stays readable.
    private let service = "com.babbellabs.voicer"
    // Predates multi-provider support; kept so an already-stored key stays readable.
    private let account = "anthropic-api-key"

    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "keychain")

    // MARK: - Public API

    public func apiKey() -> String? {
        Self.migrateOnce(self)
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public var hasKey: Bool { apiKey()?.isEmpty == false }

    /// Which provider the stored key routes to (see `AIProvider.detect`); nil if none or unknown.
    public var provider: AIProvider? { apiKey().flatMap(AIProvider.detect) }

    /// Stores the key, replacing any existing item. Synchronizable cannot be changed on an
    /// existing item, so a write is always delete-then-add with the current sync setting.
    @discardableResult
    public func setApiKey(_ key: String) -> Bool {
        Self.migrateOnce(self)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteApiKey()
            return true
        }
        SecItemDelete(itemQuery as CFDictionary)
        var item = itemQuery
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrSynchronizable as String] = Self.syncs
        // Synchronizable items cannot be "this device only" — that is the whole point.
        item[kSecAttrAccessible as String] = Self.syncs
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            Self.logger.error("Keychain add failed: \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    public func deleteApiKey() {
        Self.migrateOnce(self)
        SecItemDelete(itemQuery as CFDictionary)
    }

    /// Where the key lives: on this device only, or in iCloud Keychain.
    public var isSynchronized: Bool { Self.syncs && storedItemIsSynchronizable() == true }

    /// The sync switch changed: re-store the key with the matching synchronizable flag now,
    /// rather than at the next launch (history and settings wait for the relaunch; the
    /// key does not have to).
    public func applySyncPreference() {
        Self.migrateOnce(self)
        alignSyncFlagWithPreference()
    }

    /// Re-stores the key when its synchronizable flag disagrees with what the *user* chose.
    /// Sync is only ever switched off here because the preference is off — never because a
    /// capability probe failed, since re-storing without sync deletes the synced copy
    /// everywhere. Switching it on waits for a usable shared group.
    private func alignSyncFlagWithPreference() {
        guard let current = readValue(itemQuery), let synced = storedItemIsSynchronizable() else { return }
        if synced && !SyncPreference.isEnabled {
            Self.logger.notice("Re-storing the API key with sync off (user preference).")
            setApiKeyWithoutMigration(current)
        } else if !synced && Self.syncs {
            Self.logger.notice("Re-storing the API key with sync on.")
            setApiKeyWithoutMigration(current)
        }
    }

    // MARK: - Queries

    /// The item's home: our service/account in the shared access group (when usable), matching
    /// both the synchronizable and the local variant so reads and deletes see either.
    private var itemQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        if let group = Self.usableSharedGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        #if os(macOS)
        if Self.usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        #endif
        return query
    }

    /// Whether the stored item (if any) is marked synchronizable.
    private func storedItemIsSynchronizable() -> Bool? {
        var query = itemQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any] else { return nil }
        return (attributes[kSecAttrSynchronizable as String] as? Bool)
            ?? ((attributes[kSecAttrSynchronizable as String] as? Int).map { $0 != 0 })
    }

    // MARK: - Capabilities, probed once

    /// Sync the key through iCloud Keychain: the user wants it, and this build can (shared
    /// access group entitlement present and, on macOS, the data-protection keychain).
    private static var syncs: Bool { SyncPreference.isEnabled && usableSharedGroup != nil }

    /// The shared group from the Info.plist prefix, or nil for builds without a team prefix.
    private static let sharedGroupName: String? = {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "UtterclipAppIdentifierPrefix") as? String,
              !prefix.isEmpty, !prefix.hasPrefix("$(") else { return nil }
        return prefix + "com.ralfchille.voicer.shared"
    }()

    /// `<TeamID>.com.ralfchille.voicer.shared` when this build may use it; nil where the
    /// keychain refuses the group (no `keychain-access-groups` entitlement) — then the key
    /// stays per app. Probed with a throwaway write. A *transient* failure — the keychain is
    /// locked right after launch, `errSecInteractionNotAllowed` — is not a verdict: the group
    /// is assumed usable and the probe repeats next time. Only definitive answers are cached.
    /// (Before 1.1 build 4 a locked keychain was read as "no group", and the key was then
    /// re-stored per device, which deleted the synced copy on every other device.)
    private static var usableSharedGroup: String? {
        groupLock.lock(); defer { groupLock.unlock() }
        if let decided = groupDecision { return decided }
        let (group, definitive) = probeSharedGroup()
        if definitive { groupDecision = .some(group) }
        return group
    }

    private static let groupLock = NSLock()
    /// `.none` = not decided yet; `.some(nil)` = no usable group; `.some(group)` = usable.
    private static var groupDecision: String?? = nil

    private static func probeSharedGroup() -> (group: String?, definitive: Bool) {
        guard let group = sharedGroupName else { return (nil, true) }
        var probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ralfchille.utterclip.keychain-probe",
            kSecAttrAccount as String: "group-probe",
            kSecAttrAccessGroup as String: group,
            // Writable while the screen is locked (after the first unlock since boot).
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        #if os(macOS)
        guard usesDataProtectionKeychain else { return (nil, true) } // groups need the modern keychain
        probe[kSecUseDataProtectionKeychain as String] = true
        #endif
        SecItemDelete(probe as CFDictionary)
        probe[kSecValueData as String] = Data("probe".utf8)
        let status = SecItemAdd(probe as CFDictionary, nil)
        probe.removeValue(forKey: kSecValueData as String)
        SecItemDelete(probe as CFDictionary)
        switch status {
        case errSecSuccess:
            return (group, true)
        case errSecMissingEntitlement, errSecNoAccessForItem, errSecParam:
            logger.notice("Shared keychain group unavailable (\(status, privacy: .public)); key stays per device.")
            return (nil, true)
        default:
            logger.notice("Shared keychain group probe inconclusive (\(status, privacy: .public)); assuming it works, will retry.")
            return (group, false)
        }
    }

    #if os(macOS)
    /// The data-protection keychain is only open to processes with an application identifier
    /// (builds signed with a provisioning profile). Others get `errSecMissingEntitlement` from
    /// every write and fall back to the login keychain — which works, minus sync.
    static let usesDataProtectionKeychain: Bool = {
        var probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ralfchille.utterclip.keychain-probe",
            kSecAttrAccount as String: "probe",
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(probe as CFDictionary)
        probe[kSecValueData as String] = Data("probe".utf8)
        let status = SecItemAdd(probe as CFDictionary, nil)
        probe.removeValue(forKey: kSecValueData as String)
        SecItemDelete(probe as CFDictionary)
        if status == errSecMissingEntitlement {
            logger.notice("No application identifier: API key goes to the login keychain.")
            return false
        }
        return true
    }()
    #endif

    // MARK: - Migration from 1.0 (and between sync on/off)

    private static let migrationLock = NSLock()
    private static var migrated = false

    /// Once per launch: bring the key from wherever 1.0 left it (per-app group, this device
    /// only; on macOS possibly the login keychain) into the shared group, and make its
    /// synchronizable flag match the sync setting. Idempotent; nothing to do on a fresh install.
    private static func migrateOnce(_ provider: KeyProvider) {
        migrationLock.lock(); defer { migrationLock.unlock() }
        guard !migrated else { return }
        migrated = true
        provider.migrate()
    }

    private func migrate() {
        // 1. Already in the target location? Then only the sync flag may need adjusting.
        if readValue(itemQuery) != nil {
            alignSyncFlagWithPreference()
            return
        }
        // 2. Look where 1.0 kept it and move it over.
        for legacy in legacyQueries() {
            if let value = readValue(legacy) {
                Self.logger.notice("Migrating the API key into the shared keychain group.")
                if setApiKeyWithoutMigration(value) {
                    SecItemDelete(legacy as CFDictionary)
                }
                return
            }
        }
    }

    /// The 1.0 locations: same service/account, per-app access group (no group attribute),
    /// not synchronizable; on macOS both keychains, the login one for ad-hoc-signed builds.
    private func legacyQueries() -> [[String: Any]] {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        #if os(macOS)
        var dataProtection = base
        dataProtection[kSecUseDataProtectionKeychain as String] = true
        return Self.usesDataProtectionKeychain ? [dataProtection, base] : [base]
        #else
        return [base]
        #endif
    }

    private func readValue(_ query: [String: Any]) -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func setApiKeyWithoutMigration(_ key: String) -> Bool {
        SecItemDelete(itemQuery as CFDictionary)
        var item = itemQuery
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrSynchronizable as String] = Self.syncs
        item[kSecAttrAccessible as String] = Self.syncs
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            Self.logger.error("Keychain add during migration failed: \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }
}
