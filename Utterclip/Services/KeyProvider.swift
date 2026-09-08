import Foundation
import Security

/// Keychain-backed API key storage (plan §5a). The key is entered once via the Settings
/// screen and lives only in the device Keychain — never in the repo, never logged.
/// Swappable by design: user-supplied keys (future work) use this exact same path.
struct KeyProvider {
    static let shared = KeyProvider()

    // Unchanged across the rename so the key saved before it stays readable.
    private let service = "com.babbellabs.voicer"
    // Predates multi-provider support; kept so an already-stored key stays readable.
    private let account = "anthropic-api-key"

    func apiKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var hasKey: Bool { apiKey()?.isEmpty == false }

    /// Which provider the stored key routes to (see `AIProvider.detect`); nil if none or unknown.
    var provider: AIProvider? { apiKey().flatMap(AIProvider.detect) }

    @discardableResult
    func setApiKey(_ key: String) -> Bool {
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
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func deleteApiKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
