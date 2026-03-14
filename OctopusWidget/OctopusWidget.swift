import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct OctopusTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> OctopusEntry {
        OctopusEntry(date: Date(), data: .placeholder, error: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (OctopusEntry) -> Void) {
        if context.isPreview {
            completion(OctopusEntry(date: Date(), data: .placeholder, error: nil))
            return
        }
        fetchEntry(completion: completion)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OctopusEntry>) -> Void) {
        fetchEntry { entry in
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchEntry(completion: @escaping (OctopusEntry) -> Void) {
        guard SharedConfig.isConfigured else {
            completion(OctopusEntry(date: Date(), data: nil, error: "Open app to configure"))
            return
        }

        Task {
            do {
                let data = try await OctopusAPI.shared.fetchAll()
                completion(OctopusEntry(date: Date(), data: data, error: nil))
            } catch {
                completion(OctopusEntry(date: Date(), data: nil, error: error.localizedDescription))
            }
        }
    }
}

// MARK: - Timeline Entry

struct OctopusEntry: TimelineEntry {
    let date: Date
    let data: LiveData?
    let error: String?
}

// MARK: - Widget Helpers

func widgetDemandColor(_ watts: Double) -> Color {
    switch watts {
    case ..<500: return .green
    case ..<1500: return Color(red: 0.3, green: 0.69, blue: 0.31)
    case ..<3000: return .orange
    default: return .red
    }
}

func widgetTimeString(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

// MARK: - Small Widget

struct OctopusWidgetSmallView: View {
    let entry: OctopusEntry

    var body: some View {
        if let data = entry.data {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(widgetDemandColor(data.currentDemandWatts))
                    Spacer()
                    // Interactive refresh button
                    Button(intent: RefreshEnergyIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(formatWatts(data.currentDemandWatts))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(widgetDemandColor(data.currentDemandWatts))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("avg \(formatWatts(data.averageDemandWatts))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Text(String(format: "%.1f kWh today", data.todayKWh))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(widgetTimeString(data.timestamp))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
            .containerBackground(for: .widget) {
                Color(red: 0.06, green: 0.06, blue: 0.12)
            }
        } else {
            notConfiguredView(error: entry.error)
        }
    }
}

// MARK: - Medium Widget

struct OctopusWidgetMediumView: View {
    let entry: OctopusEntry

    var body: some View {
        if let data = entry.data {
            HStack(spacing: 16) {
                // Left: live demand
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(widgetDemandColor(data.currentDemandWatts))
                        Spacer()
                        Button(intent: RefreshEnergyIntent()) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text(formatWatts(data.currentDemandWatts))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(widgetDemandColor(data.currentDemandWatts))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text("5m avg \(formatWatts(data.averageDemandWatts))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                // Right: today + time
                VStack(alignment: .leading, spacing: 12) {
                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f kWh", data.todayKWh))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Text(widgetTimeString(data.timestamp))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.6))
                }

                Spacer()
            }
            .containerBackground(for: .widget) {
                Color(red: 0.06, green: 0.06, blue: 0.12)
            }
        } else {
            notConfiguredView(error: entry.error)
        }
    }
}

// MARK: - Large Widget

struct OctopusWidgetLargeView: View {
    let entry: OctopusEntry

    var body: some View {
        if let data = entry.data {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(widgetDemandColor(data.currentDemandWatts))
                    Spacer()
                    Button(intent: RefreshEnergyIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text(formatWatts(data.currentDemandWatts))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(widgetDemandColor(data.currentDemandWatts))
                    .minimumScaleFactor(0.5)

                Text("5m avg \(formatWatts(data.averageDemandWatts))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                // Mini spark chart from recent readings
                if data.readings.count > 1 {
                    miniChart(data.readings)
                }

                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f kWh", data.todayKWh))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(widgetTimeString(data.timestamp))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
            .containerBackground(for: .widget) {
                Color(red: 0.06, green: 0.06, blue: 0.12)
            }
        } else {
            notConfiguredView(error: entry.error)
        }
    }

    private func miniChart(_ readings: [TelemetryReading]) -> some View {
        let demands = readings.map(\.demandWatts)
        let maxD = demands.max() ?? 1
        let minD = demands.min() ?? 0
        let range = max(maxD - minD, 100)

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stepX = w / CGFloat(readings.count - 1)

            Path { path in
                for (i, r) in readings.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = h - ((CGFloat(r.demandWatts - minD) / CGFloat(range)) * h)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(
                LinearGradient(colors: [.green, .yellow, .orange, .red], startPoint: .bottom, endPoint: .top),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )

            Path { path in
                for (i, r) in readings.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = h - ((CGFloat(r.demandWatts - minD) / CGFloat(range)) * h)
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
        }
        .frame(height: 80)
    }
}

// MARK: - Lock Screen: Circular

struct OctopusAccessoryCircularView: View {
    let entry: OctopusEntry

    var body: some View {
        if let data = entry.data {
            Gauge(value: min(data.currentDemandWatts, 10000), in: 0...10000) {
                Image(systemName: "bolt.fill")
            } currentValueLabel: {
                Text(compactWatts(data.currentDemandWatts))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Image(systemName: "bolt.slash")
        }
    }

    private func compactWatts(_ w: Double) -> String {
        if w >= 1000 {
            return String(format: "%.1fk", w / 1000)
        }
        return "\(Int(w))"
    }
}

// MARK: - Lock Screen: Rectangular

struct OctopusAccessoryRectangularView: View {
    let entry: OctopusEntry

    var body: some View {
        if let data = entry.data {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                }

                Text(formatWatts(data.currentDemandWatts))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)

                Text("avg \(formatWatts(data.averageDemandWatts))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 9))
                    Text("Not configured")
                        .font(.system(size: 10))
                }
            }
        }
    }
}

// MARK: - Lock Screen: Inline

struct OctopusAccessoryInlineView: View {
    let entry: OctopusEntry

    var body: some View {
        if let data = entry.data {
            Label(formatWatts(data.currentDemandWatts), systemImage: "bolt.fill")
        } else {
            Label("--", systemImage: "bolt.slash")
        }
    }
}

// MARK: - Not Configured

@ViewBuilder
func notConfiguredView(error: String?) -> some View {
    VStack(spacing: 8) {
        Image(systemName: "bolt.slash.fill")
            .font(.title2)
            .foregroundStyle(.yellow.opacity(0.5))
        Text(error ?? "Open app to set up")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
    .containerBackground(for: .widget) {
        Color(red: 0.06, green: 0.06, blue: 0.12)
    }
}

// MARK: - Entry View Router

struct OctopusWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: OctopusEntry

    var body: some View {
        switch family {
        case .systemSmall:
            OctopusWidgetSmallView(entry: entry)
        case .systemMedium:
            OctopusWidgetMediumView(entry: entry)
        case .systemLarge:
            OctopusWidgetLargeView(entry: entry)
        case .accessoryCircular:
            OctopusAccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            OctopusAccessoryRectangularView(entry: entry)
        case .accessoryInline:
            OctopusAccessoryInlineView(entry: entry)
        default:
            OctopusWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Definition

struct OctopusWidget: Widget {
    let kind = "OctopusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OctopusTimelineProvider()) { entry in
            OctopusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Octopus Live")
        .description("Live electricity usage from your Octopus Home Mini")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    OctopusWidget()
} timeline: {
    OctopusEntry(date: Date(), data: .placeholder, error: nil)
}

#Preview("Medium", as: .systemMedium) {
    OctopusWidget()
} timeline: {
    OctopusEntry(date: Date(), data: .placeholder, error: nil)
}

#Preview("Large", as: .systemLarge) {
    OctopusWidget()
} timeline: {
    OctopusEntry(date: Date(), data: .placeholder, error: nil)
}

#Preview("Lock Circular", as: .accessoryCircular) {
    OctopusWidget()
} timeline: {
    OctopusEntry(date: Date(), data: .placeholder, error: nil)
}

#Preview("Lock Rectangular", as: .accessoryRectangular) {
    OctopusWidget()
} timeline: {
    OctopusEntry(date: Date(), data: .placeholder, error: nil)
}

#Preview("Not Configured", as: .systemSmall) {
    OctopusWidget()
} timeline: {
    OctopusEntry(date: Date(), data: nil, error: "Open app to configure")
}
