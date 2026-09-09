import Foundation
import Security
import os

/// Keychain-backed API key storage (plan §5a). The key is entered once via the Settings
/// screen and lives only in the device Keychain — never in the repo, never logged.
/// Swappable by design: user-supplied keys (future work) use this exact same path.
public struct KeyProvider {
    public static let shared = KeyProvider()

    // Unchanged across the rename so the key saved before it stays readable.
    private let service = "com.babbellabs.voicer"
    // Predates multi-provider support; kept so an already-stored key stays readable.
    private let account = "anthropic-api-key"

    public func apiKey() -> String? {
        var query = baseQuery
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

    @discardableResult
    public func setApiKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteApiKey()
            return true
        }
        let data = Data(trimmed.utf8)

        var query = baseQuery
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            if added != errSecSuccess { Self.logger.error("Keychain add failed: \(added, privacy: .public)") }
            return added == errSecSuccess
        }
        if status != errSecSuccess { Self.logger.error("Keychain update failed: \(status, privacy: .public)") }
        return status == errSecSuccess
    }

    public func deleteApiKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        // Prefer the iOS-style data-protection keychain: no access prompts, per-app
        // isolation. iOS only has that one; macOS also has the legacy login keychain.
        if Self.usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        #endif
        return query
    }

    #if os(macOS)
    /// The data-protection keychain is only open to processes with an application
    /// identifier, i.e. builds signed with a team and a provisioning profile (App Store,
    /// Developer ID, TestFlight). A locally built or ad-hoc-signed copy gets
    /// `errSecMissingEntitlement` from every call, so it falls back to the login keychain —
    /// which works, at the price of a one-time "allow access" prompt after each rebuild.
    /// Probed once per launch with a throwaway write (reads can succeed where writes are
    /// refused), which is removed again immediately.
    private static let usesDataProtectionKeychain: Bool = {
        var probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ralfchille.utterclip.keychain-probe",
            kSecAttrAccount as String: "probe",
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(probe as CFDictionary) // a leftover from a crashed launch
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

    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "keychain")
}
