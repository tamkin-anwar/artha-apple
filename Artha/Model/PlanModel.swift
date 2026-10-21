import Foundation
import Observation

/// The month as a plan (/api/v1/plan): the budget split into bills,
/// everyday spending and what's left (the same math as Today's Safe to
/// Spend, in its parts), this month's bills paid and still to come, and
/// optional category limits. Changes go through the same server rules as
/// the web app; afterwards `onChange` lets Today pick up the new numbers.
@Observable
final class PlanModel {
    struct BillRow: Identifiable {
        let id: String
        let name: String
        let day: String
        let weekday: String
        let detail: String
        let amount: Decimal
        let currencyCode: String
        let displayEquivalent: Decimal?
        let isPaid: Bool
        let isSoon: Bool
    }

    private(set) var summary: PlanSummary?
    private(set) var bills: [BillRow] = []
    /// The last six months, for "Month by month". Loaded beside the plan.
    private(set) var history: HistorySummary?
    private(set) var error: String?
    private(set) var lastLoaded: Date?

    var onChange: @MainActor () async -> Void = {}

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: Figures

    var currencyCode: String { summary?.currency ?? "USD" }
    var monthName: String { summary?.month.name ?? "" }
    var daysLeft: Int { summary?.month.daysLeft ?? 1 }
    var cap: Decimal? { summary?.budget.map { Decimal.api($0.cap) } }
    var billsTotal: Decimal { Decimal.api(summary?.billsTotal) }
    var billsPaid: Decimal { Decimal.api(summary?.billsPaid) }
    var billsComing: Decimal { Decimal.api(summary?.billsComing) }
    var everydaySpent: Decimal { Decimal.api(summary?.breakdown?.everydaySpent) }
    var everydayBudget: Decimal { Decimal.api(summary?.breakdown?.everydayBudget) }
    var left: Decimal { Decimal.api(summary?.breakdown?.left) }
    var overBy: Decimal { Decimal.api(summary?.breakdown?.overBy) }
    var perDay: Decimal { Decimal.api(summary?.breakdown?.perDay).rounded(0, .down) }
    var isOver: Bool { overBy > 0 }
    var limits: [PlanSummary.Limit] { summary?.categoryBudgets ?? [] }
    var unbudgeted: [CategoryList.Category] { summary?.unbudgetedCategories ?? [] }

    /// What this person usually spends a month, rounded up to a friendly
    /// number, to suggest instead of making them guess.
    var suggestedBudget: Decimal? {
        guard let overall = summary?.typical?.overall else { return nil }
        let value = Decimal.api(overall)
        return value > 0 ? value.roundedUp(toStep: 50) : nil
    }

    func usual(for category: String) -> Decimal? {
        guard let raw = summary?.typical?.byCategory[category] else { return nil }
        let value = Decimal.api(raw)
        return value > 0 ? value : nil
    }

    func suggestedLimit(for category: String) -> Decimal? {
        usual(for: category)?.roundedUp(toStep: 10)
    }

    // MARK: Loading

    func load() async {
        async let months: Void = loadHistory()
        do {
            let (summary, data): (PlanSummary, Data) = try await api.fetch("plan")
            apply(summary)
            ResponseCache.save(data, as: .plan)
            error = nil
        } catch let failure as APIError {
            error = failure.message
        } catch {
            self.error = "Artha couldn't load your plan. Pull down to try again."
        }
        await months
    }

    /// Past months only change when this one does, so a failure here just
    /// keeps whatever was showing; the plan's own error covers being offline.
    private func loadHistory() async {
        guard let (history, data): (HistorySummary, Data) = try? await api.fetch("history?months=6") else { return }
        self.history = history
        ResponseCache.save(data, as: .history)
    }

    /// Shows the last plan this device saw while the fresh one loads.
    func restore(from data: Data) {
        guard summary == nil, let cached = api.decode(PlanSummary.self, from: data) else { return }
        apply(cached, fresh: false)
        if history == nil, let saved = ResponseCache.load(.history) {
            history = api.decode(HistorySummary.self, from: saved)
        }
    }

    private func apply(_ summary: PlanSummary, fresh: Bool = true) {
        self.summary = summary
        bills = Self.rows(for: summary)
        if fresh { lastLoaded = .now }
    }

    func clear() {
        summary = nil
        bills = []
        history = nil
        error = nil
        lastLoaded = nil
    }

    // MARK: Changes

    /// Saves the monthly budget; nil removes it.
    func saveBudget(_ amount: Decimal?) async throws {
        try await api.put("budget", body: ["monthly_cap": amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "0"])
        await afterChange()
    }

    func saveLimit(_ category: String, amount: Decimal) async throws {
        try await api.put("category-budgets/\(category)", body: ["monthly_cap": NSDecimalNumber(decimal: amount).stringValue])
        await afterChange()
    }

    func removeLimit(_ category: String) async throws {
        try await api.delete("category-budgets/\(category)")
        await afterChange()
    }

    private func afterChange() async {
        async let plan: Void = load()
        async let today: Void = onChange()
        _ = await (plan, today)
    }

    // MARK: Bill rows

    private static func rows(for summary: PlanSummary) -> [BillRow] {
        let today = Date.apiDay(summary.date)
        let calendar = Calendar.current
        return summary.bills.enumerated().map { index, bill in
            let due = Date.apiDay(bill.date)
            var daysAway = 0
            if let today, let due {
                daysAway = calendar.dateComponents([.day], from: today, to: due).day ?? 0
            }
            let isPaid = bill.status == "paid"
            let when: String
            if isPaid {
                when = "Paid"
            } else if daysAway <= 0 {
                when = "Due today"
            } else if daysAway == 1 {
                when = "Tomorrow"
            } else {
                when = "In \(daysAway) days"
            }
            return BillRow(
                id: "\(bill.description)-\(bill.date)-\(index)",
                name: bill.description,
                day: due.map { String(calendar.component(.day, from: $0)) } ?? "",
                weekday: due?.formatted(.dateTime.weekday(.abbreviated)).uppercased() ?? "",
                detail: "\(bill.categoryLabel) · \(when)",
                amount: Decimal.api(bill.amount),
                currencyCode: bill.currency,
                displayEquivalent: bill.displayAmount.map { Decimal.api($0) },
                isPaid: isPaid,
                isSoon: !isPaid && daysAway <= 2
            )
        }
    }
}
