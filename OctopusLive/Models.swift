import Foundation

// MARK: - GraphQL Response Types

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    let message: String
}

// MARK: - Token

struct TokenResponse: Decodable {
    let obtainKrakenToken: TokenData
}

struct TokenData: Decodable {
    let token: String
}

// MARK: - Account Discovery

struct AccountResponse: Decodable {
    let account: AccountData?
}

struct AccountData: Decodable {
    let electricityAgreements: [ElectricityAgreement]?
}

struct ElectricityAgreement: Decodable {
    let meterPoint: MeterPoint?
}

struct MeterPoint: Decodable {
    let mpan: String?
    let meters: [Meter]?
}

struct Meter: Decodable {
    let serialNumber: String?
    let smartDevices: [SmartDevice]?
}

struct SmartDevice: Decodable {
    let deviceId: String?
}

// MARK: - Telemetry

struct CombinedTelemetryResponse: Decodable {
    let live: [TelemetryReading]?
    let today: [TelemetryReading]?
    let chart: [TelemetryReading]?
}

struct TelemetryResponse: Decodable {
    let smartMeterTelemetry: [TelemetryReading]?
}

struct TelemetryReading: Decodable, Identifiable {
    let readAt: String
    let consumptionDelta: String
    let demand: String

    var id: String { readAt }

    var demandWatts: Double {
        Double(demand) ?? 0
    }

    var consumptionWh: Double {
        Double(consumptionDelta) ?? 0
    }
}

// MARK: - Chart Time Range

enum ChartRange: String, CaseIterable, Identifiable {
    case fiveMin = "5m"
    case fifteenMin = "15m"
    case oneHour = "1h"
    case sixHours = "6h"
    case twentyFourHours = "24h"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .fiveMin: return 5 * 60
        case .fifteenMin: return 15 * 60
        case .oneHour: return 60 * 60
        case .sixHours: return 6 * 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        }
    }

    var grouping: String {
        switch self {
        case .fiveMin: return "TEN_SECONDS"
        case .fifteenMin: return "ONE_MINUTE"
        case .oneHour: return "FIVE_MINUTES"
        case .sixHours: return "HALF_HOURLY"
        case .twentyFourHours: return "HALF_HOURLY"
        }
    }
}

// MARK: - Live Data

struct LiveData {
    let currentDemandWatts: Double
    let averageDemandWatts: Double
    let todayKWh: Double
    let readings: [TelemetryReading]
    let chartReadings: [TelemetryReading]
    let timestamp: Date

    static let placeholder = LiveData(
        currentDemandWatts: 1240,
        averageDemandWatts: 980,
        todayKWh: 8.2,
        readings: [],
        chartReadings: [],
        timestamp: Date()
    )
}

// MARK: - Formatting

func formatWatts(_ w: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    formatter.groupingSeparator = ","
    let num = formatter.string(from: NSNumber(value: Int(w))) ?? "\(Int(w))"
    return "\(num)W"
}
