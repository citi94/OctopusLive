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

    /// Latest live readings and today's total, shared so the app and widget
    /// reuse each other's fetches instead of each calling the API.
    static var liveCache: TimedValue<[TelemetryReading]>? {
        get { decoded(forKey: "liveCache") }
        set { encode(newValue, forKey: "liveCache") }
    }

    static var todayCache: TimedValue<Double>? {
        get { decoded(forKey: "todayCache") }
        set { encode(newValue, forKey: "todayCache") }
    }

    /// Set when Octopus rate-limits us; nothing calls telemetry until then.
    static var rateLimitedUntil: Date? {
        get { defaults.object(forKey: "rateLimitedUntil") as? Date }
        set { defaults.set(newValue, forKey: "rateLimitedUntil") }
    }

    private static func decoded<T: Decodable>(forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T?, forKey key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
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
        for key in ["apiKey", "accountNumber", "deviceId", "mpan", "meterSerial", "isDemo", "liveCache", "todayCache", "rateLimitedUntil", "lastLiveData"] {
            defaults.removeObject(forKey: key)
        }
        KeychainHelper.deleteAll()
    }
}
