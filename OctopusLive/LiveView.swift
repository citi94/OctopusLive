import SwiftUI

struct LiveView: View {
    @State private var data: WidgetData?
    @State private var error: String?
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.12)
                .ignoresSafeArea()

            if let data = data {
                ScrollView {
                    VStack(spacing: 28) {
                        demandSection(data)
                        chartSection(data)
                        todaySection(data)
                        updatedLabel(data)
                    }
                    .padding()
                }
            } else if let error = error {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ProgressView("Loading...")
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle("Octopus Live")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Demand

    private func demandSection(_ data: WidgetData) -> some View {
        VStack(spacing: 8) {
            Text("LIVE")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(3)
                .foregroundStyle(demandColor(data.currentDemandWatts))

            Text(data.currentDemandFormatted)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(demandColor(data.currentDemandWatts))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: data.currentDemandWatts)

            HStack(spacing: 16) {
                Label("5m avg \(data.averageDemandFormatted)", systemImage: "chart.line.flattrend.xyaxis")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    // MARK: - Chart

    private func chartSection(_ data: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent demand")
                .font(.caption)
                .foregroundStyle(.secondary)

            DemandChart(readings: data.readings)
                .frame(height: 140)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Today

    private func todaySection(_ data: WidgetData) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(data.todayKWhFormatted)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("used today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.1))

            VStack(spacing: 4) {
                Text(data.todayCostFormatted)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("est. cost")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Updated

    private func updatedLabel(_ data: WidgetData) -> some View {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return Text("Updated \(f.string(from: data.timestamp))")
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.6))
    }

    // MARK: - Helpers

    private func demandColor(_ watts: Double) -> Color {
        switch watts {
        case ..<500: return .green
        case ..<1500: return Color(red: 0.3, green: 0.69, blue: 0.31)
        case ..<3000: return .orange
        default: return .red
        }
    }

    // MARK: - Polling

    private func startPolling() {
        fetchData()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            fetchData()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func fetchData() {
        Task {
            do {
                let result = try await OctopusAPI.shared.fetchWidgetData()
                await MainActor.run {
                    self.data = result
                    self.error = nil
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Demand Chart

struct DemandChart: View {
    let readings: [TelemetryReading]

    var body: some View {
        let points = Array(readings.suffix(30))
        let demands = points.map(\.demandWatts)
        let maxD = demands.max() ?? 1
        let minD = demands.min() ?? 0
        let range = max(maxD - minD, 1)

        if points.count > 1 {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let stepX = w / CGFloat(points.count - 1)

                // Line
                Path { path in
                    for (i, r) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = h - ((CGFloat(r.demandWatts - minD) / CGFloat(range)) * h)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(
                    LinearGradient(colors: [.green, .yellow, .orange, .red], startPoint: .bottom, endPoint: .top),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                // Fill
                Path { path in
                    for (i, r) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = h - ((CGFloat(r.demandWatts - minD) / CGFloat(range)) * h)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: h))
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: CGFloat(points.count - 1) * stepX, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.25), Color.orange.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        } else {
            Text("Waiting for data...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    NavigationStack {
        LiveView()
    }
}
