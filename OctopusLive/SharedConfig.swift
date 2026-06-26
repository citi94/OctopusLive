import Foundation

struct SharedConfig {
    static let appGroup = "group.com.octopuslive.shared"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// The Octopus API key — the one true secret. Stored in the (shared) Keychain
    /// rather than the app-group plist, which is plaintext. Legacy installs that
    /// still hold the key in UserDefaults are migrated transparently on first read.
    static var apiKey: String {
        get {
            if let key = KeychainHelper.load(key: "apiKey"), !key.isEmpty {
                return key
            }
            // One-time migration from the old plaintext UserDefaults storage.
            if let legacy = defaults.string(forKey: "apiKey"), !legacy.isEmpty {
                KeychainHelper.save(key: "apiKey", value: legacy)
                defaults.removeObject(forKey: "apiKey")
                return legacy
            }
            return ""
        }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(key: "apiKey")
            } else {
                KeychainHelper.save(key: "apiKey", value: newValue)
            }
            // Never leave a plaintext copy behind.
            defaults.removeObject(forKey: "apiKey")
        }
    }

    static var accountNumber: String {
        get { defaults.string(forKey: "accountNumber") ?? "" }
        set { defaults.set(newValue, forKey: "accountNumber") }
    }

    static var deviceId: String {
        get { defaults.string(forKey: "deviceId") ?? "" }
        set { defaults.set(newValue, forKey: "deviceId") }
    }

    static var mpan: String {
        get { defaults.string(forKey: "mpan") ?? "" }
        set { defaults.set(newValue, forKey: "mpan") }
    }

    static var meterSerial: String {
        get { defaults.string(forKey: "meterSerial") ?? "" }
        set { defaults.set(newValue, forKey: "meterSerial") }
    }

    static var isConfigured: Bool {
        !apiKey.isEmpty && !accountNumber.isEmpty && !deviceId.isEmpty
    }

    static func deleteAll() {
        for key in ["apiKey", "accountNumber", "deviceId", "mpan", "meterSerial"] {
            defaults.removeObject(forKey: key)
        }
        KeychainHelper.deleteAll()
    }
}
