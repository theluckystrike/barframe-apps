import Foundation
import Security

/// Stores the Stripe restricted key in the login Keychain (generic password).
/// Sandbox apps get per-container keychain access; no entitlement needed.
public struct KeyStore: Sendable {
    public static let service = "com.michaellip.revpulse.stripe"
    public static let account = "restricted-key"

    public let service: String
    public let account: String

    public init(service: String = Self.service, account: String = Self.account) {
        self.service = service
        self.account = account
    }

    public func save(_ key: String) throws {
        let data = Data(key.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let st = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard st == errSecSuccess else { throw KeyStoreError.osStatus(st) }
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let st = SecItemAdd(query as CFDictionary, nil)
            guard st == errSecSuccess else { throw KeyStoreError.osStatus(st) }
        } else {
            throw KeyStoreError.osStatus(status)
        }
    }

    public func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    public enum KeyStoreError: LocalizedError {
        case osStatus(OSStatus)
        public var errorDescription: String? {
            switch self {
            case .osStatus(let s): return "Keychain error (\(s))"
            }
        }
    }
}
