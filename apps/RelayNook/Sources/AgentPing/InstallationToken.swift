import Foundation
import Security

/// Keep the 128-bit installation credential in sandboxed preferences.
enum InstallationToken {
    static let key = "eventToken"
    static func load() throws -> String {
        if let value = UserDefaults.standard.string(forKey: key), value.count == 32,
           value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) { return value }
        return try regenerate()
    }
    static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    static func regenerate() throws -> String {
        let value = try randomValue()
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.synchronize()
        return value
    }
}
