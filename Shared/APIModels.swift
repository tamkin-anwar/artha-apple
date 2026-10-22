import Foundation

// Mirrors the JSON from the Artha server's /api/v1 (the artha repo's
// artha/blueprints/api/routes.py). Keys arrive in snake_case and are
// decoded with .convertFromSnakeCase. Money arrives as two-decimal strings
// ("1284.01") and is turned into Decimal with `Decimal.api(_:)`, never Double.

nonisolated struct APIUser: Decodable, Sendable {
    let id: Int
    let username: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let currency: String
    let timezone: String?
    let twoFactorEnabled: Bool
    /// Shared with the website's notification settings. Optional so a
    /// saved copy from before these existed still decodes.
    let notifyBillsDue: Bool?
    let notifyBudgetAlerts: Bool?
    let reminderHour: Int?

    var initials: String {
        let parts = [firstName, lastName].compactMap { $0?.first }.map(String.init)
        if !parts.isEmpty { return parts.joined().uppercased() }
        return String(username.prefix(2)).uppercased()
    }
}

nonisolated struct SessionResponse: Decodable, Sendable {
    let token: String
    let deletionCanceled: Bool
    let user: APIUser
}

nonisolated struct DeletionResponse: Decodable, Sendable {
    let purgeDate: String
}

nonisolated struct PasswordChanged: Decodable, Sendable {
    let token: String
    let user: APIUser
}

nonisolated struct TwoFactorSetup: Decodable, Sendable {
    let secret: String
    let uri: String
}

nonisolated struct TwoFactorEnabled: Decodable, Sendable {
    let recoveryCodes: [String]
    let user: APIUser
}

nonisolated struct UserEnvelope: Decodable, Sendable {
    let user: APIUser
}

nonisolated struct TransactionEnvelope: Decodable, Sendable {
    let transaction: APITransaction
}

nonisolated struct TransactionPage: Decodable, Sendable {
    let currency: String
    /// The person's own date on the server ("2026-10-20").
    let today: String
    let transactions: [APITransaction]
    let nextOffset: Int?
}

nonisolated struct CategoryList: Decodable, Sendable {
    nonisolated struct Category: Decodable, Sendable, Identifiable, Hashable {
        let key: String
        let label: String
        var id: String { key }
    }

    let categories: [Category]
}

nonisolated struct APITransaction: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let description: String
    let amount: String
    let currency: String
    let type: String
    let category: String?
    let categoryLabel: String
    let date: String?
    let isRecurring: Bool
    let recurrenceInterval: String?
    /// "manual", "csv" (statement import), "apple_pay", or nil (older rows).
    let source: String?
    /// Only when `currency` isn't the person's display currency: the same
    /// amount converted, shown beside the real one, never instead of it.
    let displayAmount: String?
    /// Logged on its own (Apple Pay) and not looked at yet. Optional so a
    /// response cached before this field existed still decodes.
    let needsReview: Bool?
}

nonisolated struct PlanSummary: Decodable, Sendable {
    nonisolated struct Breakdown: Decodable, Sendable {
        let bills: String
        let everydaySpent: String
        let everydayBudget: String
        let left: String
        let overBy: String
        let perDay: String
        let status: String?
    }

    nonisolated struct Bill: Decodable, Sendable {
        let description: String
        let amount: String
        let currency: String
        let category: String?
        let categoryLabel: String
        let date: String
        /// "paid", "scheduled" (posted ahead for a later day) or "due".
        let status: String
        let displayAmount: String?
    }

    nonisolated struct Limit: Decodable, Sendable {
        let key: String
        let label: String
        let cap: String
        let spent: String
        let left: String
        let overBy: String
        let percentUsed: Double
        let tier: String
    }

    nonisolated struct Typical: Decodable, Sendable {
        let months: Int
        let overall: String
        let byCategory: [String: String]
    }

    let date: String
    let currency: String
    let month: TodaySummary.Month
    let spent: String
    let budget: TodaySummary.Budget?
    let breakdown: Breakdown?
    let bills: [Bill]
    let billsTotal: String
    let billsPaid: String
    let billsComing: String
    let categoryBudgets: [Limit]
    let unbudgetedCategories: [CategoryList.Category]
    let typical: Typical?
}

