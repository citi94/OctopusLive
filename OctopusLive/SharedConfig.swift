import Foundation

struct SharedConfig {
    static let appGroup = "group.com.octopuslive.shared"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // API key stored in Keychain for security
    static var apiKey: String {
        get { KeychainHelper.load(key: "apiKey") ?? "" }
        set { KeychainHelper.save(key: "apiKey", value: newValue) }
    }

    // Non-sensitive config in UserDefaults (shared with widget via App Group)
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
        KeychainHelper.deleteAll()
        defaults.removeObject(forKey: "accountNumber")
        defaults.removeObject(forKey: "deviceId")
        defaults.removeObject(forKey: "mpan")
        defaults.removeObject(forKey: "meterSerial")
    }
}
