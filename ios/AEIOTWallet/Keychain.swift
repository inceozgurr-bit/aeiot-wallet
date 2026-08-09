import Foundation
import Security
import LocalAuthentication

enum Keychain {
    private static let service = "com.aeiot.wallet"

    /// Saves a value. When `requireBiometry` is true the item can only be read
    /// after a fresh biometric/passcode check (used for the seed phrase).
    /// Returns false if the write failed, so callers never assume a lost secret was stored.
    @discardableResult
    static func save(_ value: String, key: String, requireBiometry: Bool = false) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = Data(value.utf8)

        #if targetEnvironment(simulator)
        let biometryAvailable = false
        #else
        let biometryAvailable = requireBiometry
        #endif

        if biometryAvailable,
           let acl = SecAccessControlCreateWithFlags(
               nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil) {
            attrs[kSecAttrAccessControl as String] = acl
        } else {
            attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func load(key: String, prompt: String? = nil) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        query[kSecReturnData as String] = true
        if let prompt {
            let context = LAContext()
            context.localizedReason = prompt
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
