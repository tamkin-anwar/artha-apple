import AppIntents
import SwiftUI
import WidgetKit

/// Safe to Spend (or spent this month, or net worth) at a glance, on the
/// Home Screen, the Lock Screen and in StandBy. The number each person
/// leads with is theirs to pick, the same choice Today offers.
struct GlanceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetStore.glanceKind, intent: GlanceConfiguration.self, provider: GlanceProvider()) { entry in
            GlanceView(entry: entry)
        }
        .configurationDisplayName("Safe to Spend")
        .description("What's safe to spend today, how the month is pacing, and what's coming up. Or pick spent this month or net worth.")
        .supportedFamilies(Self.families)
    }

    /// Desktop sizes on a Mac; the Lock Screen and StandBy ones too on
    /// iPhone and iPad.
    private static var families: [WidgetFamily] {
        #if os(macOS)
        [.systemSmall, .systemMedium, .systemLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

struct GlanceConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Artha at a glance"
    static let description = IntentDescription("Choose the number this widget leads with.")

    @Parameter(title: "Show", default: .safeToSpend)
    var metric: GlanceMetric
}

struct GlanceEntry: TimelineEntry {
    enum State { case ready(TodaySummary), signedOut, unavailable }

    let date: Date
    let metric: GlanceMetric
    let state: State
}

struct GlanceProvider: AppIntentTimelineProvider {
    /// How often a widget asks for fresh numbers on its own. The app also
    /// pushes an update the moment anything changes (an add, an edit, an
    /// Apple Pay purchase), so this only matters on quiet days.
    static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: .now, metric: .safeToSpend, state: .ready(.sample))
    }

    func snapshot(for configuration: GlanceConfiguration, in context: Context) async -> GlanceEntry {
        if context.isPreview, TodayNumbers.cached() == nil {
            return GlanceEntry(date: .now, metric: configuration.metric, state: .ready(.sample))
        }
        return await entry(for: configuration)
    }

    func timeline(for configuration: GlanceConfiguration, in context: Context) async -> Timeline<GlanceEntry> {
        let entry = await entry(for: configuration)
        let next = Date.now.addingTimeInterval(Self.refreshInterval)
        // Also redraw just after midnight, when "a day for N days" changes
        // even if no money moved.
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1),
                                                 matchingPolicy: .nextTime) ?? next
        var entries = [entry]
        if midnight < next, case .ready = entry.state {
            entries.append(GlanceEntry(date: midnight, metric: entry.metric, state: entry.state))
        }
        return Timeline(entries: entries, policy: .after(min(next, midnight.addingTimeInterval(60))))
    }

    private func entry(for configuration: GlanceConfiguration) async -> GlanceEntry {
        switch await TodayNumbers.load() {
        case .ready(let summary, _):
            GlanceEntry(date: .now, metric: configuration.metric, state: .ready(summary))
        case .signedOut:
            GlanceEntry(date: .now, metric: configuration.metric, state: .signedOut)
        case .unavailable:
            GlanceEntry(date: .now, metric: configuration.metric, state: .unavailable)
        }
    }
}
