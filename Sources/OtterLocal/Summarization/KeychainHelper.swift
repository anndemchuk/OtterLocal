import Foundation
import Security

/// A tiny wrapper around the macOS Keychain for storing one secret: our LLM
/// API key. The Keychain is macOS's built-in encrypted secret storage -- it's
/// a safer place for an API key than UserDefaults, which just writes a plain
/// text file to disk.
enum KeychainHelper {
    private static let service = "com.otterlocal.llmApiKey"

    static func save(_ value: String) {
        let data = Data(value.utf8)

        // Remove any existing item first so we don't end up with duplicates
        // (the Keychain treats "add when one already exists" as an error).
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data
        SecItemAdd(newItem as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
