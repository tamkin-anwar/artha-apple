import Charts
import SwiftUI

/// Everything you own and owe. Net worth leads, with how it moved over the
/// range you pick, drawn as a line you can drag across. Under it, what's
/// owned against what's owed, a nudge when balances go stale, and every
/// account grouped the way people think about them. Balances are typed in,
/// so there's no bank connection to break, and every account keeps its own
/// currency.
struct WealthView: View {
    @Environment(AppSession.self) private var session
    @State private var sheet: WealthSheet?

    private var wealth: WealthModel { session.wealth }

    var body: some View {
        NavigationStack {
            ScrollView {
                if wealth.summary == nil {
                    loading
                } else if !wealth.hasAccounts {
                    EmptyWealth(sheet: $sheet)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        NetWorthHero()
                            .padding(.horizontal, 20)
                        NetWorthChart()
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                        RangePicker()
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                        OwnedAndOwed()
                            .padding(.horizontal, 16)
                            .padding(.top, 26)
                        if !wealth.staleAccounts.isEmpty {
                            StaleCard { sheet = .review(wealth.staleAccounts) }
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        }
                        ForEach(wealth.groups) { group in
                            AccountGroupView(group: group, currencyCode: wealth.currencyCode) { account in
                                sheet = .edit(account)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 28)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 120)
                }
            }
            .scrollIndicators(.hidden)
            .background(Palette.ground)
            .refreshable { await wealth.load() }
            .navigationTitle("Wealth")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                if wealth.hasAccounts {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add account", systemImage: "plus") { sheet = .add("checking") }
                    }
                }
            }
        }
        .task { if wealth.summary == nil { await wealth.load() } }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add(let type): AccountSheet(existing: nil, startingType: type)
            case .edit(let account): AccountSheet(existing: account)
            case .review(let accounts): ReviewBalancesSheet(accounts: accounts)
            }
        }
    }

    @ViewBuilder
    private var loading: some View {
        if let error = wealth.error {
            ContentUnavailableView {
                Label("Can't load Wealth", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await wealth.load() } }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 80)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 160)
        }
    }
}

enum WealthSheet: Identifiable {
    case add(String)
    case edit(APIAccount)
    case review([APIAccount])

    var id: String {
        switch self {
        case .add(let type): "add-\(type)"
        case .edit(let account): "edit-\(account.id)"
        case .review: "review"
        }
    }
}

// MARK: - Net worth

private struct NetWorthHero: View {
    @Environment(AppSession.self) private var session
    private var wealth: WealthModel { session.wealth }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Net worth")
            Text(Money.whole(wealth.netWorth, wealth.currencyCode))
                .font(.figure(64))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: (wealth.netWorth as NSDecimalNumber).doubleValue))
                .animation(.snappy(duration: 0.5), value: wealth.netWorth)
                .padding(.top, 4)
            if let change = wealth.change {
                HStack(spacing: 6) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .heavy))
                    Text("\(Money.whole(abs(change), wealth.currencyCode)) \(wealth.changeLabel)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(change >= 0 ? Palette.good : Palette.caution)
                .padding(.top, 10)
                .animation(.snappy(duration: 0.4), value: wealth.range)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Net worth over time, as a line you can drag across. Balances only
/// change when someone updates them, so the line steps at each update
/// rather than inventing a smooth curve between them.
private struct NetWorthChart: View {
    @Environment(AppSession.self) private var session
    @State private var selected: Date?

    private var wealth: WealthModel { session.wealth }

    var body: some View {
        let points = wealth.rangePoints
        if points.count < 2 {
            VStack(spacing: 4) {
                Text("Your trend starts here")
                    .font(.system(size: 15, weight: .semibold))
                Text("Every balance you update adds a point to this line.")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height - 12))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 12))
                    }
                    .stroke(Palette.ink.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                }
            }
        } else {
            chart(points)
        }
    }

    private func chart(_ points: [WealthModel.Point]) -> some View {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.35, abs(high) * 0.02, 1)
        let active = point(for: selected, in: points) ?? points.last
        let color = (wealth.change ?? 0) >= 0 ? Palette.accent : Palette.cautionLine

        return Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Date", point.date),
                         yStart: .value("Base", low - pad),
                         yEnd: .value("Net worth", point.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.26), color.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.stepEnd)
                LineMark(x: .value("Date", point.date), y: .value("Net worth", point.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.stepEnd)
            }
            if let active {
                RuleMark(x: .value("Date", active.date))
                    .foregroundStyle(Palette.ink.opacity(0.22))
                PointMark(x: .value("Date", active.date), y: .value("Net worth", active.value))
                    .symbolSize(80)
                    .foregroundStyle(color)
                    .annotation(position: .top, spacing: 10,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(active.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.secondary)
                            Text(Money.whole(Decimal(active.value), wealth.currencyCode))
                                .font(.figure(16))
                                .monospacedDigit()
                                .foregroundStyle(Palette.ink)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Palette.surface, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1))
                    }
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad * 1.6))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXSelection(value: $selected)
        // One tick per balance update crossed, not per point dragged over.
        .sensoryFeedback(.selection, trigger: selected.flatMap { date in points.last(where: { $0.date <= date })?.date })
        .animation(.snappy(duration: 0.45), value: wealth.range)
        .frame(height: 200)
        .accessibilityElement()
        .accessibilityLabel("Net worth over time")
        .accessibilityValue("\(Money.whole(Decimal(points.first?.value ?? 0), wealth.currencyCode)) to \(Money.whole(Decimal(points.last?.value ?? 0), wealth.currencyCode)) \(wealth.changeLabel)")
    }

    /// The net worth on a dragged-to day: the last point on or before it.
    private func point(for date: Date?, in points: [WealthModel.Point]) -> WealthModel.Point? {
        guard let date else { return nil }
        guard let match = points.last(where: { $0.date <= date }) ?? points.first else { return nil }
        return WealthModel.Point(date: max(date, match.date), value: match.value)
    }
}

