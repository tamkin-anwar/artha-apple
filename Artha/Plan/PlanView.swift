import SwiftUI

/// The month as a plan. The budget, split the way people already think
/// about money: bills first, then everyday spending, then what's left (the
/// same figure Today calls Safe to Spend, in its parts). Under it, this
/// month's bills paid and still to come, then optional category limits.
/// Nothing here is required: no budget, no limits, and it still shows the
/// bills.
struct PlanView: View {
    @Environment(AppSession.self) private var session
    @State private var editingLimit: LimitTarget?

    private var plan: PlanModel { session.plan }

    var body: some View {
        NavigationStack {
            ScrollView {
                if plan.summary == nil {
                    loading
                } else {
                    VStack(alignment: .leading, spacing: 30) {
                        PlanCard()
                        BillsSection()
                        LimitsSection(editingLimit: $editingLimit)
                        MonthByMonth()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 120)
                }
            }
            .scrollIndicators(.hidden)
            .background(Palette.ground)
            .refreshable { await plan.load() }
            .navigationTitle(plan.monthName.isEmpty ? "Plan" : "\(plan.monthName) plan")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
        .task { if plan.summary == nil { await plan.load() } }
        .sheet(item: $editingLimit) { target in
            LimitSheet(existing: target.limit)
        }
    }

    @ViewBuilder
    private var loading: some View {
        if let error = plan.error {
            ContentUnavailableView {
                Label("Can't load your plan", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await plan.load() } }
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

/// Which limit sheet is open: a new limit, or an existing one to change.
struct LimitTarget: Identifiable {
    let limit: PlanSummary.Limit?
    var id: String { limit?.key ?? "new" }
}

// MARK: - The plan

/// The budget as one bar in three parts, with what each part is.
private struct PlanCard: View {
    @Environment(AppSession.self) private var session
    private var plan: PlanModel { session.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cap = plan.cap {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel("Budget")
                    Spacer()
                    Button("Edit") { session.isEditingBudget = true }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 32)
                }
                Text(Money.whole(cap, plan.currencyCode))
                    .font(.figure(44))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: (cap as NSDecimalNumber).doubleValue))
                    .padding(.top, 2)

                PlanBar(cap: cap, bills: plan.billsTotal, everyday: plan.everydaySpent, isOver: plan.isOver)
                    .frame(height: 16)
                    .padding(.top, 18)

                VStack(spacing: 0) {
                    LegendRow(swatch: .bills, title: "Bills",
                              detail: billsDetail,
                              amount: plan.billsTotal, currencyCode: plan.currencyCode)
                    LegendRow(swatch: .everyday, title: "Everyday spending",
                              detail: "of \(Money.whole(plan.everydayBudget, plan.currencyCode)) after bills",
                              amount: plan.everydaySpent, currencyCode: plan.currencyCode)
                    if plan.isOver {
                        LegendRow(swatch: .over, title: "Over budget",
                                  detail: "including the bills still to come",
                                  amount: plan.overBy, currencyCode: plan.currencyCode, emphasis: Palette.caution)
                    } else {
                        LegendRow(swatch: .left, title: "Left to spend",
                                  detail: "\(Money.whole(plan.perDay, plan.currencyCode)) a day for \(plan.daysLeft) \(plan.daysLeft == 1 ? "day" : "days")",
                                  amount: plan.left, currencyCode: plan.currencyCode, emphasis: Palette.ink)
                    }
                }
                .padding(.top, 14)
            } else {
                NoBudget()
            }
        }
        .padding(18)
        .background(Palette.surface, in: .rect(cornerRadius: 24))
        .animation(.snappy(duration: 0.45), value: plan.cap)
        .animation(.snappy(duration: 0.45), value: plan.left)
    }

    private var billsDetail: String {
        if plan.billsTotal == 0 { return "nothing repeating this month" }
        if plan.billsComing == 0 { return "all paid this month" }
        return "\(Money.whole(plan.billsComing, plan.currencyCode)) still to come"
    }
}

/// No budget yet: what one would do, and a suggestion from real spending.
private struct NoBudget: View {
    @Environment(AppSession.self) private var session
    private var plan: PlanModel { session.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Budget")
            Text("No monthly budget yet")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 8)
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Button(plan.suggestedBudget.map { "Set \(Money.whole($0, plan.currencyCode)) a month" } ?? "Set a budget") {
                session.isEditingBudget = true
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            .padding(.top, 18)
        }
    }

    private var detail: String {
        let base = "Set one and Artha splits it into bills, everyday spending and what's left, every day."
        guard let usual = plan.summary?.typical.map({ Decimal.api($0.overall) }), usual > 0 else { return base }
        return "You've spent about \(Money.whole(usual, plan.currencyCode)) a month lately. " + base
    }
}

private enum Swatch {
    case bills, everyday, left, over

    var color: Color {
        switch self {
        case .bills: Palette.ink.opacity(0.82)
        case .everyday: Palette.accent
        case .left: Palette.raised
        case .over: Palette.cautionLine
        }
    }
}

