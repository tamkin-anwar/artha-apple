import Foundation
import Observation

/// Today's month, shaped for the screens. Every figure comes from the
/// server's /api/v1/today (the same code the web Dashboard runs), so the
/// app never does its own budget math; this only reshapes it for display.
@Observable
final class MonthModel {
    enum HeroMetric: String, CaseIterable, Identifiable {
        case safeToSpend = "Safe to spend"
        case spentThisMonth = "Spent this month"
        case netWorth = "Net worth"
        var id: String { rawValue }
    }

    enum Status { case onPace, ahead, over }

    struct Bill: Identifiable {
        let id: String
        let name: String
        let label: String
        let date: String
        let amount: Decimal
        let currencyCode: String
        let isSoon: Bool
    }

    struct Expense: Identifiable {
        let id: Int
        let merchant: String
        let detail: String
        let symbol: String
        let amount: Decimal
        let currencyCode: String
        /// Only for a transaction in another currency: its equivalent in
        /// the display currency, shown beside the real amount.
        let displayEquivalent: Decimal?
    }

    struct DayPoint: Identifiable {
        let day: Int
        let amount: Double
        var id: Int { day }
    }

    struct Share: Identifiable {
        let id: String
        let amount: Decimal
        var name: String { id }
    }

    private(set) var summary: TodaySummary?
    var heroMetric: HeroMetric = .safeToSpend
    /// Bumps on every add so Today can play one success haptic.
    private(set) var addCount = 0

    func apply(_ summary: TodaySummary) {
        self.summary = summary
        if !availableMetrics.contains(heroMetric) {
            heroMetric = availableMetrics.first ?? .spentThisMonth
        }
    }

    func clear() {
        summary = nil
        heroMetric = .safeToSpend
    }

    func noteAdded() { addCount += 1 }

    // MARK: Basics

    var currencyCode: String { summary?.currency ?? "USD" }
    var hasBudget: Bool { summary?.safeToSpend != nil }
    var today: Int { summary?.month.day ?? 1 }
    var daysInMonth: Int { summary?.month.daysInMonth ?? 30 }
    var daysLeft: Int { summary?.month.daysLeft ?? 1 }
    var monthName: String { summary?.month.name ?? "" }
    var nextMonthName: String {
        guard let end = Date.apiDay(summary?.month.end),
              let next = Calendar.current.date(byAdding: .day, value: 1, to: end) else { return "Next month" }
        return next.formatted(.dateTime.month(.wide))
    }

    /// A brand-new account: no budget yet and nothing recorded.
    var isEmpty: Bool {
        guard let summary else { return true }
        return summary.safeToSpend == nil && summary.recent.isEmpty && Decimal.api(summary.spent) == 0
    }

