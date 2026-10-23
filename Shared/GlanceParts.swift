import Charts
import SwiftUI
import WidgetKit

// The pieces of a Safe to Spend glance, drawn the same way in a widget and
// in the card Siri and Shortcuts show.

struct GlanceHeader: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            OrbMark().frame(width: 14, height: 14)
            Text(text.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct GlanceNumber: View {
    let glance: Glance
    var size: CGFloat = 36

    var body: some View {
        Text(Money.whole(glance.value, glance.code))
            .font(.figure(size))
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .contentTransition(.numericText(value: (glance.value as NSDecimalNumber).doubleValue))
            .widgetAccentable()
    }
}

struct GlanceStatus: View {
    let glance: Glance

    var body: some View {
        if let text = glance.statusText {
            HStack(spacing: 5) {
                Circle().fill(glance.statusColor).frame(width: 7, height: 7)
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(glance.statusColor)
            }
        }
    }
}

struct SmallGlance: View {
    let glance: Glance

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlanceHeader(text: glance.label)
            Spacer(minLength: 4)
            GlanceNumber(glance: glance, size: 38)
            Text(glance.detail)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.top, 2)
            Spacer(minLength: 4)
            GlanceStatus(glance: glance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The month so far against an even pace, small enough for a widget.
struct MiniPace: View {
    let glance: Glance

    var body: some View {
        let days = glance.summary.month.daysInMonth
        let top = max(glance.paceTop ?? 0, glance.points.map(\.amount).max() ?? 0, 1) * 1.08
        Chart {
            if let pace = glance.paceTop {
                ForEach([1, days], id: \.self) { day in
                    LineMark(x: .value("Day", day), y: .value("Amount", pace * Double(day) / Double(days)),
                             series: .value("Line", "Pace"))
                        .foregroundStyle(Palette.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            ForEach(glance.points) { point in
                AreaMark(x: .value("Day", point.day), y: .value("Amount", point.amount))
                    .foregroundStyle(LinearGradient(colors: [glance.lineColor.opacity(0.28), glance.lineColor.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", point.day), y: .value("Amount", point.amount),
                         series: .value("Line", "Spent"))
                    .foregroundStyle(glance.lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .widgetAccentable()
        .chartXScale(domain: 1...days)
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }
}
