import Foundation
import Security

/// Thin wrapper around Keychain Services. API keys are looked up by
/// `ProviderConfig.id` and never touch UserDefaults/JSON — only the fact
/// that a key exists (`ProviderConfig.hasAPIKey`) is persisted alongside
/// the provider.
enum KeychainStore {
    private static let service = "com.ricardobenthem.aiclient.apikey"

    static func save(apiKey: String, for providerID: UUID) {
        let account = providerID.uuidString
        let data = Data(apiKey.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Replace any existing entry for this provider rather than erroring
        // on `errSecDuplicateItem`.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            print("KeychainStore: failed to save API key for \(providerID) (OSStatus \(status))")
        }
    }

    static func apiKey(for providerID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(for providerID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
