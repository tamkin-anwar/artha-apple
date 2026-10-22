import Charts
import SwiftUI

/// The last six months side by side, at the bottom of Plan. What people
/// love in YNAB's Reflect, Copilot's cash flow and Rocket Money's spending
/// bars, without their extra screens: one plain sentence first ("You
/// usually spend $2,840 a month"), then a bar for each month's spending
/// beside what came in, with the usual level drawn across. Tap a month to
/// see it, its biggest categories, and how each moved from the month
/// before. Spending is the solid bar and what came in the softer one,
/// since spending is what this is about; only the month being read is at
/// full strength. A first month that began partway through says so, and
/// isn't counted toward the usual.
struct MonthByMonth: View {
    @Environment(AppSession.self) private var session
    @State private var selected: String?

    private var plan: PlanModel { session.plan }

    var body: some View {
        if let history = plan.history, !history.months.isEmpty {
            content(history)
        }
    }

    private func content(_ history: HistorySummary) -> some View {
        let months = history.months
        let shown = months.first { $0.month == selected } ?? months[months.count - 1]
        let tracksIncome = months.contains { Decimal.api($0.income) > 0 }
        let average = history.averageSpent.map { Decimal.api($0) }

        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Month by month")
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                headline(average: average, current: months.last, currency: history.currency)

                if months.count > 1 {
                    chart(months, tracksIncome: tracksIncome, average: average, shown: shown)
                        .padding(.top, 18)
                    legend(tracksIncome: tracksIncome, hasAverage: average != nil)
                        .padding(.top, 10)
                }

                Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                    .padding(.vertical, 16)

                MonthDetail(month: shown,
                            previous: previousMonth(before: shown, in: months),
                            tracksIncome: tracksIncome,
                            currency: history.currency)
            }
            .padding(18)
            .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
        }
        .animation(.snappy(duration: 0.3), value: shown.month)
    }

    /// The month to compare against, unless it only covers a few days
    /// (a first month that began partway through), which would make every
    /// category look new.
    private func previousMonth(before month: HistorySummary.Month,
                               in months: [HistorySummary.Month]) -> HistorySummary.Month? {
        guard let index = months.firstIndex(where: { $0.month == month.month }), index > 0 else { return nil }
        let previous = months[index - 1]
        return previous.started == nil ? previous : nil
    }

    // MARK: Headline

    @ViewBuilder
    private func headline(average: Decimal?, current: HistorySummary.Month?, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let average {
                Text("You usually spend \(Money.whole(average, currency)) a month")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let current, current.isCurrent {
                    Text(paceLine(current, average: average, currency: currency))
                        .font(.system(.subheadline))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if (plan.history?.months.count ?? 0) > 1 {
                Text("Your first full month is underway")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("When it ends, Artha shows what you usually spend, and how each month compares.")
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Your first month with Artha")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("Each month you finish adds a bar here, so you can see how they compare.")
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Where this month stands against the usual, said plainly.
    private func paceLine(_ month: HistorySummary.Month, average: Decimal, currency: String) -> String {
        let spent = Decimal.api(month.spent)
        let soFar = "\(month.name) so far: \(Money.whole(spent, currency))"
        if spent > average {
            return "\(soFar), \(Money.whole(spent - average, currency)) past the usual."
        }
        return "\(soFar), \(Money.whole(average - spent, currency)) under the usual."
    }

    // MARK: Chart

    private func chart(_ months: [HistorySummary.Month], tracksIncome: Bool, average: Decimal?,
                       shown: HistorySummary.Month) -> some View {
        Chart {
            ForEach(months, id: \.month) { month in
                let isShown = month.month == shown.month
                BarMark(x: .value("Month", month.label),
                        y: .value("Amount", (Decimal.api(month.spent) as NSDecimalNumber).doubleValue),
                        width: .ratio(tracksIncome ? 0.4 : 0.5))
                    .foregroundStyle(Palette.accent)
                    .cornerRadius(4)
                    .position(by: .value("Kind", "Spent"))
                    .opacity(isShown ? 1 : 0.4)
                    .accessibilityLabel(month.name)
                    .accessibilityValue("\(Money.whole(Decimal.api(month.spent), session.plan.currencyCode)) spent")
                if tracksIncome {
                    BarMark(x: .value("Month", month.label),
                            y: .value("Amount", (Decimal.api(month.income) as NSDecimalNumber).doubleValue),
                            width: .ratio(0.4))
                        .foregroundStyle(Palette.good.opacity(0.5))
                        .cornerRadius(4)
                        .position(by: .value("Kind", "Earned"))
                        .opacity(isShown ? 1 : 0.4)
                        .accessibilityLabel(month.name)
                        .accessibilityValue("\(Money.whole(Decimal.api(month.income), session.plan.currencyCode)) came in")
                }
            }
            if let average {
                RuleMark(y: .value("Usual", (average as NSDecimalNumber).doubleValue))
                    .foregroundStyle(Palette.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                    .accessibilityLabel("Usual spending")
                    .accessibilityValue(Money.whole(average, session.plan.currencyCode))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(.caption, weight: label == shown.label ? .bold : .regular))
                            .foregroundStyle(label == shown.label ? Palette.ink : Palette.secondary)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartXSelection(value: Binding(
            get: { shown.label },
            set: { label in
                guard let label, let month = months.first(where: { $0.label == label }) else { return }
                selected = month.month
            }))
        // Selection follows a drag; a plain tap on a month picks it too,
        // since tapping a bar is what people try first.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let frame = proxy.plotFrame else { return }
                        let x = location.x - geometry[frame].origin.x
                        guard let label: String = proxy.value(atX: x),
                              let month = months.first(where: { $0.label == label }) else { return }
                        selected = month.month
                    }
            }
        }
        .sensoryFeedback(.selection, trigger: shown.month)
        .frame(height: 170)
    }

    private func legend(tracksIncome: Bool, hasAverage: Bool) -> some View {
        HStack(spacing: 16) {
            LegendItem(title: "Spent") {
                RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 10, height: 10)
            }
            if tracksIncome {
                LegendItem(title: "Came in") {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.good.opacity(0.5)).frame(width: 10, height: 10)
                }
            }
            if hasAverage {
                LegendItem(title: "Usual") {
                    Capsule().fill(Palette.secondary.opacity(0.7)).frame(width: 14, height: 2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

private struct LegendItem<Swatch: View>: View {
    let title: String
    @ViewBuilder let swatch: Swatch

    var body: some View {
        HStack(spacing: 6) {
            swatch
            Text(title)
                .font(.system(.caption))
                .foregroundStyle(Palette.secondary)
        }
    }
}

/// One month: spent, what came in and what was kept, then its biggest
/// categories and how each moved from the month before.
private struct MonthDetail: View {
    let month: HistorySummary.Month
    let previous: HistorySummary.Month?
    let tracksIncome: Bool
    let currency: String

    var body: some View {
        let spent = Decimal.api(month.spent)
        let income = Decimal.api(month.income)
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(Palette.ink)

            HStack(alignment: .top, spacing: 0) {
                Figure(title: "Spent", value: Money.whole(spent, currency))
                if tracksIncome {
                    Figure(title: "Came in", value: Money.whole(income, currency))
                    // A month with no income logged isn't "short", it's
                    // just not recorded, so say nothing rather than alarm.
                    if income == 0 {
                        Spacer().frame(maxWidth: .infinity)
                    } else if income >= spent {
                        Figure(title: "Kept", value: Money.whole(income - spent, currency), tint: Palette.good)
                    } else {
                        Figure(title: "Short by", value: Money.whole(spent - income, currency), tint: Palette.caution)
                    }
                }
            }

            if !month.categories.isEmpty {
                VStack(spacing: 10) {
                    ForEach(month.categories.prefix(4), id: \.label) { category in
                        CategoryLine(category: category,
                                     before: previous?.categories.first { $0.key == category.key },
                                     hasPrevious: previous != nil,
                                     previousName: previous?.name,
                                     currency: currency)
                    }
                }
            } else {
                Text("Nothing spent yet.")
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}

private extension MonthDetail {
    var title: String {
        if month.isCurrent { return "\(month.name) so far" }
        if let started = month.started, let day = Date.apiDay(started) {
            return "\(month.name) \(String(month.year)), from \(day.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return "\(month.name) \(String(month.year))"
    }
}

private struct Figure: View {
    let title: String
    let value: String
    var tint: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.caption))
                .foregroundStyle(Palette.secondary)
            Text(value)
                .figureFont(18)
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct CategoryLine: View {
    let category: HistorySummary.Month.Category
    let before: HistorySummary.Month.Category?
    let hasPrevious: Bool
    let previousName: String?
    let currency: String

    var body: some View {
        let amount = Decimal.api(category.amount)
        HStack(spacing: 12) {
            Image(systemName: CategoryStyle.symbol(for: category.key, type: "expense"))
                .font(.system(.footnote, weight: .medium))
                .frame(width: 30, height: 30)
                .background(Palette.raised, in: .rect(cornerRadius: Radius.small))
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.label)
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.ink)
                if let change {
                    Text(change)
                        .font(.system(.caption))
                        .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(Money.whole(amount, currency))
                .figureFont(15)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Up $120 from September", "Down $40", or "New in October" when the
    /// month before had none. Nothing for the first month shown.
    private var change: String? {
        guard hasPrevious, let previousName else { return nil }
        let amount = Decimal.api(category.amount)
        guard let before else { return "None in \(previousName)" }
        let difference = amount - Decimal.api(before.amount)
        let rounded = Money.whole(abs(difference), currency)
        if rounded == Money.whole(0, currency) { return "Same as \(previousName)" }
        return difference > 0 ? "Up \(rounded) from \(previousName)" : "Down \(rounded) from \(previousName)"
    }
}
