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

enum GlanceMetric: String, AppEnum {
    case safeToSpend, spent, netWorth

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Number"
    static let caseDisplayRepresentations: [GlanceMetric: DisplayRepresentation] = [
        .safeToSpend: "Safe to spend",
        .spent: "Spent this month",
        .netWorth: "Net worth",
    ]
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
        if context.isPreview, cachedSummary() == nil {
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
        guard let token = Keychain.read(account: Keychain.tokenAccount) else {
            return GlanceEntry(date: .now, metric: configuration.metric, state: .signedOut)
        }
        switch await fetchToday(token: token) {
        case .success(let summary):
            return GlanceEntry(date: .now, metric: configuration.metric, state: .ready(summary))
        case .signedOut:
            return GlanceEntry(date: .now, metric: configuration.metric, state: .signedOut)
        case .failed:
            // Offline or the server's slow: show the last numbers the app
            // or a previous refresh saved, rather than nothing.
            if let cached = cachedSummary() {
                return GlanceEntry(date: .now, metric: configuration.metric, state: .ready(cached))
            }
            return GlanceEntry(date: .now, metric: configuration.metric, state: .unavailable)
        }
    }

    private enum FetchResult { case success(TodaySummary), signedOut, failed }

    private func fetchToday(token: String) async -> FetchResult {
        var request = URLRequest(url: WidgetStore.baseURL.appending(path: "today"))
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failed }
        if status == 401 { return .signedOut }
        guard status == 200, let summary = Self.decode(data) else { return .failed }
        WidgetStore.saveToday(data)
        return .success(summary)
    }

    private func cachedSummary() -> TodaySummary? {
        WidgetStore.loadToday().flatMap(Self.decode)
    }

    private static func decode(_ data: Data) -> TodaySummary? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(TodaySummary.self, from: data)
    }
}
