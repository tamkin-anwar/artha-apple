import AppIntents
import Foundation
import SwiftUI

// What a widget and the Check Safe to Spend action both show, so the
// Home Screen, the desktop, Siri and Shortcuts can never disagree.

enum GlanceMetric: String, AppEnum {
    case safeToSpend, spent, netWorth

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Number"
    static let caseDisplayRepresentations: [GlanceMetric: DisplayRepresentation] = [
        .safeToSpend: "Safe to spend",
        .spent: "Spent this month",
        .netWorth: "Net worth",
    ]
}

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

/// The signed-in device's numbers from the server's /today, fetched with
/// the token the app keeps in the shared Keychain group. Offline, or with
/// the server slow, it falls back to the last numbers the app or a widget
/// saved (`fresh` is false then).
enum TodayNumbers {
    enum Result {
        case ready(TodaySummary, fresh: Bool)
        case signedOut
        case unavailable
    }

    static func load() async -> Result {
        guard let token = Keychain.read(account: Keychain.tokenAccount) else { return .signedOut }
        var request = URLRequest(url: WidgetStore.baseURL.appending(path: "today"))
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let status = (response as? HTTPURLResponse)?.statusCode {
            if status == 401 { return .signedOut }
            if status == 200, let summary = decode(data) {
                WidgetStore.saveToday(data)
                return .ready(summary, fresh: true)
            }
        }
        if let cached = cached() { return .ready(cached, fresh: false) }
        return .unavailable
    }

    static func cached() -> TodaySummary? {
        WidgetStore.loadToday().flatMap(decode)
    }

    private static func decode(_ data: Data) -> TodaySummary? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(TodaySummary.self, from: data)
    }
}
