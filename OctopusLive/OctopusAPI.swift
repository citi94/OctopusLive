import Foundation

actor OctopusAPI {
    static let shared = OctopusAPI()

    // swiftlint:disable:next force_unwrapping
    private static let graphqlURL = URL(string: "https://api.octopus.energy/v1/graphql/")!
    private var graphqlURL: URL { Self.graphqlURL }

    private var cachedToken: String?
    private var tokenExpiry: Date?

    // Rate limit tracking
    private(set) var lastRateLimitInfo: RateLimitInfo?

    struct RateLimitInfo {
        let headers: [String: String]
        let timestamp: Date
    }

    // MARK: - Sanitization

    /// Escape a string for safe inclusion in a GraphQL query string literal
    private func sanitize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
    }

    // MARK: - Auth

    private func getToken() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }

        let apiKey = SharedConfig.apiKey
        guard !apiKey.isEmpty else { throw APIError.notConfigured }

        let query = """
        mutation { obtainKrakenToken(input: { APIKey: "\(sanitize(apiKey))" }) { token } }
        """

        let response: GraphQLResponse<TokenResponse> = try await execute(query: query, token: nil)
        guard let token = response.data?.obtainKrakenToken.token else {
            throw APIError.authFailed
        }

        cachedToken = token
        tokenExpiry = Date().addingTimeInterval(55 * 60)
        return token
    }

    func clearTokenCache() {
        cachedToken = nil
        tokenExpiry = nil
    }

    // MARK: - Account Discovery

    func discoverDevice(apiKey: String, accountNumber: String) async throws -> (deviceId: String, mpan: String, serial: String) {
        let tokenQuery = """
        mutation { obtainKrakenToken(input: { APIKey: "\(sanitize(apiKey))" }) { token } }
        """
        let tokenResponse: GraphQLResponse<TokenResponse> = try await execute(query: tokenQuery, token: nil)
        guard let token = tokenResponse.data?.obtainKrakenToken.token else {
            throw APIError.authFailed
        }

        let query = """
        {
            account(accountNumber: "\(sanitize(accountNumber))") {
                electricityAgreements(active: true) {
                    meterPoint {
                        mpan
                        meters(includeInactive: false) {
                            serialNumber
                            smartDevices { deviceId }
                        }
                    }
                }
            }
        }
        """

        let response: GraphQLResponse<AccountResponse> = try await execute(query: query, token: token)

        guard let account = response.data?.account else {
            throw APIError.accountNotFound
        }

        for agreement in account.electricityAgreements ?? [] {
            if let mp = agreement.meterPoint {
                for meter in mp.meters ?? [] {
                    for device in meter.smartDevices ?? [] {
                        if let deviceId = device.deviceId, !deviceId.isEmpty {
                            return (
                                deviceId: deviceId,
                                mpan: mp.mpan ?? "",
                                serial: meter.serialNumber ?? ""
                            )
                        }
                    }
                }
            }
        }

        throw APIError.noSmartDevice
    }

    // MARK: - Live Demand (lightweight, called frequently)

    func fetchLiveDemand() async throws -> (current: Double, avg: Double, readings: [TelemetryReading]) {
        guard SharedConfig.isConfigured else { throw APIError.notConfigured }

        let token = try await getToken()
        let deviceId = SharedConfig.deviceId

        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        let query = """
        {
            smartMeterTelemetry(
                deviceId: "\(sanitize(deviceId))",
                grouping: TEN_SECONDS,
                start: "\(fmt.string(from: now.addingTimeInterval(-5 * 60)))",
                end: "\(fmt.string(from: now))"
            ) { readAt consumptionDelta demand }
        }
        """

        let response: GraphQLResponse<TelemetryResponse> = try await execute(query: query, token: token)
        let readings = response.data?.smartMeterTelemetry ?? []

        let current = readings.last?.demandWatts ?? 0
        let avg = readings.isEmpty ? 0 :
            readings.reduce(0.0) { $0 + $1.demandWatts } / Double(readings.count)

        return (current: current, avg: avg, readings: readings)
    }

    // MARK: - Today Usage (called infrequently)

    func fetchTodayKWh() async throws -> Double {
        guard SharedConfig.isConfigured else { throw APIError.notConfigured }

        let token = try await getToken()
        let deviceId = SharedConfig.deviceId

        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        let query = """
        {
            smartMeterTelemetry(
                deviceId: "\(sanitize(deviceId))",
                grouping: HALF_HOURLY,
                start: "\(fmt.string(from: Calendar.current.startOfDay(for: now)))",
                end: "\(fmt.string(from: now))"
            ) { readAt consumptionDelta demand }
        }
        """

        let response: GraphQLResponse<TelemetryResponse> = try await execute(query: query, token: token)
        let readings = response.data?.smartMeterTelemetry ?? []
        let totalWh = readings.reduce(0.0) { $0 + $1.consumptionWh }
        return totalWh / 1000
    }

    // MARK: - Chart Data (called on range change)

    func fetchChartData(range: ChartRange) async throws -> [TelemetryReading] {
        guard SharedConfig.isConfigured else { throw APIError.notConfigured }

        let token = try await getToken()
        let deviceId = SharedConfig.deviceId

        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        let query = """
        {
            smartMeterTelemetry(
                deviceId: "\(sanitize(deviceId))",
                grouping: \(range.grouping),
                start: "\(fmt.string(from: now.addingTimeInterval(-range.seconds)))",
                end: "\(fmt.string(from: now))"
            ) { readAt consumptionDelta demand }
        }
        """

        let response: GraphQLResponse<TelemetryResponse> = try await execute(query: query, token: token)
        return response.data?.smartMeterTelemetry ?? []
    }

    // MARK: - Combined fetch for widget (single request, aliases)

    func fetchAll(chartRange: ChartRange = .fiveMin) async throws -> LiveData {
        guard SharedConfig.isConfigured else { throw APIError.notConfigured }

        let token = try await getToken()
        let deviceId = SharedConfig.deviceId

        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        let isoNow = fmt.string(from: now)
        let isoFiveMin = fmt.string(from: now.addingTimeInterval(-5 * 60))
        let isoStartOfDay = fmt.string(from: Calendar.current.startOfDay(for: now))

        let chartAlias: String
        if chartRange == .fiveMin {
            chartAlias = ""
        } else {
            let isoChartStart = fmt.string(from: now.addingTimeInterval(-chartRange.seconds))
            chartAlias = """
                chart: smartMeterTelemetry(
                    deviceId: "\(sanitize(deviceId))",
                    grouping: \(chartRange.grouping),
                    start: "\(isoChartStart)",
                    end: "\(isoNow)"
                ) { readAt consumptionDelta demand }
            """
        }

        let query = """
        {
            live: smartMeterTelemetry(
                deviceId: "\(sanitize(deviceId))",
                grouping: TEN_SECONDS,
                start: "\(isoFiveMin)",
                end: "\(isoNow)"
            ) { readAt consumptionDelta demand }
            today: smartMeterTelemetry(
                deviceId: "\(sanitize(deviceId))",
                grouping: HALF_HOURLY,
                start: "\(isoStartOfDay)",
                end: "\(isoNow)"
            ) { readAt consumptionDelta demand }
            \(chartAlias)
        }
        """

        let response: GraphQLResponse<CombinedTelemetryResponse> = try await execute(query: query, token: token)

        let liveReadings = response.data?.live ?? []
        let todayReadings = response.data?.today ?? []
        let chartReadings = response.data?.chart ?? liveReadings

        let currentDemand = liveReadings.last?.demandWatts ?? 0
        let avgDemand = liveReadings.isEmpty ? 0 :
            liveReadings.reduce(0.0) { $0 + $1.demandWatts } / Double(liveReadings.count)

        let totalWh = todayReadings.reduce(0.0) { $0 + $1.consumptionWh }
        let totalKwh = totalWh / 1000

        return LiveData(
            currentDemandWatts: currentDemand,
            averageDemandWatts: avgDemand,
            todayKWh: totalKwh,
            readings: liveReadings,
            chartReadings: chartReadings,
            timestamp: now
        )
    }

    // MARK: - Network

    private func execute<T: Decodable>(query: String, token: String?) async throws -> GraphQLResponse<T> {
        var request = URLRequest(url: graphqlURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError("No HTTP response")
        }

        // Capture rate limit headers
        var rateLimitHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            let k = "\(key)".lowercased()
            if k.contains("rate") || k.contains("limit") || k.contains("retry") || k.contains("throttle") {
                rateLimitHeaders["\(key)"] = "\(value)"
            }
        }
        if !rateLimitHeaders.isEmpty || http.statusCode == 429 {
            lastRateLimitInfo = RateLimitInfo(headers: rateLimitHeaders, timestamp: Date())
        }

        guard http.statusCode != 429 else {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After") ?? "unknown"
            throw APIError.rateLimited(retryAfter: retryAfter)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw APIError.networkError("HTTP \(http.statusCode): \(body.prefix(200))")
        }

        let decoded: GraphQLResponse<T>
        do {
            decoded = try JSONDecoder().decode(GraphQLResponse<T>.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw APIError.networkError("Decode error: \(error.localizedDescription)\n\(body.prefix(300))")
        }

        if let errors = decoded.errors, let first = errors.first {
            throw APIError.networkError("API: \(first.message)")
        }

        return decoded
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case notConfigured
        case authFailed
        case networkError(String)
        case rateLimited(retryAfter: String)
        case accountNotFound
        case noSmartDevice

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Please enter your API key and account number in the app"
            case .authFailed: return "Invalid API key"
            case .networkError(let detail): return detail
            case .rateLimited(let retry): return "Rate limited (retry after: \(retry))"
            case .accountNotFound: return "Account not found"
            case .noSmartDevice: return "No Home Mini found on this account"
            }
        }
    }
}
