import SwiftUI

struct LiveView: View {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var isDemo: Bool = false

    @State private var currentWatts: Double = 0
    @State private var avgWatts: Double = 0
    @State private var todayKWh: Double = 0
    @State private var liveReadings: [TelemetryReading] = []
    @State private var chartReadings: [TelemetryReading] = []
    @State private var chartRange: ChartRange = .fiveMin
    @State private var lastUpdate: Date?
    @State private var error: String?
    @State private var liveTimer: Timer?
    @State private var todayTimer: Timer?
    @State private var liveInterval: TimeInterval = 40
    private let todayInterval: TimeInterval = 300

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.12)
                .ignoresSafeArea()

            if lastUpdate != nil {
                ScrollView {
                    VStack(spacing: 24) {
                        demandSection
                        chartSection
                        todaySection
                        updatedLabel
                    }
                    .padding()
                }
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button {
                        self.error = nil
                        fetchLive()
                        fetchToday()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.yellow)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                    }
                }
            } else {
                ProgressView("Loading...")
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle("Octopus Live")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
        .onChange(of: chartRange) {
            fetchChart()
        }
    }

    // MARK: - Demand

    private var demandSection: some View {
        VStack(spacing: 8) {
            Text("LIVE")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(3)
                .foregroundStyle(demandColor(currentWatts))

            Text(formatWatts(currentWatts))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(demandColor(currentWatts))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: currentWatts)

            Label("5m avg \(formatWatts(avgWatts))", systemImage: "chart.line.flattrend.xyaxis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $chartRange) {
                ForEach(ChartRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            let readings = chartRange == .fiveMin ? liveReadings : chartReadings
            DemandChart(readings: readings)
                .frame(height: 180)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Today

    private var todaySection: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f kWh", todayKWh))
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("used today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Updated

    private var updatedLabel: some View {
        Group {
            if let lastUpdate {
                Text("Updated \(Self.timeFormatter.string(from: lastUpdate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        if isDemo {
            loadDemoData()
            liveTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                loadDemoData()
            }
            return
        }
        fetchLive()
        fetchToday()
        liveTimer = Timer.scheduledTimer(withTimeInterval: liveInterval, repeats: true) { _ in
            fetchLive()
        }
        todayTimer = Timer.scheduledTimer(withTimeInterval: todayInterval, repeats: true) { _ in
            fetchToday()
        }
    }

    private func loadDemoData() {
        let base = Double.random(in: 800...2500)
        currentWatts = base + Double.random(in: -200...200)
        avgWatts = base
        todayKWh = Double.random(in: 4...12)
        lastUpdate = Date()
    }

    private func stopPolling() {
        liveTimer?.invalidate()
        liveTimer = nil
        todayTimer?.invalidate()
        todayTimer = nil
    }

    private func fetchLive() {
        Task {
            do {
                let result = try await OctopusAPI.shared.fetchLiveDemand()
                await MainActor.run {
                    self.currentWatts = result.current
                    self.avgWatts = result.avg
                    self.liveReadings = result.readings
                    self.lastUpdate = Date()
                    self.error = nil
                    if liveInterval > 40 {
                        adjustPolling(interval: max(40, liveInterval - 10))
                    }
                }
            } catch let apiError as OctopusAPI.APIError {
                await MainActor.run {
                    if case .rateLimited = apiError {
                        adjustPolling(interval: min(120, liveInterval + 30))
                    } else {
                        self.error = apiError.localizedDescription
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func adjustPolling(interval: TimeInterval) {
        guard interval != liveInterval else { return }
        liveInterval = interval
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: liveInterval, repeats: true) { _ in
            fetchLive()
        }
    }

    private func fetchToday() {
        Task {
            do {
                let kwh = try await OctopusAPI.shared.fetchTodayKWh()
                await MainActor.run {
                    self.todayKWh = kwh
                }
            } catch {
                // Non-critical, don't overwrite main error
            }
        }
    }

    private func fetchChart() {
        guard chartRange != .fiveMin else { return }
        Task {
            do {
                let readings = try await OctopusAPI.shared.fetchChartData(range: chartRange)
                await MainActor.run {
                    self.chartReadings = readings
                }
            } catch {
                // Non-critical
            }
        }
    }
}

// MARK: - Demand Chart

struct DemandChart: View {
    let readings: [TelemetryReading]

    var body: some View {
        let demands = readings.map(\.demandWatts)
        let maxD = demands.max() ?? 0
        let minD = demands.min() ?? 0
        let rawRange = maxD - minD
        let scaleMin = max(0, minD - rawRange * 0.1)
        let scaleMax = maxD + rawRange * 0.1
        let range = max(scaleMax - scaleMin, 100)

        if readings.count > 1 {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    VStack {
                        Text(formatWatts(scaleMax))
                        Spacer()
                        Text(formatWatts((scaleMax + scaleMin) / 2))
                        Spacer()
                        Text(formatWatts(scaleMin))
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .frame(width: 52, alignment: .trailing)

                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let stepX = w / CGFloat(readings.count - 1)

                        ForEach(0..<3) { i in
                            let y = h * CGFloat(i) / 2.0
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        }

                        Path { path in
                            for (i, r) in readings.enumerated() {
                                let x = CGFloat(i) * stepX
                                let y = h - ((CGFloat(r.demandWatts - scaleMin) / CGFloat(range)) * h)
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: h))
                                    path.addLine(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                            path.addLine(to: CGPoint(x: CGFloat(readings.count - 1) * stepX, y: h))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        Path { path in
                            for (i, r) in readings.enumerated() {
                                let x = CGFloat(i) * stepX
                                let y = h - ((CGFloat(r.demandWatts - scaleMin) / CGFloat(range)) * h)
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(
                            LinearGradient(colors: [.green, .yellow, .orange, .red], startPoint: .bottom, endPoint: .top),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
                .frame(height: 140)
            }
        } else {
            Text("Waiting for data...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Helpers

#Preview {
    NavigationStack {
        LiveView()
    }
}
