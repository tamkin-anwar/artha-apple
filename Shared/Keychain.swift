import Foundation
import Security

/// The device's Artha sign-in token lives in the Keychain, never in
/// UserDefaults. ThisDeviceOnly keeps it out of backups and off other
/// devices: every device signs in for itself. It's saved to a Keychain
/// group shared with Artha's widgets (ArthaKeychainGroup in Info.plist) so
/// they can fetch fresh numbers on their own, and readable after the first
/// unlock since boot so a Lock Screen widget or an Apple Pay automation can
/// use it while the phone is locked.
nonisolated enum Keychain {
    private static let service = "studio.anwarcreative.artha"
    static let tokenAccount = "api-token"

    /// "TEAMID.studio.anwarcreative.artha.shared", filled in at build time.
    private static var sharedGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "ArthaKeychainGroup") as? String,
              !group.isEmpty, !group.hasPrefix("$(") else { return nil }
        return group
    }

    /// On a Mac, the same modern Keychain iPhone uses (with the same
    /// access rules), rather than the older file-based one a Mac uses by
    /// default. Builds without a signing identity can't use it, so those
    /// fall back to the older one.
    private static func modern(_ query: [String: Any]) -> [String: Any] {
        #if os(macOS)
        var query = query
        query[kSecUseDataProtectionKeychain as String] = true
        return query
        #else
        return query
        #endif
    }

    static func save(_ value: String, account: String) {
        delete(account: account)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        #if os(macOS)
        if SecItemAdd(modern(query) as CFDictionary, nil) == errSecSuccess { return }
        #endif
        if let group = sharedGroup {
            query[kSecAttrAccessGroup as String] = group
            if SecItemAdd(query as CFDictionary, nil) == errSecSuccess { return }
            // Without the shared-group entitlement (some simulator setups),
            // keep the token in the app's own group rather than losing it.
            query.removeValue(forKey: kSecAttrAccessGroup as String)
        }
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Searches every group this app or widget can read, so a token saved
    /// before the shared group existed is still found.
    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        #if os(macOS)
        if SecItemCopyMatching(modern(query) as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        #endif
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the token from every group this app can reach.
    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        SecItemDelete(modern(query) as CFDictionary)
        #endif
        SecItemDelete(query as CFDictionary)
    }

    /// Moves a token saved before the shared group existed into it, so the
    /// widgets can see it. Cheap enough to run on every launch.
    static func migrateToSharedGroup(account: String) {
        guard let token = read(account: account) else { return }
        save(token, account: account)
    }
}
