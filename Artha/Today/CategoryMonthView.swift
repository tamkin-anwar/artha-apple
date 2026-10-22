import SwiftUI

/// What's behind one number in "Where October went": the category's total
/// and every transaction in it this month, newest first. Tap one to edit.
struct CategoryMonthView: View {
    let route: TodayRoute.Category

    @Environment(AppSession.self) private var session
    @Environment(MonthModel.self) private var month
    @State private var transactions: [APITransaction]?
    @State private var currencyCode = "USD"
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Money.cents(total, month.currencyCode))
                        .figureFont(40)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text(subtitle)
                        .font(.system(.subheadline))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.vertical, 8)
                .listRowBackground(Palette.ground)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
            }

            ForEach(shown ?? []) { tx in
                NavigationLink(value: TodayRoute.transaction(tx.id, fallback: tx)) {
                    TransactionRow(expense: .init(tx, detail: detail(for: tx)), displayCurrency: currencyCode)
                }
                .listRowBackground(Palette.ground)
                .listRowSeparatorTint(Palette.ink.opacity(0.07))
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle(route.name)
        .inlineTitle()
        .overlay {
            if transactions == nil {
                if let error {
                    ContentUnavailableView {
                        Label("Can't load \(route.name)", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        // Again on coming back from an edit, which can move a transaction
        // out of this category or change its amount.
        .onAppear { Task { await load() } }
        .refreshable { await load() }
        .animation(.snappy(duration: 0.3), value: shown?.map(\.id))
    }

    /// Today's own figure while the list loads, so the number never jumps
    /// from a partial sum.
    private var total: Decimal {
        month.shares.first { $0.id == route.name }?.amount ?? 0
    }

    /// Minus anything deleted from here: one still waiting out its Undo,
    /// or one already sent.
    private var shown: [APITransaction]? {
        let activity = session.activity
        return transactions?.filter { $0.id != activity.pendingDelete?.id && !activity.deletedIDs.contains($0.id) }
    }

    private var subtitle: String {
        let count = shown?.count
        let spent = "Spent in \(month.monthName)"
        guard let count else { return spent }
        return count == 1 ? "\(spent) · 1 transaction" : "\(spent) · \(count) transactions"
    }

    /// The category is the screen; "Everything else" mixes several, so
    /// there it says which. Then the day.
    private func detail(for tx: APITransaction) -> String {
        let day = Date.apiDay(tx.date ?? "")?.formatted(.dateTime.month(.abbreviated).day()) ?? ""
        return route.keys.count > 1 ? "\(tx.categoryLabel) · \(day)" : day
    }

    private func load() async {
        do {
            let page = try await session.monthTransactions(categories: route.keys)
            currencyCode = page.currency
            transactions = page.transactions
            error = nil
        } catch let failure as APIError {
            error = failure.message
        } catch {
            self.error = "Artha couldn't load these transactions. Try again in a moment."
        }
    }
}
