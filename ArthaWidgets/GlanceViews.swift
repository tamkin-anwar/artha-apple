import Charts
import SwiftUI
import WidgetKit

// MARK: - Entry view

struct GlanceView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.state {
            case .ready(let summary):
                content(Glance(summary: summary, metric: entry.metric, date: entry.date))
            case .signedOut:
                Message(symbol: "person.crop.circle", text: "Sign in to Artha", family: family)
            case .unavailable:
                Message(symbol: "wifi.exclamationmark", text: "Open Artha to load your numbers", family: family)
            }
        }
        .containerBackground(for: .widget) {
            if family.isAccessory {
                #if os(iOS)
                AccessoryWidgetBackground().opacity(family == .accessoryCircular ? 1 : 0)
                #endif
            } else {
                Palette.surface
            }
        }
        .widgetURL(URL(string: "artha://today"))
    }

    @ViewBuilder
    private func content(_ glance: Glance) -> some View {
        switch family {
        case .systemSmall: SmallGlance(glance: glance)
        case .systemMedium: MediumGlance(glance: glance)
        case .systemLarge: LargeGlance(glance: glance)
        #if os(iOS)
        case .accessoryCircular: CircularGlance(glance: glance)
        case .accessoryRectangular: RectangularGlance(glance: glance)
        case .accessoryInline: Text("\(Money.whole(glance.value, glance.code)) \(glance.label.lowercased())")
        #endif
        default: SmallGlance(glance: glance)
        }
    }
}

// The Lock Screen sizes exist on iPhone and iPad only; a Mac has just the
// desktop ones.
private extension WidgetFamily {
    var isAccessory: Bool {
        #if os(iOS)
        self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline
        #else
        false
        #endif
    }

    var isInline: Bool {
        #if os(iOS)
        self == .accessoryInline
        #else
        false
        #endif
    }
}

// MARK: - Home Screen

private struct AddButton: View {
    var body: some View {
        Link(destination: URL(string: "artha://add")!) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Palette.raised, in: Circle())
                .foregroundStyle(Palette.ink)
                .widgetAccentable()
        }
        .accessibilityLabel("Add a purchase")
    }
}

private struct MediumGlance: View {
    let glance: Glance

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SmallGlance(glance: glance)
            VStack(alignment: .trailing, spacing: 8) {
                AddButton()
                if glance.effectiveMetric != .netWorth, glance.points.count > 1 {
                    MiniPace(glance: glance)
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LargeGlance: View {
    let glance: Glance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    GlanceHeader(text: glance.label)
                    GlanceNumber(glance: glance, size: 44).padding(.top, 6)
                    Text(glance.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                AddButton()
            }
            GlanceStatus(glance: glance).padding(.top, 8)
            if glance.effectiveMetric != .netWorth, glance.points.count > 1 {
                MiniPace(glance: glance)
                    .frame(height: 70)
                    .padding(.top, 10)
            }
            Spacer(minLength: 10)
            if glance.summary.comingUp.isEmpty {
                Text("No bills coming up")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
            } else {
                Text("COMING UP")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.secondary)
                ForEach(Array(glance.summary.comingUp.prefix(3).enumerated()), id: \.offset) { _, bill in
                    HStack {
                        Text(bill.description)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text(when(bill.daysAway))
                            .font(.system(size: 12))
                            .foregroundStyle(bill.daysAway <= 2 ? Palette.caution : Palette.secondary)
                        Text(Money.natural(Decimal.api(bill.amount), bill.currency))
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private func when(_ days: Int) -> String {
        switch days {
        case 0: "Today"
        case 1: "Tomorrow"
        default: "In \(days) days"
        }
    }
}

// MARK: - Lock Screen

private struct CircularGlance: View {
    let glance: Glance

    var body: some View {
        if glance.effectiveMetric == .netWorth || glance.cap == nil {
            VStack(spacing: 0) {
                Text(glance.effectiveMetric == .netWorth ? "NET" : "SPENT")
                    .font(.system(size: 9, weight: .bold))
                Text(Money.compact(glance.value, glance.code))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            }
        } else if let cap = glance.cap {
            // How much of the month's budget is still unspent, as a ring.
            let used = min((glance.spent as NSDecimalNumber).doubleValue, (cap as NSDecimalNumber).doubleValue)
            Gauge(value: used, in: 0...max((cap as NSDecimalNumber).doubleValue, 1)) {
                Text("Budget")
            } currentValueLabel: {
                Text(Money.compact(glance.effectiveMetric == .spent ? glance.spent : glance.safe, glance.code))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        }
    }
}

private struct RectangularGlance: View {
    let glance: Glance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(glance.label)
                .font(.system(size: 13, weight: .semibold))
                .widgetAccentable()
            Text(Money.whole(glance.value, glance.code))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text(glance.detail)
                .font(.system(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Not ready

private struct Message: View {
    let symbol: String
    let text: String
    let family: WidgetFamily

    var body: some View {
        if family.isInline {
            Text(text)
        } else if family.isAccessory {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                Text(text).font(.system(size: 11)).multilineTextAlignment(.center)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                OrbMark().frame(width: 26, height: 26)
                Spacer()
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Gallery sample

extension TodaySummary {
    /// What the widget gallery shows before anyone has signed in: realistic,
    /// clearly sample numbers.
    static let sample: TodaySummary = {
        var days: [String] = []
        var total = 0.0
        for day in 1...21 {
            total += day == 1 ? 1650 : Double((day * 37) % 90 + 12)
            days.append("{\"day\":\(day),\"spent\":\"\(String(format: "%.2f", total))\"}")
        }
        let json = """
        {"date":"2026-10-21","currency":"USD",
         "month":{"name":"October","start":"2026-10-01","end":"2026-10-31","day":21,"days_in_month":31,"days_left":11},
         "spent":"\(String(format: "%.2f", total))","income":"4200.00",
         "budget":{"cap":"3400.00","spent":"\(String(format: "%.2f", total))","percent_used":85.0,"tier":"ok"},
         "safe_to_spend":{"amount":"412.00","per_day":"37.45","bills_still_due":"112.00","over_by":"0.00","status":"on_pace","even_pace_spent":"2303.23"},
         "spending_by_day":[\(days.joined(separator: ","))],
         "categories":[],
         "coming_up":[{"description":"Spotify","amount":"11.99","currency":"USD","category":"subscriptions","due":"2026-10-22","days_away":1},
                      {"description":"Car insurance","amount":"112.00","currency":"USD","category":"debt","due":"2026-10-28","days_away":7}],
         "recent":[],
         "net_worth":{"amount":"154683.05","assets":"479880.93","liabilities":"325197.88","account_count":8}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(TodaySummary.self, from: Data(json.utf8))
    }()
}
