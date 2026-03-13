import Foundation

actor OctopusAPI {
    static let shared = OctopusAPI()

    private let graphqlURL = URL(string: "https://api.octopus.energy/v1/graphql/")!

    // Tariff rates (pence) — Silver fixed
    private let unitRatePence: Double = 24.5
    private let standingChargePence: Double = 46.36

    private var cachedToken: String?
    private var tokenExpiry: Date?

    // MARK: - Auth

    private func getToken() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }

        let apiKey = SharedConfig.apiKey
        guard !apiKey.isEmpty else { throw APIError.notConfigured }

        let query = """
        mutation { obtainKrakenToken(input: { APIKey: "\(apiKey)" }) { token } }
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
        // Get a token with the provided key
        let tokenQuery = """
        mutation { obtainKrakenToken(input: { APIKey: "\(apiKey)" }) { token } }
        """
        let tokenResponse: GraphQLResponse<TokenResponse> = try await execute(query: tokenQuery, token: nil)
        guard let token = tokenResponse.data?.obtainKrakenToken.token else {
            throw APIError.authFailed
        }

        let query = """
        {
            account(accountNumber: "\(accountNumber)") {
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

    func fetchWidgetData() async throws -> WidgetData {
        guard SharedConfig.isConfigured else { throw APIError.notConfigured }

        let token = try await getToken()
        let deviceId = SharedConfig.deviceId

        // Fetch last 5 mins of live data
        let now = Date()
        let fiveMinAgo = now.addingTimeInterval(-5 * 60)
        let startOfDay = Calendar.current.startOfDay(for: now)

        let isoNow = ISO8601DateFormatter().string(from: now)
        let isoFiveMin = ISO8601DateFormatter().string(from: fiveMinAgo)
        let isoStartOfDay = ISO8601DateFormatter().string(from: startOfDay)

        let liveQuery = """
        {
            smartMeterTelemetry(
                deviceId: "\(deviceId)",
                grouping: TEN_SECONDS,
                start: "\(isoFiveMin)",
                end: "\(isoNow)"
            ) { readAt consumptionDelta demand }
        }
        """

        let todayQuery = """
        {
            smartMeterTelemetry(
                deviceId: "\(deviceId)",
                grouping: HALF_HOUR,
                start: "\(isoStartOfDay)",
                end: "\(isoNow)"
            ) { readAt consumptionDelta demand }
        }
        """

        async let liveResponse: GraphQLResponse<TelemetryResponse> = execute(query: liveQuery, token: token)
        async let todayResponse: GraphQLResponse<TelemetryResponse> = execute(query: todayQuery, token: token)

        let (live, today) = try await (liveResponse, todayResponse)

        let liveReadings = live.data?.smartMeterTelemetry ?? []
        let todayReadings = today.data?.smartMeterTelemetry ?? []

        let currentDemand = liveReadings.last?.demandWatts ?? 0
        let avgDemand = liveReadings.isEmpty ? 0 :
            liveReadings.reduce(0.0) { $0 + $1.demandWatts } / Double(liveReadings.count)

        let totalWh = todayReadings.reduce(0.0) { $0 + $1.consumptionWh }
        let totalKwh = totalWh / 1000
        let costPence = totalKwh * unitRatePence + standingChargePence
        let costPounds = costPence / 100

        return WidgetData(
            currentDemandWatts: currentDemand,
            averageDemandWatts: avgDemand,
            todayKWh: totalKwh,
            todayCostPounds: costPounds,
            timestamp: now
        )
    }

    // MARK: - Network

    private func execute<T: Decodable>(query: String, token: String?) async throws -> GraphQLResponse<T> {
        var request = URLRequest(url: graphqlURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }

        return try JSONDecoder().decode(GraphQLResponse<T>.self, from: data)
    }

    // MARK: - Errors

    enum APIError: LocalizedError {
        case notConfigured
        case authFailed
        case httpError
        case accountNotFound
        case noSmartDevice

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Please enter your API key and account number in the app"
            case .authFailed: return "Invalid API key"
            case .httpError: return "Network request failed"
            case .accountNotFound: return "Account not found"
            case .noSmartDevice: return "No Home Mini found on this account"
            }
        }
    }
}