nonisolated struct APIAccount: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
    let type: String
    let typeLabel: String
    /// "cash", "investments", "property" or "debts".
    let group: String
    let isLiability: Bool
    /// Always positive: what's held, or for a debt, what's owed.
    let balance: String
    let currency: String
    /// Only when `currency` isn't the display currency.
    let displayBalance: String?
    let updated: String?
    let daysSinceUpdate: Int?
}

nonisolated struct AccountEnvelope: Decodable, Sendable {
    let account: APIAccount
}

nonisolated struct WealthSummary: Decodable, Sendable {
    nonisolated struct Point: Decodable, Sendable {
        let date: String
        let netWorth: String
    }

    nonisolated struct AccountType: Decodable, Sendable, Identifiable, Hashable {
        let key: String
        let label: String
        let isLiability: Bool
        let group: String
        var id: String { key }
    }

    let currency: String
    let netWorth: String?
    let assets: String
    let liabilities: String
    let history: [Point]
    let accounts: [APIAccount]
    let accountTypes: [AccountType]
    let currencies: [String]
}

nonisolated struct TodaySummary: Decodable, Sendable {
    nonisolated struct Month: Decodable, Sendable {
        let name: String
        let start: String
        let end: String
        let day: Int
        let daysInMonth: Int
        let daysLeft: Int
    }

    nonisolated struct Budget: Decodable, Sendable {
        let cap: String
        let spent: String
        let percentUsed: Double
        let tier: String
    }

    nonisolated struct SafeToSpend: Decodable, Sendable {
        let amount: String
        let perDay: String
        let billsStillDue: String
        let overBy: String
        let status: String
        let evenPaceSpent: String
    }

    nonisolated struct DaySpend: Decodable, Sendable {
        let day: Int
        let spent: String
    }

    nonisolated struct Category: Decodable, Sendable {
        let key: String?
        let label: String
        let amount: String
    }

    nonisolated struct Bill: Decodable, Sendable {
        let description: String
        let amount: String
        let currency: String
        let category: String?
        let due: String
        let daysAway: Int
    }

    nonisolated struct NetWorth: Decodable, Sendable {
        let amount: String
        let assets: String
        let liabilities: String
        let accountCount: Int
    }

    let date: String
    let currency: String
    let month: Month
    let spent: String
    let income: String
    let budget: Budget?
    let safeToSpend: SafeToSpend?
    let spendingByDay: [DaySpend]
    let categories: [Category]
    let comingUp: [Bill]
    let recent: [APITransaction]
    let netWorth: NetWorth?
    /// Purchases that logged themselves and haven't been looked at yet.
    let toReview: Int?
    /// The newest purchase Apple Pay logged on its own; nil until the
    /// automation has logged one.
    let applePay: ApplePayStatus?

    nonisolated struct ApplePayStatus: Decodable, Sendable {
        let description: String
        let date: String?
        let count: Int
    }
}

/// /api/v1/history: the last few months, oldest first.
nonisolated struct HistorySummary: Decodable, Sendable {
    nonisolated struct Month: Decodable, Sendable {
        nonisolated struct Category: Decodable, Sendable {
            let key: String?
            let label: String
            let amount: String
        }

        let month: String
        let label: String
        let name: String
        let year: Int
        let isCurrent: Bool
        /// Only on a first month that began partway through ("2026-08-27").
        let started: String?
        let spent: String
        let income: String
        let categories: [Category]
    }

    let currency: String
    let months: [Month]
    let averageSpent: String?
}

nonisolated struct ReviewedResponse: Decodable, Sendable {
    let toReview: Int
}

extension Decimal {
    /// A money string from the API. Malformed input reads as zero rather
    /// than crashing a screen over one bad field.
    nonisolated static func api(_ string: String?) -> Decimal {
        guard let string, let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else { return 0 }
        return value
    }
}

extension Date {
    /// "2026-10-20" from the API, as a calendar date at local midnight.
    nonisolated static func apiDay(_ string: String?) -> Date? {
        guard let string else { return nil }
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
