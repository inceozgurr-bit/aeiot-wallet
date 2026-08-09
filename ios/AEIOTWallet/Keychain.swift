import Foundation
import Security
import LocalAuthentication

enum Keychain {
    /// Namespace for this app's items, deliberately independent of the bundle
    /// identifier: changing this string orphans every stored seed phrase, so it
    /// stays put even when the bundle ID changes.
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

        // .biometryCurrentSet, not .userPresence: the latter accepts the device
        // passcode, so a thief who watched it being typed could read the
        // recovery phrase outright. This also invalidates the item if a face or
        // fingerprint is enrolled later, which is that same attack via Settings.
        // The trade-off is deliberate — re-enrolling Face ID then means
        // restoring from the 12 words, which self-custody requires anyway.
        if biometryAvailable,
           let acl = SecAccessControlCreateWithFlags(
               nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil) {
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
