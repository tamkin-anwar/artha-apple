import Charts
import SwiftUI

/// The month so far against an even pace to the budget. Drag across it to
/// read any day: the selection ticks a haptic on each day and the glass
/// label follows your finger. It can't be dragged past today. Without a
/// budget there's no pace to draw, just the month's spending.
struct PaceChart: View {
    @Environment(MonthModel.self) private var month
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDay: Int?

    private var lineColor: Color {
        !month.hasBudget || month.status == .onPace ? Palette.accent : Palette.cautionLine
    }

    private var activeDay: Int {
        min(selectedDay ?? month.today, month.today)
    }

    /// Headroom above the higher of the budget and what's been spent, so the
    /// glass label always has clear sky to sit in instead of covering the line.
    private var yMax: Double {
        let budget = month.budget.map { ($0 as NSDecimalNumber).doubleValue } ?? 0
        return max(budget, month.cumulative.map(\.amount).max() ?? 0, 1) * 1.32
    }

    var body: some View {
        Chart {
            if month.hasBudget {
                ForEach([1, month.daysInMonth], id: \.self) { day in
                    LineMark(x: .value("Day", day),
                             y: .value("Amount", month.paceAmount(on: day) ?? 0),
                             series: .value("Line", "Even pace"))
                        .foregroundStyle(Palette.secondary.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                }
            }
            ForEach(month.cumulative) { point in
                AreaMark(x: .value("Day", point.day), y: .value("Amount", point.amount))
                    .foregroundStyle(LinearGradient(colors: [lineColor.opacity(0.3), lineColor.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", point.day),
                         y: .value("Amount", point.amount),
                         series: .value("Line", "Spent"))
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let amount = month.amount(on: activeDay) {
                RuleMark(x: .value("Day", activeDay))
                    .foregroundStyle(Palette.ink.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Day", activeDay), y: .value("Amount", amount))
                    .symbolSize(90)
                    .foregroundStyle(lineColor)
                    .annotation(position: .top, spacing: 10,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartLabel(day: activeDay, amount: amount, isToday: activeDay == month.today,
                                   monthName: month.monthName, currencyCode: month.currencyCode)
                    }
            }
        }
        .chartXScale(domain: 1...month.daysInMonth)
        .chartYScale(domain: 0...yMax)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartXSelection(value: $selectedDay)
        .sensoryFeedback(.selection, trigger: selectedDay)
        .animation(.snappy(duration: 0.45), value: month.spent)
        .frame(height: 230)
        .overlay(alignment: .topTrailing) {
            // At accessibility sizes this caption moves under the chart,
            // where it can't collide with the day's label.
            if let budget = month.budget, !typeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Even pace")
                    Text("to \(Money.whole(budget, month.currencyCode))")
                }
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(shortMonth) 1")
                    Spacer()
                    Text("\(shortMonth) \(month.daysInMonth)")
                }
                if let budget = month.budget, typeSize.isAccessibilitySize {
                    Text("Dashed line: an even pace to \(Money.whole(budget, month.currencyCode))")
                }
            }
            .font(.system(.caption))
            .foregroundStyle(Palette.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("Spending this month")
        .accessibilityValue(accessibilityValue)
        .accessibilityChartDescriptor(audioGraph)
    }

    /// The same line as an Audio Graph, with the even pace as a second
    /// series when there's a budget.
    private var audioGraph: AudioGraph {
        let days = month.cumulative.map(\.day)
        var series = [AudioGraph.Series(name: "Spent", values: month.cumulative.map(\.amount))]
        if month.hasBudget {
            series.append(.init(name: "Even pace", values: days.map { month.paceAmount(on: $0) ?? 0 }))
        }
        return AudioGraph(title: "Spending this month", summary: accessibilityValue,
                          categoryTitle: "Day", categories: days.map { "\(shortMonth) \($0)" },
                          valueTitle: "Spent", currencyCode: month.currencyCode, series: series)
    }

    private var shortMonth: String { String(month.monthName.prefix(3)) }

    private var accessibilityValue: String {
        let spent = Money.whole(month.spent, month.currencyCode)
        guard let pace = month.paceAmount(on: month.today) else {
            return "\(spent) spent so far."
        }
        return "\(spent) spent so far. An even pace would be \(Money.whole(Decimal(pace), month.currencyCode))."
    }
}

private struct ChartLabel: View {
    let day: Int
    let amount: Double
    let isToday: Bool
    let monthName: String
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isToday ? "Today, \(monthName.prefix(3)) \(day)" : "\(monthName.prefix(3)) \(day)")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            Text("\(Money.whole(Decimal(amount), currencyCode)) spent")
                .figureFont(16)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Solid, not glass: the chart's lines showed through glass and ran
        // across the figures. Glass is for floating controls; this is a label.
        .background(Palette.surface, in: .rect(cornerRadius: Radius.inner))
        .overlay(RoundedRectangle(cornerRadius: Radius.inner).strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1))
    }
}