private struct RangePicker: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        @Bindable var wealth = session.wealth
        Picker("Range", selection: $wealth.range) {
            ForEach(WealthModel.Range.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: wealth.range)
    }
}

/// What's owned against what's owed, as one bar.
private struct OwnedAndOwed: View {
    @Environment(AppSession.self) private var session
    private var wealth: WealthModel { session.wealth }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { proxy in
                let total = max((wealth.assets + wealth.liabilities as NSDecimalNumber).doubleValue, 1)
                let owned = proxy.size.width * (wealth.assets as NSDecimalNumber).doubleValue / total
                HStack(spacing: 3) {
                    Capsule().fill(Palette.accent).frame(width: max(owned - 1.5, wealth.assets > 0 ? 6 : 0))
                    if wealth.liabilities > 0 {
                        Capsule().fill(Palette.ink.opacity(0.35))
                    }
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            HStack(alignment: .top) {
                Total(swatch: Palette.accent, title: "You own", amount: wealth.assets, currencyCode: wealth.currencyCode)
                Spacer()
                Total(swatch: Palette.ink.opacity(0.35), title: "You owe", amount: wealth.liabilities, currencyCode: wealth.currencyCode)
            }
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 22))
        .animation(.snappy(duration: 0.45), value: wealth.assets)
        .animation(.snappy(duration: 0.45), value: wealth.liabilities)
    }

    private struct Total: View {
        let swatch: Color
        let title: String
        let amount: Decimal
        let currencyCode: String

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(swatch).frame(width: 10, height: 10)
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                }
                Text(Money.whole(amount, currencyCode))
                    .font(.figure(22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: (amount as NSDecimalNumber).doubleValue))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Balances typed in by hand go stale quietly. This says so, kindly, and
/// opens a quick pass through just those accounts.
private struct StaleCard: View {
    @Environment(AppSession.self) private var session
    let review: () -> Void

    var body: some View {
        let count = session.wealth.staleAccounts.count
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.caution)
                .frame(width: 38, height: 38)
                .background(Palette.raised, in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(count == 1 ? "1 balance is over a month old" : "\(count) balances are over a month old")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("A quick check keeps your net worth honest. Confirming one takes a tap.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Review balances", action: review)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 36)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Palette.surface, in: .rect(cornerRadius: 20))
    }
}

// MARK: - Accounts

private struct AccountGroupView: View {
    let group: WealthModel.Group
    let currencyCode: String
    let open: (APIAccount) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(group.title)
                Spacer()
                Text(Money.whole(group.total, currencyCode))
                    .font(.figure(17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                    Button { open(account) } label: {
                        AccountRow(account: account, displayCurrency: currencyCode)
                    }
                    .buttonStyle(.plain)
                    if index < group.accounts.count - 1 {
                        Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1).padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Palette.surface, in: .rect(cornerRadius: 20))
        }
    }
}

private struct AccountRow: View {
    let account: APIAccount
    let displayCurrency: String

    private var isStale: Bool { (account.daysSinceUpdate ?? 0) >= WealthModel.staleAfterDays }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: AccountStyle.symbol(for: account.type))
                .font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .background(Palette.raised, in: .rect(cornerRadius: 12))
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if isStale {
                        Circle().fill(Palette.cautionLine).frame(width: 6, height: 6)
                    }
                    Text("\(account.typeLabel) · \(AccountStyle.updatedLabel(days: account.daysSinceUpdate))")
                        .lineLimit(1)
                }
                .font(.system(size: 13))
                .foregroundStyle(isStale ? Palette.caution : Palette.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.natural(Decimal.api(account.balance), account.currency))
                    .font(.figure(17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                if let equivalent = account.displayBalance {
                    Text("≈ \(Money.whole(Decimal.api(equivalent), displayCurrency))")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Update the balance or edit this account")
    }
}

// MARK: - First time

/// No accounts yet: what Wealth does, and one-tap starts for the accounts
/// almost everyone has.
private struct EmptyWealth: View {
    @Binding var sheet: WealthSheet?

    private let starters: [(type: String, label: String)] = [
        ("checking", "Checking"), ("savings", "Savings"), ("credit_card", "Credit card"),
        ("investment", "Investments"), ("loan", "Loan"), ("real_estate", "Home"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("See everything you own and owe")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Palette.ink)
            Text("Add each account once and update a balance whenever you like. Artha adds them up into your net worth and draws it over time, in any currency. No bank logins, so nothing breaks.")
                .font(.system(size: 16))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(starters, id: \.type) { starter in
                    Button { sheet = .add(starter.type) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: AccountStyle.symbol(for: starter.type))
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 34, height: 34)
                                .background(Palette.raised, in: .rect(cornerRadius: 10))
                            Text(starter.label)
                                .font(.system(size: 15, weight: .semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Palette.accent)
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(12)
                        .background(Palette.surface, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 26)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 120)
    }
}