/// Bills, then everyday spending, then what's left, as parts of the budget.
private struct PlanBar: View {
    let cap: Decimal
    let bills: Decimal
    let everyday: Decimal
    let isOver: Bool

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let total = max((cap as NSDecimalNumber).doubleValue, (bills + everyday as NSDecimalNumber).doubleValue, 1)
            let width = proxy.size.width - gap * 2
            let billsWidth = width * (bills as NSDecimalNumber).doubleValue / total
            let everydayWidth = width * (everyday as NSDecimalNumber).doubleValue / total
            HStack(spacing: gap) {
                Capsule().fill(Swatch.bills.color).frame(width: max(billsWidth, bills > 0 ? 4 : 0))
                Capsule().fill(Swatch.everyday.color).frame(width: max(everydayWidth, everyday > 0 ? 4 : 0))
                Capsule().fill(isOver ? Swatch.over.color : Swatch.left.color)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LegendRow: View {
    let swatch: Swatch
    let title: String
    let detail: String
    let amount: Decimal
    let currencyCode: String
    var emphasis: Color = Palette.ink

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatch.color)
                .overlay {
                    if swatch == .left {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Palette.secondary.opacity(0.4), lineWidth: 1)
                    }
                }
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            Text(Money.whole(amount, currencyCode))
                .font(.figure(18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(emphasis)
                .contentTransition(.numericText(value: (amount as NSDecimalNumber).doubleValue))
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bills

private struct BillsSection: View {
    @Environment(AppSession.self) private var session
    private var plan: PlanModel { session.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Bills this month")
                Spacer()
                if plan.billsTotal > 0 {
                    Text(Money.whole(plan.billsTotal, plan.currencyCode))
                        .font(.figure(17, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(.horizontal, 4)

            if plan.bills.isEmpty {
                Text("Bills that repeat, like rent or a subscription, show up here with what's paid and what's still to come.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: .rect(cornerRadius: 20))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(plan.bills.enumerated()), id: \.element.id) { index, bill in
                        BillRowView(bill: bill, displayCurrency: plan.currencyCode)
                        if index < plan.bills.count - 1 {
                            Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1).padding(.leading, 60)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Palette.surface, in: .rect(cornerRadius: 20))
            }
        }
    }
}

private struct BillRowView: View {
    let bill: PlanModel.BillRow
    let displayCurrency: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(bill.weekday)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(bill.isSoon ? Palette.caution : Palette.secondary)
                Text(bill.day)
                    .font(.figure(22, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(bill.isPaid ? Palette.secondary : Palette.ink)
            }
            .frame(width: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(bill.isPaid ? Palette.secondary : Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if bill.isPaid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.good)
                    }
                    Text(bill.detail)
                }
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.natural(bill.amount, bill.currencyCode))
                    .font(.figure(16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(bill.isPaid ? Palette.secondary : Palette.ink)
                if let equivalent = bill.displayEquivalent {
                    Text("≈ \(Money.whole(equivalent, displayCurrency))")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Category limits

private struct LimitsSection: View {
    @Environment(AppSession.self) private var session
    @Binding var editingLimit: LimitTarget?
    private var plan: PlanModel { session.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Category limits")
                Spacer()
                if !plan.limits.isEmpty, !plan.unbudgeted.isEmpty {
                    Button("Add", systemImage: "plus") { editingLimit = LimitTarget(limit: nil) }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 32)
                }
            }
            .padding(.horizontal, 4)

            if plan.limits.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Keep an eye on one category, like Dining, without budgeting every dollar. Artha tells you when it's getting close.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Add a limit") { editingLimit = LimitTarget(limit: nil) }
                        .buttonStyle(CapsuleButtonStyle())
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: .rect(cornerRadius: 20))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(plan.limits.enumerated()), id: \.element.key) { index, limit in
                        Button { editingLimit = LimitTarget(limit: limit) } label: {
                            LimitRow(limit: limit, currencyCode: plan.currencyCode)
                        }
                        .buttonStyle(.plain)
                        if index < plan.limits.count - 1 {
                            Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Palette.surface, in: .rect(cornerRadius: 20))
            }
        }
    }
}

private struct LimitRow: View {
    let limit: PlanSummary.Limit
    let currencyCode: String

    private var fraction: Double { min(limit.percentUsed / 100, 1) }
    private var tint: Color {
        switch limit.tier {
        case "over": Palette.caution
        case "warning": Palette.cautionLine
        default: Palette.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: CategoryStyle.symbol(for: limit.key, type: "expense"))
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Palette.raised, in: .rect(cornerRadius: 10))
                    .foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text(limit.label)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text("\(Money.whole(Decimal.api(limit.spent), currencyCode)) of \(Money.whole(Decimal.api(limit.cap), currencyCode))")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 8)
                Text(limit.tier == "over"
                     ? "\(Money.whole(Decimal.api(limit.overBy), currencyCode)) over"
                     : "\(Money.whole(Decimal.api(limit.left), currencyCode)) left")
                    .font(.figure(16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(limit.tier == "over" ? Palette.caution : Palette.ink)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.raised)
                    Capsule().fill(tint).frame(width: max(proxy.size.width * fraction, fraction > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Change or remove this limit")
    }
}
