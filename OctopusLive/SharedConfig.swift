import Foundation

struct SharedConfig {
    static let appGroup = "group.com.octopuslive.shared"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var apiKey: String {
        get { defaults.string(forKey: "apiKey") ?? "" }
        set { defaults.set(newValue, forKey: "apiKey") }
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
    }
}
