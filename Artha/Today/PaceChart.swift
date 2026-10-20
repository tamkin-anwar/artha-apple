import Charts
import SwiftUI

/// The month so far against an even pace to the budget. Drag across it to
/// read any day: the selection ticks a haptic on each day and the glass
/// label follows your finger. It can't be dragged past today.
struct PaceChart: View {
    @Environment(MonthModel.self) private var month
    @State private var selectedDay: Int?

    private var lineColor: Color {
        month.status == .onPace ? Palette.accent : Palette.cautionLine
    }

    private var activeDay: Int {
        min(selectedDay ?? month.today, month.today)
    }

    /// Headroom above the higher of the budget and what's been spent, so the
    /// glass label always has clear sky to sit in instead of covering the line.
    private var yMax: Double {
        let budget = (month.budget as NSDecimalNumber).doubleValue
        return max(budget, month.cumulative.map(\.amount).max() ?? 0) * 1.32
    }

    var body: some View {
        Chart {
            ForEach([1, month.daysInMonth], id: \.self) { day in
                LineMark(x: .value("Day", day),
                         y: .value("Amount", month.paceAmount(on: day)),
                         series: .value("Line", "Even pace"))
                    .foregroundStyle(Palette.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
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
                        ChartLabel(day: activeDay, amount: amount, isToday: activeDay == month.today)
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
            VStack(alignment: .trailing, spacing: 0) {
                Text("Even pace")
                Text("to \(Money.whole(month.budget))")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.secondary)
        }
        .safeAreaInset(edge: .bottom, spacing: 6) {
            HStack {
                Text("Oct 1")
                Spacer()
                Text("Oct \(month.daysInMonth)")
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("Spending this month")
        .accessibilityValue("\(Money.whole(month.spent)) spent by October \(month.today). Even pace would be \(Money.whole(Decimal(month.paceAmount(on: month.today)))).")
    }
}

private struct ChartLabel: View {
    let day: Int
    let amount: Double
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isToday ? "Today, Oct \(day)" : "Oct \(day)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            Text("\(Money.whole(Decimal(amount))) spent")
                .font(.figure(16))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
