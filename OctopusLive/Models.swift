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

// MARK: - Rate Limit Info

struct RateLimitInfoResponse: Decodable {
    let rateLimitInfo: Info

    struct Info: Decodable {
        let fieldSpecificRateLimits: Connection
    }
    struct Connection: Decodable {
        let edges: [Edge]
    }
    struct Edge: Decodable {
        let node: Node
    }
    struct Node: Decodable {
        let field: String
        /// Unix timestamp at which the current window resets.
        let ttl: Int
    }
}

// MARK: - Cache

struct TimedValue<T: Codable>: Codable {
    let value: T
    let fetchedAt: Date

    var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }
}

// MARK: - Chart Time Range

enum ChartRange: String, CaseIterable, Identifiable, Hashable {
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

    /// Which local history this range is drawn from.
    var history: HistoryKind {
        self == .twentyFourHours ? .minute : .fine
    }
}

// MARK: - Telemetry History
//
// A rolling local copy of fine-grained telemetry. Charts are drawn from it,
// and only the gaps are fetched, so zooming out keeps full detail without
// spending more of Octopus's per-hour call allowance.

enum HistoryKind: String, Codable {
    /// 10-second readings for the last 6 hours (fed by the live poll for free).
    case fine
    /// 1-minute readings for the last 24 hours (10-second data for a whole
    /// day is more than Kraken will return in one request).
    case minute

    var grouping: String { self == .fine ? "TEN_SECONDS" : "ONE_MINUTE" }
    var bucket: TimeInterval { self == .fine ? 10 : 60 }
    var retention: TimeInterval { (self == .fine ? 6 : 24) * 3600 + 600 }
    /// How out of date the newest data may be before topping it up. The live
    /// poll keeps `.fine` current on its own while the app is open.
    var freshness: TimeInterval { self == .fine ? 90 : 10 * 60 }
}

struct ChartPoint {
    let date: Date
    let watts: Double
}

struct ChartSeries {
    let points: [ChartPoint]
    let start: Date
    let end: Date
    /// Bucket length, in seconds; consecutive points further apart than a few
    /// buckets are a gap in the data and drawn as a break in the line.
    let bucket: TimeInterval
}

struct TelemetryHistory: Codable {
    let kind: HistoryKind
    private var readings: [Date: TelemetryReading] = [:]
    /// Time spans known to be fully fetched, sorted and non-overlapping.
    private var covered: [ClosedRange<Date>] = []

    init(kind: HistoryKind) {
        self.kind = kind
    }

    mutating func merge(_ new: [TelemetryReading], from start: Date, to end: Date) {
        for reading in new {
            if let date = parseReadAt(reading.readAt) { readings[date] = reading }
        }
        // Union the new span into the covered spans, joining any that touch.
        let slack = kind.bucket * 3
        var span = start...max(start, end)
        var kept: [ClosedRange<Date>] = []
        for range in covered {
            if range.upperBound.addingTimeInterval(slack) < span.lowerBound
                || range.lowerBound.addingTimeInterval(-slack) > span.upperBound {
                kept.append(range)
            } else {
                span = min(range.lowerBound, span.lowerBound)...max(range.upperBound, span.upperBound)
            }
        }
        covered = (kept + [span]).sorted { $0.lowerBound < $1.lowerBound }
        prune(now: max(end, Date()))
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-kind.retention)
        readings = readings.filter { $0.key >= cutoff }
        covered = covered.compactMap { range in
            range.upperBound < cutoff ? nil : max(range.lowerBound, cutoff)...range.upperBound
        }
    }

    /// The single span to fetch so that `start...now` is fully covered, or nil
    /// if the history already has it. Multiple holes are fetched as one request
    /// spanning them all — Octopus limits calls, not data size.
    func missingSpan(start: Date, now: Date) -> (from: Date, to: Date)? {
        let needUntil = now.addingTimeInterval(-kind.freshness)
        var cursor = start
        var firstGap: Date?
        var lastGapEnd: Date?
        for range in covered where range.upperBound > cursor {
            if range.lowerBound > cursor.addingTimeInterval(kind.bucket) {
                firstGap = firstGap ?? cursor
                lastGapEnd = range.lowerBound
            }
            cursor = max(cursor, range.upperBound)
            if cursor >= needUntil { break }
        }
        if cursor < needUntil {
            firstGap = firstGap ?? cursor
            lastGapEnd = now
        }
        guard let from = firstGap, let to = lastGapEnd else { return nil }
        return (max(start, from.addingTimeInterval(-kind.bucket)), min(now, to.addingTimeInterval(kind.bucket)))
    }

    func series(start: Date, end: Date) -> ChartSeries {
        let points = readings
            .filter { $0.key >= start && $0.key <= end }
            .sorted { $0.key < $1.key }
            .compactMap { date, reading in
                reading.chartWatts(intervalSeconds: kind.bucket).map { ChartPoint(date: date, watts: $0) }
            }
        return ChartSeries(points: points, start: start, end: end, bucket: kind.bucket)
    }
}

private let readAtFormatter = ISO8601DateFormatter()

func parseReadAt(_ string: String) -> Date? {
    readAtFormatter.date(from: string)
}

// MARK: - Live Data

struct LiveData: Codable {
    let currentDemandWatts: Double
    let averageDemandWatts: Double
    let todayKWh: Double
    let readings: [TelemetryReading]
    let chartReadings: [TelemetryReading]
    let timestamp: Date

    init(currentDemandWatts: Double, averageDemandWatts: Double, todayKWh: Double,
         readings: [TelemetryReading], chartReadings: [TelemetryReading], timestamp: Date) {
        self.currentDemandWatts = currentDemandWatts
        self.averageDemandWatts = averageDemandWatts
        self.todayKWh = todayKWh
        self.readings = readings
        self.chartReadings = chartReadings
        self.timestamp = timestamp
    }

    init(live: TimedValue<[TelemetryReading]>, todayKWh: Double) {
        self.init(
            currentDemandWatts: live.value.currentDemandWatts,
            averageDemandWatts: live.value.averageDemandWatts,
            todayKWh: todayKWh,
            readings: live.value,
            chartReadings: live.value,
            timestamp: live.fetchedAt
        )
    }

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
