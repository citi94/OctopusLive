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

    /// Set while the app is in demo mode so the widget can show sample data too
    /// (App Review exercises the widget without an Octopus account).
    static var isDemo: Bool {
        get { defaults.bool(forKey: "isDemo") }
        set { defaults.set(newValue, forKey: "isDemo") }
    }

    /// Last successful widget fetch, shown (with its timestamp) when a background
    /// refresh fails, instead of blanking the widget on a flaky connection.
    static var lastLiveData: LiveData? {
        get {
            guard let data = defaults.data(forKey: "lastLiveData") else { return nil }
            return try? JSONDecoder().decode(LiveData.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "lastLiveData")
            } else {
                defaults.removeObject(forKey: "lastLiveData")
            }
        }
    }

    static var isConfigured: Bool {
        !apiKey.isEmpty && !accountNumber.isEmpty && !deviceId.isEmpty
    }

    /// Keychain items survive app deletion but UserDefaults don't, so a reinstall
    /// would otherwise resurrect the old API key. On the first launch of a fresh
    /// install, drop any orphaned keychain item. An existing setup (account number
    /// still present) means this is an upgrade, not a reinstall, so keep it.
    /// Call from the app only — the widget can run before the app's first launch.
    static func clearOrphanedKeychainOnFreshInstall() {
        let flag = "hasLaunched"
        guard !defaults.bool(forKey: flag) else { return }
        if accountNumber.isEmpty {
            KeychainHelper.deleteAll()
        }
        defaults.set(true, forKey: flag)
    }

    static func deleteAll() {
        for key in ["apiKey", "accountNumber", "deviceId", "mpan", "meterSerial", "isDemo", "lastLiveData"] {
            defaults.removeObject(forKey: key)
        }
        KeychainHelper.deleteAll()
    }
}
