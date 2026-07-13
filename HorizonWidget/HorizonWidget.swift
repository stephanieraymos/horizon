import WidgetKit
import SwiftUI

private let brand = Color(red: 0.200, green: 0.549, blue: 0.722)

// MARK: - Countdown widget (home / lock screen)

struct TripEntry: TimelineEntry {
    let date: Date
    let snapshot: TripWidgetSnapshot
}

struct TripProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripEntry {
        TripEntry(date: Date(), snapshot: .preview)
    }
    func getSnapshot(in context: Context, completion: @escaping (TripEntry) -> Void) {
        completion(TripEntry(date: Date(), snapshot: TripWidgetSnapshot.load() ?? .preview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TripEntry>) -> Void) {
        let snapshot = TripWidgetSnapshot.load() ?? .empty
        let entry = TripEntry(date: Date(), snapshot: snapshot)
        // Refresh at the next local midnight so the day count stays correct.
        let nextMidnight = Calendar.current.nextDate(after: Date(),
            matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct TripCountdownView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TripEntry

    private var snap: TripWidgetSnapshot { entry.snapshot }

    var body: some View {
        if let name = snap.tripName {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 2 : 6) {
                HStack(spacing: 4) {
                    Image(systemName: "airplane.departure").font(.caption2)
                    Text("Next trip").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(brand)

                Spacer(minLength: 0)

                Text(snap.countdownText)
                    .font(.system(size: family == .systemSmall ? 30 : 40, weight: .bold, design: .rounded))
                    .foregroundStyle(snap.isSomeday ? Color.purple : brand)
                    .minimumScaleFactor(0.6).lineLimit(1)

                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let dest = snap.destination {
                    Text(dest).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "map").font(.title2).foregroundStyle(brand)
                Text("No upcoming trips").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct TripCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TripCountdownWidget", provider: TripProvider()) { entry in
            TripCountdownView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Trip")
        .description("Countdown to your next adventure.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Live Activity (iPhone only)

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            // Lock Screen / banner
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.tripName).font(.headline).lineLimit(1)
                    if let dest = context.attributes.destination {
                        Text(dest).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Text(context.state.departDate, style: .relative)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(brand)
                    .multilineTextAlignment(.trailing)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.tripName, systemImage: "airplane.departure")
                        .font(.caption).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.departDate, style: .relative)
                        .font(.caption.bold().monospacedDigit()).foregroundStyle(brand)
                }
            } compactLeading: {
                Image(systemName: "airplane.departure").foregroundStyle(brand)
            } compactTrailing: {
                Text(context.state.departDate, style: .relative)
                    .monospacedDigit().foregroundStyle(brand)
            } minimal: {
                Image(systemName: "airplane.departure").foregroundStyle(brand)
            }
        }
    }
}
#endif

// MARK: - Bundle

@main
struct HorizonWidgetBundle: WidgetBundle {
    var body: some Widget {
        TripCountdownWidget()
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        TripLiveActivity()
        #endif
    }
}
