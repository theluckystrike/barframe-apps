import Foundation
import Security

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public init(status: OSStatus) { self.status = status }
    public var errorDescription: String? {
        switch status {
        case errSecInteractionNotAllowed: return "Unlock your login keychain and try again."
        case errSecAuthFailed, errSecUserCanceled: return "Keychain access was not authorized. Try saving the key again."
        case errSecMissingEntitlement: return "This build cannot access the requested keychain (\(status))."
        default: return "Keychain access failed (\(status)). Try again after unlocking your login keychain."
        }
    }
}
public protocol CredentialStore: Sendable {
    func read(_ account: String) throws -> String?
    func save(_ value: String, account: String) throws
    func delete(_ account: String) throws
}

public struct KeyStore: CredentialStore {
    private let service: String
    public init(service: String = (Bundle.main.bundleIdentifier ?? "com.unfinalized.costbar") + ".credentials") { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
    public func read(_ account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw SpendError.invalidKey }
        return key
    }
    public func save(_ value: String, account: String) throws {
        let key = try ProviderClient.normalizedKey(value)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query(account).merging(attributes) { _, new in new }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    public func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public struct Preferences: Codable, Sendable {
    public var selected: Provider = .openRouter
    public var budgets: [String: Budget] = [:]
    public var alertsEnabled = false
    public var deliveredAlertIDs: [String] = []
    public init() {}
    public func budget(for provider: Provider) -> Budget { budgets[provider.rawValue] ?? Budget() }
}

/// Only non-secret settings and normalized totals are persisted in the app container.
public final class LocalStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func preferences() -> Preferences {
        guard let data = defaults.data(forKey: "preferences.v1"), let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return prefs
    }
    public func save(_ prefs: Preferences) throws { defaults.set(try JSONEncoder().encode(prefs), forKey: "preferences.v1") }
    public func snapshot(for provider: Provider) -> SpendSnapshot? {
        guard let data = defaults.data(forKey: "snapshot.\(provider.rawValue)"), let snapshot = try? JSONDecoder().decode(SpendSnapshot.self, from: data), snapshot.provider == provider else { return nil }
        return snapshot
    }
    public func save(_ snapshot: SpendSnapshot) throws { defaults.set(try JSONEncoder().encode(snapshot), forKey: "snapshot.\(snapshot.provider.rawValue)") }
    public func removeSnapshot(for provider: Provider) { defaults.removeObject(forKey: "snapshot.\(provider.rawValue)") }
}

/// Keychain authorization can block; never run it on the UI executor.
public struct AsyncKeyStore: Sendable {
    private let store: any CredentialStore
    public init(store: any CredentialStore = KeyStore()) { self.store = store }
    public func read(_ account: String) async throws -> String? {
        try await Task.detached { [store] in try store.read(account) }.value
    }
    public func save(_ value: String, account: String) async throws {
        try await Task.detached { [store] in try store.save(value, account: account) }.value
    }
    public func delete(_ account: String) async throws {
        try await Task.detached { [store] in try store.delete(account) }.value
    }
}
