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

// MARK: - Widget Data

struct WidgetData {
    let currentDemandWatts: Double
    let averageDemandWatts: Double
    let todayKWh: Double
    let todayCostPounds: Double
    let readings: [TelemetryReading]
    let timestamp: Date

    var currentDemandFormatted: String {
        formatWatts(currentDemandWatts)
    }

    var averageDemandFormatted: String {
        formatWatts(averageDemandWatts)
    }

    var todayKWhFormatted: String {
        String(format: "%.1f kWh", todayKWh)
    }

    var todayCostFormatted: String {
        String(format: "£%.2f", todayCostPounds)
    }

    private func formatWatts(_ w: Double) -> String {
        if w >= 1000 {
            return String(format: "%.1f kW", w / 1000)
        }
        return "\(Int(w)) W"
    }

    static let placeholder = WidgetData(
        currentDemandWatts: 1240,
        averageDemandWatts: 980,
        todayKWh: 8.2,
        todayCostPounds: 2.47,
        readings: [],
        timestamp: Date()
    )
}
