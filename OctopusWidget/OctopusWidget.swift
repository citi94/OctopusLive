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
            // Request next refresh in 5 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
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
                let data = try await OctopusAPI.shared.fetchWidgetData()
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
    let data: WidgetData?
    let error: String?
}

// MARK: - Widget Views

struct OctopusWidgetSmallView: View {
    let entry: OctopusEntry

    var body: some View {
        if let data = entry.data {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(demandColor(data.currentDemandWatts))
                    Spacer()
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow.opacity(0.6))
                }

                Spacer()

                Text(data.currentDemandFormatted)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(demandColor(data.currentDemandWatts))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("avg \(data.averageDemandFormatted)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Text(data.todayKWhFormatted)
                    Spacer()
                    Text(data.todayCostFormatted)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) {
                Color(red: 0.06, green: 0.06, blue: 0.12)
            }
        } else {
            notConfiguredView(error: entry.error)
        }
    }
}

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
                            .foregroundStyle(demandColor(data.currentDemandWatts))
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow.opacity(0.6))
                    }

                    Spacer()

                    Text(data.currentDemandFormatted)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(demandColor(data.currentDemandWatts))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text("5m avg \(data.averageDemandFormatted)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                // Right: today stats
                VStack(alignment: .leading, spacing: 12) {
                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        Text(data.todayKWhFormatted)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("EST. COST")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        Text(data.todayCostFormatted)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Text(timeString(data.timestamp))
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

// MARK: - Shared Helpers

private func demandColor(_ watts: Double) -> Color {
    switch watts {
    case ..<500: return .green
    case ..<1500: return Color(red: 0.3, green: 0.69, blue: 0.31)
    case ..<3000: return .orange
    default: return .red
    }
}

private func timeString(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return "Updated \(f.string(from: date))"
}

@ViewBuilder
private func notConfiguredView(error: String?) -> some View {
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

// MARK: - Widget Definition

struct OctopusWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: OctopusEntry

    var body: some View {
        switch family {
        case .systemSmall:
            OctopusWidgetSmallView(entry: entry)
        default:
            OctopusWidgetMediumView(entry: entry)
        }
    }
}

struct OctopusWidget: Widget {
    let kind = "OctopusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OctopusTimelineProvider()) { entry in
            OctopusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Octopus Live")
        .description("Live electricity usage from your Octopus Home Mini")
        .supportedFamilies([.systemSmall, .systemMedium])
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

#Preview("Not Configured", as: .systemSmall) {
    OctopusWidget()
} timeline: {
    OctopusEntry(date: Date(), data: nil, error: "Open app to configure")
}
