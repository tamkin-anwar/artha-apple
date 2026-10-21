import Foundation
import Observation

/// Net worth now and over time, and every account behind it
/// (/api/v1/wealth). Balances are typed in, never synced: nothing here can
/// break when a bank changes its login. Changes go through the same server
/// rules as the web Accounts page; afterwards `onChange` lets Today pick up
/// the new net worth.
@Observable
final class WealthModel {
    enum Range: String, CaseIterable, Identifiable {
        case month = "1M", quarter = "3M", year = "1Y", all = "All"
        var id: String { rawValue }

        var months: Int? {
            switch self {
            case .month: 1
            case .quarter: 3
            case .year: 12
            case .all: nil
            }
        }
    }

    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    struct Group: Identifiable {
        let id: String
        let title: String
        let accounts: [APIAccount]
        let total: Decimal
    }

    /// A balance this old gets a gentle nudge to update.
    static let staleAfterDays = 30

    private(set) var summary: WealthSummary?
    private(set) var groups: [Group] = []
    private(set) var history: [Point] = []
    private(set) var error: String?
    var range: Range = .quarter

    var onChange: @MainActor () async -> Void = {}

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: Figures

    var currencyCode: String { summary?.currency ?? "USD" }
    var hasAccounts: Bool { !(summary?.accounts.isEmpty ?? true) }
    var netWorth: Decimal { Decimal.api(summary?.netWorth) }
    var assets: Decimal { Decimal.api(summary?.assets) }
    var liabilities: Decimal { Decimal.api(summary?.liabilities) }
    var accountTypes: [WealthSummary.AccountType] { summary?.accountTypes ?? [] }
    var currencies: [String] { summary?.currencies ?? ["USD"] }

    var staleAccounts: [APIAccount] {
        (summary?.accounts ?? []).filter { ($0.daysSinceUpdate ?? 0) >= Self.staleAfterDays }
    }

    /// The history inside the chosen range. The value on the range's first
    /// day is whatever net worth was then (the last point at or before it),
    /// so the line starts where it really stood instead of at the first
    /// update inside the range.
    var rangePoints: [Point] {
        guard let last = history.last else { return [] }
        guard let months = range.months,
              let start = Calendar.current.date(byAdding: .month, value: -months, to: last.date),
              let firstAfter = history.firstIndex(where: { $0.date > start }) else {
            return history
        }
        let inside = Array(history[firstAfter...])
        guard firstAfter > 0 else { return inside }
        return [Point(date: start, value: history[firstAfter - 1].value)] + inside
    }

    /// How much net worth moved over the chosen range.
    var change: Decimal? {
        let points = rangePoints
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return Decimal(last.value - first.value).rounded(2)
    }

    var changeLabel: String {
        switch range {
        case .month: return "in the past month"
        case .quarter: return "in the past 3 months"
        case .year: return "in the past year"
        case .all:
            guard let first = history.first?.date else { return "" }
            return "since \(first.formatted(.dateTime.month(.abbreviated).year()))"
        }
    }

    // MARK: Loading

    func load() async {
        do {
            let (summary, data): (WealthSummary, Data) = try await api.fetch("wealth")
            apply(summary)
            ResponseCache.save(data, as: .wealth)
            error = nil
        } catch let failure as APIError {
            error = failure.message
        } catch {
            self.error = "Artha couldn't load your accounts. Pull down to try again."
        }
    }

    func restore(from data: Data) {
        guard summary == nil, let cached = api.decode(WealthSummary.self, from: data) else { return }
        apply(cached)
    }

    private func apply(_ summary: WealthSummary) {
        self.summary = summary
        history = summary.history.compactMap { point in
            Date.apiDay(point.date).map { Point(date: $0, value: (Decimal.api(point.netWorth) as NSDecimalNumber).doubleValue) }
        }
        let titles = ["cash": "Cash", "investments": "Investments", "property": "Property and other", "debts": "Debts"]
        groups = ["cash", "investments", "property", "debts"].compactMap { key in
            let accounts = summary.accounts.filter { $0.group == key }
            guard !accounts.isEmpty else { return nil }
            let total = accounts.reduce(Decimal(0)) { $0 + Decimal.api($1.displayBalance ?? $1.balance) }
            return Group(id: key, title: titles[key] ?? key, accounts: accounts, total: total)
        }
    }

    func clear() {
        summary = nil
        groups = []
        history = []
        error = nil
        range = .quarter
    }

    // MARK: Changes

    func addAccount(name: String, type: String, currency: String, balance: Decimal) async throws {
        let _: AccountEnvelope = try await api.post("accounts", body: [
            "name": name,
            "account_type": type,
            "currency": currency,
            "current_balance": NSDecimalNumber(decimal: balance).stringValue,
        ])
        await afterChange()
    }

    /// `changes` holds only what changed. Sending a balance, even the same
    /// one, marks it as just updated.
    func updateAccount(_ id: Int, changes: [String: Any]) async throws {
        let _: AccountEnvelope = try await api.patch("accounts/\(id)", body: changes)
        await afterChange()
    }

    func deleteAccount(_ id: Int) async throws {
        try await api.delete("accounts/\(id)")
        await afterChange()
    }

    private func afterChange() async {
        async let wealth: Void = load()
        async let today: Void = onChange()
        _ = await (wealth, today)
    }
}

/// The SF Symbol for each account type (accounts.ACCOUNT_TYPES on the server).
enum AccountStyle {
    static func symbol(for type: String) -> String {
        switch type {
        case "checking": "building.columns"
        case "savings": "banknote"
        case "investment": "chart.line.uptrend.xyaxis"
        case "real_estate": "house"
        case "vehicle": "car"
        case "credit_card": "creditcard"
        case "loan": "doc.text"
        case "other_liability": "minus.circle"
        default: "shippingbox"
        }
    }

    static func updatedLabel(days: Int?) -> String {
        switch days {
        case nil: ""
        case 0: "Updated today"
        case 1: "Updated yesterday"
        case let days?: "Updated \(days) days ago"
        }
    }
}
