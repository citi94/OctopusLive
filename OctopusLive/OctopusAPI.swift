import Foundation

actor OctopusAPI {
    static let shared = OctopusAPI()

    // swiftlint:disable:next force_unwrapping
    private static let graphqlURL = URL(string: "https://api.octopus.energy/v1/graphql/")!
    private var graphqlURL: URL { Self.graphqlURL }

    private var cachedToken: String?
    private var tokenExpiry: Date?
    // The actor is re-entrant across awaits, so concurrent callers (live + today
    // + chart fire together) would each mint a token; share one in-flight fetch.
    private var tokenTask: Task<String, Error>?

    // Several widget families reload at once; let them share one request.
    private var liveTask: Task<TimedValue<[TelemetryReading]>, Error>?
    private var todayTask: Task<Double, Error>?

    // Long-range chart data is only used by the app, so it's cached in memory.
    private var chartCache: [ChartRange: (readings: [TelemetryReading], fetchedAt: Date)] = [:]

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

        if let tokenTask {
            return try await tokenTask.value
        }

        let apiKey = SharedConfig.apiKey
        guard !apiKey.isEmpty else { throw APIError.notConfigured }

        let query = """
        mutation { obtainKrakenToken(input: { APIKey: "\(sanitize(apiKey))" }) { token } }
        """

        let task = Task<String, Error> {
            let response: GraphQLResponse<TokenResponse> = try await execute(query: query, token: nil)
            guard let token = response.data?.obtainKrakenToken.token else {
                throw APIError.authFailed
            }
            return token
        }
        tokenTask = task
        defer { tokenTask = nil }

        let token = try await task.value
        cachedToken = token
        tokenExpiry = Date().addingTimeInterval(55 * 60)
        return token
    }

    func clearTokenCache() {
        cachedToken = nil
        tokenExpiry = nil
        tokenTask = nil
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

    // MARK: - Telemetry
    //
    // Octopus limits smartMeterTelemetry to ~125 calls/hour per account (see
    // `rateLimitInfo`), shared by the app, every widget, and any other tool using
    // the same account. So every read goes through a cache shared via the app
    // group: the widget reuses what the app just fetched and vice versa, and a
    // caller only hits the network when the cached copy is older than it can
    // tolerate.

    /// Live demand for the last 5 minutes (TEN_SECONDS buckets).
    func fetchLiveReadings(maxAge: TimeInterval) async throws -> TimedValue<[TelemetryReading]> {
        if let cached = SharedConfig.liveCache, cached.age < maxAge {
            return cached
        }
        if let liveTask { return try await liveTask.value }
        let task = Task {
            let now = Date()
            let readings = try await telemetry(grouping: "TEN_SECONDS", start: now.addingTimeInterval(-5 * 60), end: now)
            let fresh = TimedValue(value: readings, fetchedAt: now)
            SharedConfig.liveCache = fresh
            return fresh
        }
        liveTask = task
        defer { liveTask = nil }
        return try await task.value
    }

    /// Energy used since local midnight, in kWh.
    func fetchTodayKWh(maxAge: TimeInterval) async throws -> Double {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now)
        if let cached = SharedConfig.todayCache, cached.age < maxAge, cached.fetchedAt >= midnight {
            return cached.value
        }
        if let todayTask { return try await todayTask.value }
        let task = Task {
            let readings = try await telemetry(grouping: "HALF_HOURLY", start: midnight, end: now)
            let kwh = readings.reduce(0.0) { $0 + $1.consumptionWh } / 1000
            SharedConfig.todayCache = TimedValue(value: kwh, fetchedAt: now)
            return kwh
        }
        todayTask = task
        defer { todayTask = nil }
        return try await task.value
    }

    /// Readings for a longer chart range. Coarse buckets change slowly, so these
    /// tolerate a much older cache than the live view.
    func fetchChartData(range: ChartRange, maxAge: TimeInterval) async throws -> [TelemetryReading] {
        if let cached = chartCache[range], Date().timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached.readings
        }
        let now = Date()
        let readings = try await telemetry(grouping: range.grouping, start: now.addingTimeInterval(-range.seconds), end: now)
        chartCache[range] = (readings, now)
        return readings
    }

    /// Everything the widget shows. With the app open this is usually served
    /// entirely from the cache the app keeps warm.
    func fetchWidgetData(liveMaxAge: TimeInterval) async throws -> LiveData {
        let live = try await fetchLiveReadings(maxAge: liveMaxAge)
        let today = (try? await fetchTodayKWh(maxAge: 15 * 60)) ?? SharedConfig.todayCache?.value ?? 0
        return LiveData(live: live, todayKWh: today)
    }

    private func telemetry(grouping: String, start: Date, end: Date) async throws -> [TelemetryReading] {
        guard SharedConfig.isConfigured else { throw APIError.notConfigured }
        // While Octopus is limiting us, don't call at all: repeatedly breaking a
        // dynamic limit makes Kraken tighten it further.
        if let until = SharedConfig.rateLimitedUntil, until > Date() {
            throw APIError.rateLimited(until: until)
        }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let query = """
        {
            smartMeterTelemetry(
                deviceId: "\(sanitize(SharedConfig.deviceId))",
                grouping: \(grouping),
                start: "\(fmt.string(from: start))",
                end: "\(fmt.string(from: end))"
            ) { readAt consumptionDelta demand }
        }
        """

        do {
            let response: GraphQLResponse<TelemetryResponse> = try await executeAuthorized(query: query)
            return response.data?.smartMeterTelemetry ?? []
        } catch APIError.rateLimited {
            let until = await telemetryLimitReset()
            SharedConfig.rateLimitedUntil = until
            throw APIError.rateLimited(until: until)
        }
    }

    /// When the smartMeterTelemetry limit window resets, per Kraken's
    /// `rateLimitInfo` (costs points, not telemetry calls). Falls back to 15
    /// minutes, and never pauses longer than an hour.
    private func telemetryLimitReset() async -> Date {
        let fallback = Date().addingTimeInterval(15 * 60)
        let query = "{ rateLimitInfo { fieldSpecificRateLimits(first: 50) { edges { node { field ttl } } } } }"
        guard let response: GraphQLResponse<RateLimitInfoResponse> = try? await executeAuthorized(query: query),
              let ttl = response.data?.rateLimitInfo.fieldSpecificRateLimits.edges
                .first(where: { $0.node.field == "Query.smartMeterTelemetry" })?.node.ttl
        else { return fallback }
        let reset = Date(timeIntervalSince1970: TimeInterval(ttl))
        return min(max(reset, Date().addingTimeInterval(60)), Date().addingTimeInterval(60 * 60))
    }

    // MARK: - Network

    /// Runs an authenticated query. Kraken tokens can be invalidated before our
    /// local expiry (e.g. API key regenerated, server-side expiry), and a stale
    /// cached token would otherwise keep failing until the cache ages out — so on
    /// an API-level error with a cached token, refresh the token and retry once.
    private func executeAuthorized<T: Decodable>(query: String) async throws -> GraphQLResponse<T> {
        let hadCachedToken = cachedToken != nil
        let token = try await getToken()
        do {
            return try await execute(query: query, token: token)
        } catch let error as APIError where hadCachedToken && error.isAuthError {
            clearTokenCache()
            return try await execute(query: query, token: try await getToken())
        }
    }

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

        guard http.statusCode != 429 else {
            throw APIError.rateLimited(until: Date().addingTimeInterval(15 * 60))
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
            // Kraken reports rate limiting as a GraphQL error on an HTTP 200.
            if first.extensions?.errorCode == "KT-CT-1199" {
                throw APIError.rateLimited(until: Date().addingTimeInterval(15 * 60))
            }
            throw first.isAuthError ? APIError.tokenRejected(first.message) : APIError.apiError(first.message)
        }

        return decoded
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case notConfigured
        case authFailed
        case networkError(String)
        case apiError(String)
        case tokenRejected(String)
        case rateLimited(until: Date)
        case accountNotFound
        case noSmartDevice

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Please enter your API key and account number in the app"
            case .authFailed: return "Invalid API key"
            case .networkError(let detail): return detail
            case .apiError(let message), .tokenRejected(let message): return "Octopus API: \(message)"
            case .rateLimited(let until):
                return "Octopus is limiting requests — resuming at \(until.formatted(date: .omitted, time: .shortened))"
            case .accountNotFound: return "Account not found"
            case .noSmartDevice: return "No Home Mini found on this account"
            }
        }

        var isAuthError: Bool {
            if case .tokenRejected = self { return true }
            return false
        }

        /// Short message for space-constrained surfaces like widgets.
        var shortDescription: String {
            switch self {
            case .notConfigured: return "Open app to set up"
            case .authFailed, .tokenRejected: return "Sign-in failed — open app"
            case .rateLimited: return "Octopus limit — retrying soon"
            case .accountNotFound, .noSmartDevice: return "Check settings in app"
            case .networkError, .apiError: return "Couldn't reach Octopus"
            }
        }
    }
}
