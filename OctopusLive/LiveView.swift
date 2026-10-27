import SwiftUI

struct LiveView: View {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var isDemo: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    @State private var currentWatts: Double = 0
    @State private var avgWatts: Double = 0
    @State private var todayKWh: Double = 0
    @State private var liveReadings: [TelemetryReading] = []
    @State private var chartSeries: ChartSeries?
    @State private var chartRange: ChartRange = .fiveMin
    @State private var lastUpdate: Date?
    @State private var hasLiveData = false
    @State private var consecutiveFailures = 0
    @State private var error: String?
    @State private var rateLimitedUntil: Date?
    @State private var liveTimer: Timer?
    @State private var slowTimer: Timer?

    // Octopus allows ~125 telemetry calls/hour per account, shared with the
    // widget. Live every 45s (80/h) + today every 15 min + a long-range chart
    // every 5–15 min keeps the app under ~100/h; the widget reuses the app's
    // cache while it's open.
    private let liveInterval: TimeInterval = 45
    private let slowInterval: TimeInterval = 5 * 60

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.12)
                .ignoresSafeArea()

            content
        }
        .navigationTitle("Octo Live")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
        .onChange(of: chartRange) {
            chartSeries = nil
            fetchChart()
        }
        // Timers don't fire in the background, so refresh on return. Each fetch
        // is cache-aware, so this only hits the API for data that's actually stale.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !isDemo {
                fetchLive()
                fetchToday()
                fetchChart()
            }
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        // A persistent failure (2+ in a row) surfaces even over stale data,
        // so a mid-session auth/decode break doesn't freeze on old numbers.
        let hardError = error != nil && (lastUpdate == nil || consecutiveFailures >= 2)

        if hardError, let error {
            errorView(message: error)
        } else if lastUpdate != nil && hasLiveData {
            ScrollView {
                VStack(spacing: 24) {
                    demandSection
                    chartSection
                    todaySection
                    updatedLabel
                }
                .padding()
            }
        } else if lastUpdate != nil {
            noLiveDataView
        } else {
            ProgressView("Loading...")
                .foregroundStyle(.white)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            retryButton
        }
    }

    // Connected (and authenticated) but the Home Mini isn't sending real-time
    // demand yet — show why instead of a misleading confident "0W".
    private var noLiveDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text("Connected, but no live data yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Your Octopus Home Mini isn't sending real-time readings right now. Make sure it's plugged in, connected to Wi-Fi, and online — live data can take a few minutes to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if todayKWh > 0 {
                Text(String(format: "%.1f kWh used today", todayKWh))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            retryButton
        }
        .padding()
    }

    private var retryButton: some View {
        Button {
            self.error = nil
            consecutiveFailures = 0
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

            DemandChart(series: chartRange == .fiveMin ? liveSeries : chartSeries)
                .frame(height: 180)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var liveSeries: ChartSeries? {
        guard let end = lastUpdate else { return nil }
        let points = liveReadings.compactMap { reading -> ChartPoint? in
            guard reading.hasDemand, let date = parseReadAt(reading.readAt) else { return nil }
            return ChartPoint(date: date, watts: reading.demandWatts)
        }
        return ChartSeries(points: points, start: end.addingTimeInterval(-5 * 60), end: end, bucket: 10)
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
            if let rateLimitedUntil, rateLimitedUntil > Date() {
                Label("Octopus is limiting requests — showing the last reading until \(rateLimitedUntil.formatted(date: .omitted, time: .shortened))", systemImage: "hourglass")
                    .font(.caption2)
                    .foregroundStyle(.yellow.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            if let lastUpdate {
                Text("Updated \(Self.timeFormatter.string(from: lastUpdate))")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        // onAppear can fire more than once without a matching onDisappear;
        // never stack a second set of timers (doubles API calls → rate limits).
        stopPolling()
        if isDemo {
            loadDemoData()
            liveTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                loadDemoData()
            }
            return
        }
        // Show whatever the app or widget fetched last straight away.
        if let cached = SharedConfig.liveCache {
            apply(cached)
        }
        if let today = SharedConfig.todayCache {
            todayKWh = today.value
        }
        fetchLive()
        fetchToday()
        fetchChart()
        liveTimer = Timer.scheduledTimer(withTimeInterval: liveInterval, repeats: true) { _ in
            fetchLive()
        }
        slowTimer = Timer.scheduledTimer(withTimeInterval: slowInterval, repeats: true) { _ in
            fetchToday()
            fetchChart()
        }
    }

    private func loadDemoData() {
        let now = Date()
        let fmt = ISO8601DateFormatter()
        func readings(count: Int, step: TimeInterval, base: Double, jitter: Double) -> [TelemetryReading] {
            (0..<count).map { i in
                let t = now.addingTimeInterval(-Double(count - 1 - i) * step)
                // Gentle wave plus noise so the chart looks like a real household.
                let w = max(80, base + sin(Double(i) / 4) * base * 0.3 + Double.random(in: -jitter...jitter))
                return TelemetryReading(
                    readAt: fmt.string(from: t),
                    consumptionDelta: String(format: "%.1f", w * step / 3600),
                    demand: String(format: "%.0f", w)
                )
            }
        }

        let live = readings(count: 30, step: 10, base: 1100, jitter: 250)
        liveReadings = live
        // Regenerate the long-range chart only when the range changes (it's
        // cleared then), not on every 3s demo tick.
        if chartRange != .fiveMin && chartSeries == nil {
            let bucket = chartRange.history.bucket
            let points = readings(count: Int(chartRange.seconds / bucket), step: bucket, base: 700, jitter: 300)
                .compactMap { r in parseReadAt(r.readAt).map { ChartPoint(date: $0, watts: r.demandWatts) } }
            chartSeries = ChartSeries(points: points, start: now.addingTimeInterval(-chartRange.seconds), end: now, bucket: bucket)
        }
        currentWatts = live.currentDemandWatts
        avgWatts = live.averageDemandWatts
        todayKWh = 8.4
        hasLiveData = true
        lastUpdate = now
    }

    private func stopPolling() {
        liveTimer?.invalidate()
        liveTimer = nil
        slowTimer?.invalidate()
        slowTimer = nil
    }

    private func apply(_ live: TimedValue<[TelemetryReading]>) {
        currentWatts = live.value.currentDemandWatts
        avgWatts = live.value.averageDemandWatts
        liveReadings = live.value
        hasLiveData = live.value.contains { $0.hasDemand }
        lastUpdate = live.fetchedAt
    }

    private func fetchLive() {
        Task {
            do {
                // A little under the poll interval, so a fresh widget fetch is reused.
                let live = try await OctopusAPI.shared.fetchLiveReadings(maxAge: 30)
                await OctopusAPI.shared.recordLive(live)
                await MainActor.run {
                    apply(live)
                    self.error = nil
                    self.consecutiveFailures = 0
                    self.rateLimitedUntil = nil
                    // Redraw longer ranges from the history the poll just extended.
                    fetchChart()
                }
            } catch OctopusAPI.APIError.rateLimited(let until) {
                // Not a failure: keep showing the last reading and say why.
                await MainActor.run { self.rateLimitedUntil = until }
            } catch {
                await MainActor.run {
                    self.consecutiveFailures += 1
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func fetchToday() {
        Task {
            do {
                let kwh = try await OctopusAPI.shared.fetchTodayKWh(maxAge: 15 * 60)
                await MainActor.run {
                    self.todayKWh = kwh
                }
            } catch {
                // Non-critical, don't overwrite main error
            }
        }
    }

    private func fetchChart() {
        if isDemo {
            loadDemoData()
            return
        }
        let range = chartRange
        guard range != .fiveMin else { return }
        Task {
            do {
                let series = try await OctopusAPI.shared.chartSeries(range: range)
                await MainActor.run {
                    // Drop results for a range the user has already switched away from.
                    guard self.chartRange == range else { return }
                    self.chartSeries = series
                }
            } catch {
                // Non-critical
            }
        }
    }
}

// MARK: - Demand Chart

struct DemandChart: View {
    let series: ChartSeries?

    var body: some View {
        if let series, series.points.count > 1 {
            let demands = series.points.map(\.watts)
            let maxD = demands.max() ?? 0
            let minD = demands.min() ?? 0
            let rawRange = maxD - minD
            let scaleMin = max(0, minD - rawRange * 0.1)
            let scaleMax = maxD + rawRange * 0.1
            let range = max(scaleMax - scaleMin, 100)

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
                        let segments = Self.segments(series, width: w) { watts in
                            h - CGFloat((watts - scaleMin) / range) * h
                        }

                        ForEach(0..<3) { i in
                            let y = h * CGFloat(i) / 2.0
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        }

                        Path { path in
                            for segment in segments where segment.count > 1 {
                                path.move(to: CGPoint(x: segment[0].x, y: h))
                                segment.forEach { path.addLine(to: $0) }
                                path.addLine(to: CGPoint(x: segment[segment.count - 1].x, y: h))
                                path.closeSubpath()
                            }
                        }
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        Path { path in
                            for segment in segments {
                                guard let first = segment.first else { continue }
                                path.move(to: first)
                                segment.dropFirst().forEach { path.addLine(to: $0) }
                            }
                        }
                        .stroke(
                            LinearGradient(colors: [.green, .yellow, .orange, .red], startPoint: .bottom, endPoint: .top),
                            style: StrokeStyle(lineWidth: series.points.count > 120 ? 1.25 : 2, lineCap: .round, lineJoin: .round)
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

    /// Screen points for the line, split wherever the data has a gap. Dense data
    /// is reduced to the lowest and highest reading per pixel column (in time
    /// order), so zooming out shrinks the detail rather than averaging it away —
    /// a 2-minute kettle spike still shows on the 24h chart.
    static func segments(_ series: ChartSeries, width: CGFloat, y: (Double) -> CGFloat) -> [[CGPoint]] {
        let span = series.end.timeIntervalSince(series.start)
        guard span > 0, width > 0 else { return [] }
        func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(series.start) / span) * width }
        let gap = series.bucket * 4

        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []
        var column: Int?
        var low: ChartPoint?
        var high: ChartPoint?
        var previous: Date?

        func flush() {
            guard let low, let high else { return }
            let ordered = low.date <= high.date ? [low, high] : [high, low]
            for p in ordered where current.last?.x != x(p.date) || current.last?.y != y(p.watts) {
                current.append(CGPoint(x: x(p.date), y: y(p.watts)))
            }
        }

        // Readings can sit a moment outside the window (Kraken's bucket
        // boundaries vs. our fetch time); they'd plot off the edge anyway.
        for point in series.points where point.date >= series.start && point.date <= series.end {
            if let previous, point.date.timeIntervalSince(previous) > gap {
                flush(); low = nil; high = nil
                if !current.isEmpty { segments.append(current) }
                current = []
                column = nil
            }
            previous = point.date
            let col = Int(x(point.date).rounded(.down))
            if col == column, let lo = low, let hi = high {
                if point.watts < lo.watts { low = point }
                if point.watts > hi.watts { high = point }
            } else {
                flush()
                column = col
                low = point
                high = point
            }
        }
        flush()
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}

// MARK: - Helpers

#Preview {
    NavigationStack {
        LiveView()
    }
}
