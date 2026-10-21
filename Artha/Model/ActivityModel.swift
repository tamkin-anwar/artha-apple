import Foundation
import Observation

/// Every transaction, newest first, a page at a time, with search and an
/// Expenses/Income filter done on the server. Edits and deletes go through
/// the same server rules as the web app; afterwards `onChange` lets Today
/// pick up the new numbers.
@Observable
final class ActivityModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case expenses = "Expenses"
        case income = "Income"
        var id: String { rawValue }

        var apiType: String? {
            switch self {
            case .all: nil
            case .expenses: "expense"
            case .income: "income"
            }
        }
    }

    struct Day: Identifiable {
        let id: String
        let title: String
        let isUpcoming: Bool
        let transactions: [APITransaction]
    }

    /// How long a swiped-away transaction waits before it's really deleted,
    /// which is how long Undo stays on screen.
    static let undoWindow: Duration = .seconds(5)

    private(set) var transactions: [APITransaction] = []
    private(set) var currencyCode = "USD"
    /// The person's own date, from the server rather than the phone's
    /// clock, which can sit in another timezone.
    private(set) var today = Calendar.current.startOfDay(for: .now)
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var categories: [CategoryList.Category] = []
    private(set) var pendingDelete: APITransaction?
    /// Bumps on every delete so the list can play one haptic.
    private(set) var deleteCount = 0

    var query = ""
    var filter: Filter = .all

    var onChange: () async -> Void = {}

    private let api: APIClient
    private var nextOffset: Int?
    private var pendingDeleteTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(api: APIClient) {
        self.api = api
    }

    var isFiltered: Bool { filter != .all || !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var canLoadMore: Bool { nextOffset != nil }

    /// Grouped by day, newest first. A recurring bill is posted ahead for
    /// later this month, so days after today are marked as upcoming.
    var days: [Day] {
        let today = today
        var groups: [(key: String, items: [APITransaction])] = []
        for tx in transactions where tx.id != pendingDelete?.id {
            let key = tx.date ?? ""
            if groups.last?.key == key {
                groups[groups.count - 1].items.append(tx)
            } else {
                groups.append((key, [tx]))
            }
        }
        return groups.map { group in
            let date = Date.apiDay(group.key)
            return Day(id: group.key,
                       title: Self.title(for: date, today: today),
                       isUpcoming: date.map { $0 > today } ?? false,
                       transactions: group.items)
        }
    }

    func transaction(id: Int) -> APITransaction? {
        transactions.first { $0.id == id }
    }

    // MARK: Loading

    /// Starts over from the newest transaction with the current search
    /// and filter. A slower, older reload never overwrites a newer one.
    func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let page: TransactionPage = try await api.get(path(offset: 0))
            guard generation == loadGeneration else { return }
            transactions = page.transactions
            currencyCode = page.currency
            today = Date.apiDay(page.today) ?? today
            nextOffset = page.nextOffset
            hasLoaded = true
            error = nil
        } catch let failure as APIError {
            guard generation == loadGeneration else { return }
            error = failure.message
        } catch {
            guard generation == loadGeneration else { return }
            self.error = "Artha couldn't load your transactions. Pull down to try again."
        }
        if categories.isEmpty {
            let list: CategoryList? = try? await api.get("categories")
            categories = list?.categories ?? []
        }
    }

    func loadMore() async {
        guard let offset = nextOffset, !isLoading else { return }
        let generation = loadGeneration
        isLoading = true
        defer { isLoading = false }
        do {
            let page: TransactionPage = try await api.get(path(offset: offset))
            guard generation == loadGeneration else { return }
            let known = Set(transactions.map(\.id))
            transactions += page.transactions.filter { !known.contains($0.id) }
            nextOffset = page.nextOffset
        } catch {
            // The next scroll to the bottom tries again.
        }
    }

    private func path(offset: Int) -> String {
        var items = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset))]
        let search = query.trimmingCharacters(in: .whitespaces)
        if !search.isEmpty { items.append(URLQueryItem(name: "q", value: search)) }
        if let type = filter.apiType { items.append(URLQueryItem(name: "type", value: type)) }
        var components = URLComponents()
        components.path = "transactions"
        components.queryItems = items
        return components.string ?? "transactions"
    }

    // MARK: Changes

    /// Saves an edit; `changes` holds only the fields that changed.
    func update(_ tx: APITransaction, changes: [String: Any]) async throws {
        let envelope: TransactionEnvelope = try await api.patch("transactions/\(tx.id)", body: changes)
        if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
            transactions[index] = envelope.transaction
        }
        // A new date can move it to another day, so re-sort the same way
        // the server does: newest date first, then newest id.
        transactions.sort { ($0.date ?? "", $0.id) > ($1.date ?? "", $1.id) }
        await onChange()
    }

    /// Hides the transaction now and deletes it once the undo window
    /// passes. Deleting another one first finishes this one straight away.
    func delete(_ tx: APITransaction) {
        if pendingDelete != nil { commitPendingDelete() }
        pendingDelete = tx
        deleteCount += 1
        pendingDeleteTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.commitPendingDelete()
        }
    }

    func undoDelete() {
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        pendingDelete = nil
    }

    /// Sends a held-back delete now, e.g. when the app goes to the
    /// background, so a delete is never silently lost.
    func commitPendingDelete() {
        guard let tx = pendingDelete else { return }
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        pendingDelete = nil
        transactions.removeAll { $0.id == tx.id }
        Task {
            do {
                try await api.delete("transactions/\(tx.id)")
                await onChange()
            } catch APIError.rejected(code: "not_found", _) {
                // Already gone (deleted on the web meanwhile): nothing to put back.
            } catch let failure as APIError {
                error = failure.message
                await reload()
            } catch {
                await reload()
            }
        }
    }

    func dismissError() { error = nil }

    func clear() {
        undoDelete()
        transactions = []
        categories = []
        nextOffset = nil
        hasLoaded = false
        error = nil
        query = ""
        filter = .all
    }

    // MARK: Day titles

    private static func title(for date: Date?, today: Date) -> String {
        guard let date else { return "No date" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: today) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        if let days = calendar.dateComponents([.day], from: date, to: today).day, (2..<7).contains(days) {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(date, equalTo: today, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
