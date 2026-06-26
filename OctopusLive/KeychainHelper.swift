import Foundation
import Security

enum KeychainHelper {
    // Shared keychain access group, used by both the app and the widget so they
    // can read the same stored secret. This MUST match the group configured in
    // the "Keychain Sharing" capability for both targets. The capability stores
    // `$(AppIdentifierPrefix)com.octopuslive.shared` in the entitlements, which
    // resolves at runtime to the team-prefixed value below.
    //
    // NOTE: this is NOT the app group (`group.com.octopuslive.shared`) — keychain
    // access groups are a separate, team-prefixed namespace.
    private static let accessGroup = "4U3KPR6DJJ.com.octopuslive.shared"

    /// Base query for an item. When `shared` is true the shared access group is
    /// included so the app and widget see the same item; when false the item
    /// lives in the target's default keychain. We try shared first and fall back
    /// to default so a not-yet-provisioned Keychain Sharing capability (or the
    /// Simulator, which handles access groups differently) never bricks storage.
    private static func baseQuery(key: String, shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        if shared {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        if !save(key: key, data: data, shared: true) {
            _ = save(key: key, data: data, shared: false)
        }
    }

    @discardableResult
    private static func save(key: String, data: Data, shared: Bool) -> Bool {
        // Delete any existing item first, then add fresh.
        SecItemDelete(baseQuery(key: key, shared: shared) as CFDictionary)

        var addQuery = baseQuery(key: key, shared: shared)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func load(key: String) -> String? {
        load(key: key, shared: true) ?? load(key: key, shared: false)
    }

    private static func load(key: String, shared: Bool) -> String? {
        var query = baseQuery(key: key, shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        // Clear both locations so a key never lingers in either.
        SecItemDelete(baseQuery(key: key, shared: true) as CFDictionary)
        SecItemDelete(baseQuery(key: key, shared: false) as CFDictionary)
    }

    static func deleteAll() {
        for key in ["apiKey"] {
            delete(key: key)
        }
    }
}