    var headerDate: String {
        guard let date = Date.apiDay(summary?.date) else { return "" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }

    // MARK: Money

    var spent: Decimal { Decimal.api(summary?.spent) }
    var budget: Decimal? { summary?.budget.map { Decimal.api($0.cap) } }
    var safeToSpend: Decimal { max(0, Decimal.api(summary?.safeToSpend?.amount)) }
    var overBy: Decimal { Decimal.api(summary?.safeToSpend?.overBy) }
    /// Rounded down to whole units: a daily allowance should never promise
    /// more than is actually safe ($109.83 reads as $109, not $110).
    var perDay: Decimal { Decimal.api(summary?.safeToSpend?.perDay).rounded(0, .down) }
    var netWorth: Decimal? { summary?.netWorth.map { Decimal.api($0.amount) } }
    var accountCount: Int { summary?.netWorth?.accountCount ?? 0 }

    var status: Status {
        switch summary?.safeToSpend?.status {
        case "over": .over
        case "ahead": .ahead
        default: .onPace
        }
    }

    var availableMetrics: [HeroMetric] {
        var metrics: [HeroMetric] = []
        if hasBudget { metrics.append(.safeToSpend) }
        metrics.append(.spentThisMonth)
        if netWorth != nil { metrics.append(.netWorth) }
        return metrics
    }

    var heroValue: Decimal {
        switch heroMetric {
        case .safeToSpend: safeToSpend
        case .spentThisMonth: spent
        case .netWorth: netWorth ?? 0
        }
    }

    // MARK: Chart

    var cumulative: [DayPoint] {
        (summary?.spendingByDay ?? []).map {
            DayPoint(day: $0.day, amount: (Decimal.api($0.spent) as NSDecimalNumber).doubleValue)
        }
    }

    func amount(on day: Int) -> Double? {
        cumulative.first { $0.day == day }?.amount
    }

    /// An even pace to the budget through the end of `day`, the same line
    /// the server's "ahead of pace" status is measured against.
    func paceAmount(on day: Int) -> Double? {
        guard let budget else { return nil }
        return (budget as NSDecimalNumber).doubleValue * Double(day) / Double(daysInMonth)
    }

    // MARK: Sections

    /// The top three categories by spending, plus everything else.
    var shares: [Share] {
        let categories = (summary?.categories ?? []).map { (label: $0.label, amount: Decimal.api($0.amount)) }
        guard categories.count > 4 else {
            return categories.map { Share(id: $0.label, amount: $0.amount) }
        }
        let top = categories.prefix(3).map { Share(id: $0.label, amount: $0.amount) }
        let rest = categories.dropFirst(3).reduce(Decimal(0)) { $0 + $1.amount }
        return top + [Share(id: "Everything else", amount: rest)]
    }

    var bills: [Bill] {
        guard let summary, let today = Date.apiDay(summary.date) else { return [] }
        let calendar = Calendar.current
        return summary.comingUp.prefix(3).compactMap { bill in
            guard let due = Date.apiDay(bill.due) else { return nil }
            let sameMonth = calendar.isDate(due, equalTo: today, toGranularity: .month)
            let weekday = due.formatted(.dateTime.weekday(.abbreviated)).uppercased()
            let label: String
            switch bill.daysAway {
            case 0: label = "TODAY"
            case 1: label = "TOMORROW"
            case 2...6 where sameMonth: label = "\(weekday) · \(bill.daysAway) DAYS"
            default: label = sameMonth ? weekday : due.formatted(.dateTime.month(.abbreviated)).uppercased()
            }
            return Bill(
                id: "\(bill.description)-\(bill.due)",
                name: bill.description,
                label: label,
                date: String(format: "%02d", calendar.component(.day, from: due)),
                amount: Decimal.api(bill.amount),
                currencyCode: bill.currency,
                isSoon: bill.daysAway <= 2
            )
        }
    }

    var recent: [Expense] {
        guard let summary else { return [] }
        let today = Date.apiDay(summary.date)
        return summary.recent.map { tx in
            Expense(
                id: tx.id,
                merchant: tx.description,
                detail: "\(tx.type == "income" ? "Income" : tx.categoryLabel) · \(Self.relativeDay(tx.date, today: today))",
                symbol: Self.symbol(for: tx.category, type: tx.type),
                amount: Decimal.api(tx.amount),
                currencyCode: tx.currency,
                displayEquivalent: tx.displayAmount.map { Decimal.api($0) }
            )
        }
    }

    private static func relativeDay(_ string: String?, today: Date?) -> String {
        guard let date = Date.apiDay(string) else { return "" }
        let calendar = Calendar.current
        if let today, calendar.isDate(date, inSameDayAs: today) { return "Today" }
        if let today, let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if let today, let days = calendar.dateComponents([.day], from: date, to: today).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func symbol(for category: String?, type: String) -> String {
        if type == "income" { return "arrow.down.left" }
        switch category {
        case "groceries": return "cart"
        case "dining": return "fork.knife"
        case "transport": return "car"
        case "housing": return "house"
        case "utilities": return "bolt"
        case "subscriptions": return "repeat"
        case "shopping": return "bag"
        case "health": return "heart"
        case "entertainment": return "film"
        case "debt": return "creditcard"
        default: return "circle.grid.2x2"
        }
    }
}
