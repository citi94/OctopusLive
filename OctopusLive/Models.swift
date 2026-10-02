import Foundation

// MARK: - GraphQL Response Types

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    let message: String
    let extensions: Extensions?

    struct Extensions: Decodable {
        let errorCode: String?
    }

    /// Kraken signals expired/invalid tokens via GraphQL errors (HTTP 200).
    var isAuthError: Bool {
        let code = extensions?.errorCode ?? ""
        // KT-CT-1111 unauthorized, KT-CT-1124 JWT expired, KT-CT-1143 invalid token
        if ["KT-CT-1111", "KT-CT-1124", "KT-CT-1143"].contains(code) { return true }
        let m = message.lowercased()
        return m.contains("token") || m.contains("jwt") || m.contains("signature")
            || m.contains("unauthori") || m.contains("authenticat")
    }
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

struct TelemetryReading: Codable, Identifiable {
    let readAt: String
    // Kraken returns these as null for intervals without a real-time read
    // (e.g. HALF_HOURLY buckets, or gaps when the Home Mini wasn't streaming),
    // so they must be optional or a single null fails the whole decode.
    let consumptionDelta: String?
    let demand: String?

    var id: String { readAt }

    var demandWatts: Double {
        Double(demand ?? "") ?? 0
    }

    var consumptionWh: Double {
        Double(consumptionDelta ?? "") ?? 0
    }

    /// True when this interval carries an actual real-time demand reading
    /// (non-null and numeric, including a genuine 0 W).
    var hasDemand: Bool {
        guard let demand else { return false }
        return Double(demand) != nil
    }

    /// Value to plot for this interval: the real-time demand when present,
    /// otherwise the average power implied by the interval's consumption
    /// (Wh over the bucket length). Coarse groupings like HALF_HOURLY return
    /// null demand, so without this fallback those charts flatline at 0 W.
    /// Nil when the interval has neither.
    func chartWatts(intervalSeconds: TimeInterval) -> Double? {
        if hasDemand { return demandWatts }
        guard let delta = consumptionDelta, let wh = Double(delta) else { return nil }
        return wh * 3600 / intervalSeconds
    }
}

extension Array where Element == TelemetryReading {
    /// Readings that carry a real-time demand value. Null-demand gaps must be
    /// skipped, not treated as 0 W, or they drag the current/average figures down.
    var withDemand: [TelemetryReading] { filter(\.hasDemand) }

    /// Most recent real demand reading, in watts.
    var currentDemandWatts: Double { withDemand.last?.demandWatts ?? 0 }

    /// Mean of the real demand readings, in watts.
    var averageDemandWatts: Double {
        let values = withDemand.map(\.demandWatts)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
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

    /// Length of one bucket for `grouping`, in seconds.
    var intervalSeconds: TimeInterval {
        switch self {
        case .fiveMin: return 10
        case .fifteenMin: return 60
        case .oneHour: return 5 * 60
        case .sixHours, .twentyFourHours: return 30 * 60
        }
    }
}

// MARK: - Live Data

struct LiveData: Codable {
    let currentDemandWatts: Double
    let averageDemandWatts: Double
    let todayKWh: Double
    let readings: [TelemetryReading]
    let chartReadings: [TelemetryReading]
    let timestamp: Date

    /// True when the live window actually contains real-time demand readings.
    /// Distinguishes "Home Mini streaming" from "connected but no data yet".
    var hasLiveData: Bool {
        readings.contains { $0.hasDemand }
    }

    static let placeholder = LiveData(
        currentDemandWatts: 1240,
        averageDemandWatts: 980,
        todayKWh: 8.2,
        readings: [],
        chartReadings: [],
        timestamp: Date()
    )
}

// MARK: - Demand Color

import SwiftUI

func demandColor(_ watts: Double) -> Color {
    switch watts {
    case ..<300: return .green
    case ..<1000: return .yellow
    case ..<3000: return .orange
    default: return .red
    }
}

// MARK: - Formatting

func formatWatts(_ w: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    formatter.groupingSeparator = ","
    let rounded = Int(w.rounded())
    let num = formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    return "\(num)W"
}
