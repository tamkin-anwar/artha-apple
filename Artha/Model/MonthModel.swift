import Foundation
import Observation

/// Sample month for the prototype. Every figure on Today is derived from
/// the few numbers here (budget, what's been spent, bills still due), the
/// way the real app will derive them from the Artha API, so switching
/// scenarios keeps every number on screen consistent with the others.
@Observable
final class MonthModel {
    enum Scenario: String, CaseIterable, Identifiable {
        case onPace = "On pace"
        case ahead = "Ahead of pace"
        case over = "Over budget"
        case firstDay = "First day"
        var id: String { rawValue }
    }

    enum HeroMetric: String, CaseIterable, Identifiable {
        case safeToSpend = "Safe to spend"
        case spentThisMonth = "Spent this month"
        case netWorth = "Net worth"
        var id: String { rawValue }
    }

    enum Status { case onPace, ahead, over }

    struct Bill: Identifiable {
        let id = UUID()
        let name: String
        let label: String
        let date: String
        let amount: Decimal
        let isThisMonth: Bool
        let isSoon: Bool
    }

    struct Expense: Identifiable {
        let id = UUID()
        let merchant: String
        let detail: String
        let symbol: String
        let amount: Decimal
        let currencyCode: String
        /// Only for an expense in another currency: its USD equivalent,
        /// shown beside the native amount, never instead of it.
        let usdEquivalent: Decimal?
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

    var scenario: Scenario = .onPace
    var heroMetric: HeroMetric = .safeToSpend
    private(set) var added: [Expense] = []
    /// Bumps on every add so Today can play one success haptic.
    private(set) var addCount = 0

    let budget: Decimal = 3400
    let today = 19
    let daysInMonth = 31
    let monthName = "October"
    let netWorth: Decimal = 48210

    let bills: [Bill] = [
        Bill(name: "Spotify", label: "WED · 2 DAYS", date: "21", amount: 11.99, isThisMonth: true, isSoon: true),
        Bill(name: "Phone bill", label: "SAT", date: "24", amount: 45, isThisMonth: true, isSoon: false),
        Bill(name: "Rent", label: "NOV", date: "01", amount: 1650, isThisMonth: false, isSoon: false),
    ]

    private let baseRecent: [Expense] = [
        Expense(merchant: "Trader Joe's", detail: "Groceries · 8:12 AM", symbol: "cart", amount: 48.20, currencyCode: "USD", usdEquivalent: nil),
        Expense(merchant: "Lyft", detail: "Transport · Yesterday", symbol: "car", amount: 8.45, currencyCode: "USD", usdEquivalent: nil),
        Expense(merchant: "Family, Dhaka", detail: "Transfer · Saturday", symbol: "arrow.left.arrow.right", amount: 12000, currencyCode: "BDT", usdEquivalent: 98.36),
    ]

    /// Cumulative spending through each day of the on-pace month.
    private let onPaceCumulative: [Decimal] = [95, 180, 260, 410, 470, 540, 690, 760, 830, 980, 1050, 1120, 1260, 1330, 1490, 1560, 1700, 1996, 2059]

    private var scenarioSpent: Decimal {
        switch scenario {
        case .onPace: 2059
        case .ahead: 3120
        case .over: 3483
        case .firstDay: 0
        }
    }

    var hasData: Bool { scenario != .firstDay || !added.isEmpty }

    var spent: Decimal { scenarioSpent + added.reduce(0) { $0 + $1.amount } }

    var billsDueThisMonth: Decimal {
        bills.filter(\.isThisMonth).reduce(0) { $0 + $1.amount }
    }

    var safeToSpend: Decimal { max(0, budget - spent - billsDueThisMonth) }
    var overBy: Decimal { max(0, spent + billsDueThisMonth - budget) }
    var daysLeft: Int { daysInMonth - today + 1 }

    var perDay: Decimal {
        let raw = (safeToSpend as NSDecimalNumber).doubleValue / Double(daysLeft)
        return Decimal(raw.rounded(.down))
    }

    /// What an even pace to the budget would have spent by the end of `day`.
    func paceAmount(on day: Int) -> Double {
        (budget as NSDecimalNumber).doubleValue * Double(day - 1) / Double(daysInMonth - 1)
    }

    var status: Status {
        if overBy > 0 { return .over }
        let ahead = (spent as NSDecimalNumber).doubleValue - paceAmount(on: today)
        return ahead > (budget as NSDecimalNumber).doubleValue * 0.05 ? .ahead : .onPace
    }

    /// Day-by-day cumulative spending, scaled to the scenario; anything added
    /// in this session lands on today.
    var cumulative: [DayPoint] {
        guard hasData else { return [] }
        let base = (onPaceCumulative.last! as NSDecimalNumber).doubleValue
        let target = (scenarioSpent as NSDecimalNumber).doubleValue
        let scale = scenario == .firstDay ? 0 : target / base
        let extra = (added.reduce(0) { $0 + $1.amount } as NSDecimalNumber).doubleValue
        return onPaceCumulative.enumerated().map { index, value in
            let day = index + 1
            let amount = (value as NSDecimalNumber).doubleValue * scale + (day == today ? extra : 0)
            return DayPoint(day: day, amount: amount)
        }
    }

    func amount(on day: Int) -> Double? {
        cumulative.first { $0.day == day }?.amount
    }

    var recent: [Expense] { added.reversed() + baseRecent }

    /// Top three categories by size, plus everything else, summing to `spent`.
    var shares: [Share] {
        let base: [(String, Decimal)] = [("Bills", 440), ("Groceries", 412), ("Shopping", 318)]
        let scale = (scenarioSpent as NSDecimalNumber).doubleValue / 2059
        var result = base.map { name, value in
            Share(id: name, amount: Decimal(((value as NSDecimalNumber).doubleValue * scale).rounded()))
        }
        let named = result.reduce(0) { $0 + $1.amount }
        result.append(Share(id: "Everything else", amount: spent - named))
        return result
    }

    var heroValue: Decimal {
        switch heroMetric {
        case .safeToSpend: safeToSpend
        case .spentThisMonth: spent
        case .netWorth: netWorth
        }
    }

    func add(_ expense: Expense) {
        added.append(expense)
        addCount += 1
    }
}
