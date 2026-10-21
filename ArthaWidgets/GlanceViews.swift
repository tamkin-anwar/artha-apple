import Charts
import SwiftUI
import WidgetKit

/// The numbers a widget shows, worked out from the server's /today for the
/// moment the widget draws. A widget can still be on screen the next
/// morning, so "a day for N days" is recounted from the entry's own date.
struct Glance {
    enum Status { case onPace, ahead, over }

    let summary: TodaySummary
    let metric: GlanceMetric
    let date: Date

    var code: String { summary.currency }
    var hasBudget: Bool { summary.safeToSpend != nil }

    /// Falls back to spent this month when there's no budget yet, and when
    /// net worth was picked but there are no accounts.
    var effectiveMetric: GlanceMetric {
        switch metric {
        case .safeToSpend where !hasBudget: .spent
        case .netWorth where summary.netWorth == nil: hasBudget ? .safeToSpend : .spent
        default: metric
        }
    }

    var daysLeft: Int {
        let calendar = Calendar.current
        guard let serverDay = Date.apiDay(summary.date),
              calendar.isDate(date, equalTo: serverDay, toGranularity: .month) else { return summary.month.daysLeft }
        let day = calendar.component(.day, from: date)
        return max(1, summary.month.daysInMonth - max(day, summary.month.day) + 1)
    }

    var safe: Decimal { max(0, Decimal.api(summary.safeToSpend?.amount)) }
    var perDay: Decimal { (safe / Decimal(daysLeft)).rounded(0, .down) }
    var spent: Decimal { Decimal.api(summary.spent) }
    var cap: Decimal? { summary.budget.map { Decimal.api($0.cap) } }
    var netWorth: Decimal { Decimal.api(summary.netWorth?.amount) }
    var overBy: Decimal { Decimal.api(summary.safeToSpend?.overBy) }

    var status: Status {
        switch summary.safeToSpend?.status {
        case "over": .over
        case "ahead": .ahead
        default: .onPace
        }
    }

    var label: String {
        switch effectiveMetric {
        case .safeToSpend: "Safe to spend"
        case .spent: "Spent in \(summary.month.name)"
        case .netWorth: "Net worth"
        }
    }

    var value: Decimal {
        switch effectiveMetric {
        case .safeToSpend: safe
        case .spent: spent
        case .netWorth: netWorth
        }
    }

    var detail: String {
        switch effectiveMetric {
        case .safeToSpend:
            if status == .over { return "Over by \(Money.whole(overBy, code))" }
            return "\(Money.whole(perDay, code)) a day for \(daysLeft) \(daysLeft == 1 ? "day" : "days")"
        case .spent:
            if let cap { return "of \(Money.whole(cap, code)) budget" }
            return "so far this month"
        case .netWorth:
            let count = summary.netWorth?.accountCount ?? 0
            return "across \(count) \(count == 1 ? "account" : "accounts")"
        }
    }

    var statusText: String? {
        guard hasBudget, effectiveMetric != .netWorth else { return nil }
        switch status {
        case .onPace: return "On pace"
        case .ahead: return "Ahead of pace"
        case .over: return "Over budget"
        }
    }

    var statusColor: Color {
        status == .onPace ? Palette.good : Palette.caution
    }

    var lineColor: Color {
        !hasBudget || status == .onPace ? Palette.accent : Palette.cautionLine
    }

    struct Point: Identifiable {
        let day: Int
        let amount: Double
        var id: Int { day }
    }

    var points: [Point] {
        summary.spendingByDay.map { Point(day: $0.day, amount: (Decimal.api($0.spent) as NSDecimalNumber).doubleValue) }
    }

    var paceTop: Double? { cap.map { ($0 as NSDecimalNumber).doubleValue } }
}

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
                AccessoryWidgetBackground().opacity(family == .accessoryCircular ? 1 : 0)
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
        case .accessoryCircular: CircularGlance(glance: glance)
        case .accessoryRectangular: RectangularGlance(glance: glance)
        case .accessoryInline: Text("\(Money.whole(glance.value, glance.code)) \(glance.label.lowercased())")
        default: SmallGlance(glance: glance)
        }
    }
}

private extension WidgetFamily {
    var isAccessory: Bool {
        self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline
    }
}

// MARK: - Home Screen

private struct Header: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            OrbMark().frame(width: 14, height: 14)
            Text(text.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct BigNumber: View {
    let glance: Glance
    var size: CGFloat = 36

    var body: some View {
        Text(Money.whole(glance.value, glance.code))
            .font(.figure(size))
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .contentTransition(.numericText(value: (glance.value as NSDecimalNumber).doubleValue))
            .widgetAccentable()
    }
}

private struct StatusLine: View {
    let glance: Glance

    var body: some View {
        if let text = glance.statusText {
            HStack(spacing: 5) {
                Circle().fill(glance.statusColor).frame(width: 7, height: 7)
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(glance.statusColor)
            }
        }
    }
}

private struct SmallGlance: View {
    let glance: Glance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(text: glance.label)
            Spacer(minLength: 4)
            BigNumber(glance: glance, size: 38)
            Text(glance.detail)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.top, 2)
            Spacer(minLength: 4)
            StatusLine(glance: glance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

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

/// The month so far against an even pace, small enough for a widget.
private struct MiniPace: View {
    let glance: Glance

    var body: some View {
        let days = glance.summary.month.daysInMonth
        let top = max(glance.paceTop ?? 0, glance.points.map(\.amount).max() ?? 0, 1) * 1.08
        Chart {
            if let pace = glance.paceTop {
                ForEach([1, days], id: \.self) { day in
                    LineMark(x: .value("Day", day), y: .value("Amount", pace * Double(day) / Double(days)),
                             series: .value("Line", "Pace"))
                        .foregroundStyle(Palette.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            ForEach(glance.points) { point in
                AreaMark(x: .value("Day", point.day), y: .value("Amount", point.amount))
                    .foregroundStyle(LinearGradient(colors: [glance.lineColor.opacity(0.28), glance.lineColor.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", point.day), y: .value("Amount", point.amount),
                         series: .value("Line", "Spent"))
                    .foregroundStyle(glance.lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .widgetAccentable()
        .chartXScale(domain: 1...days)
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}

private struct LargeGlance: View {
    let glance: Glance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Header(text: glance.label)
                    BigNumber(glance: glance, size: 44).padding(.top, 6)
                    Text(glance.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                AddButton()
            }
            StatusLine(glance: glance).padding(.top, 8)
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
        if family == .accessoryInline {
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
