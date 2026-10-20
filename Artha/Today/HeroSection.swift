import SwiftUI

/// The one big number. Safe to spend by default; the label is a menu so
/// each person can lead with the number they care about.
struct HeroSection: View {
    @Environment(MonthModel.self) private var month

    var body: some View {
        @Bindable var month = month
        VStack(alignment: .leading, spacing: 0) {
            Menu {
                Picker("Show on Today", selection: $month.heroMetric) {
                    ForEach(MonthModel.HeroMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(month.heroMetric.rawValue)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .frame(minHeight: 32)
            }

            Text(Money.whole(month.heroValue))
                .font(.figure(76))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: (month.heroValue as NSDecimalNumber).doubleValue))
                .animation(.snappy(duration: 0.5), value: month.heroValue)
                .padding(.top, 2)

            HStack(spacing: 10) {
                if month.heroMetric != .netWorth {
                    StatusBadge(status: month.status, overBy: month.overBy)
                }
                Text(subtitle)
                    .font(.system(size: 15))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.5), value: subtitle)
            }
            .padding(.top, 14)
        }
    }

    private var subtitle: String {
        switch month.heroMetric {
        case .safeToSpend:
            month.status == .over
                ? "November starts in \(month.daysLeft) days"
                : "\(Money.whole(month.perDay)) a day for \(month.daysLeft) days"
        case .spentThisMonth:
            "of \(Money.whole(month.budget)) budget"
        case .netWorth:
            "Up $1,140 this month"
        }
    }
}

/// One color per state, and it only changes when the state does.
struct StatusBadge: View {
    let status: MonthModel.Status
    let overBy: Decimal

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
            Text(text)
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(color)
        .padding(.leading, 8)
        .padding(.trailing, 11)
        .frame(height: 28)
        .background(color.opacity(0.14), in: Capsule())
        .contentTransition(.interpolate)
        .animation(.snappy(duration: 0.35), value: text)
    }

    private var text: String {
        switch status {
        case .onPace: "On pace"
        case .ahead: "Ahead of pace"
        case .over: "Over by \(Money.whole(overBy))"
        }
    }

    private var symbol: String {
        switch status {
        case .onPace: "checkmark"
        case .ahead: "arrow.up.right"
        case .over: "exclamationmark"
        }
    }

    private var color: Color {
        status == .onPace ? Palette.good : Palette.caution
    }
}
