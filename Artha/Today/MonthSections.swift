import SwiftUI

/// "Where October went": a full-width band, the top three categories and
/// everything else, told apart by four clear steps of white.
struct WhereItWent: View {
    @Environment(MonthModel.self) private var month
    @Environment(\.dynamicTypeSize) private var typeSize
    /// A rounded card in a column (wide screens) instead of a full-width band.
    var asCard = false
    private let opacities: [Double] = [1, 0.66, 0.4, 0.12]

    var body: some View {
        let shares = month.shares
        let total = max(1, (shares.reduce(Decimal(0)) { $0 + $1.amount } as NSDecimalNumber).doubleValue)
        // At accessibility text sizes the title and total stack instead of
        // sharing a line they no longer fit on.
        let header = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        VStack(alignment: .leading, spacing: 16) {
            header {
                Text("WHERE \(month.monthName.uppercased()) WENT")
                    .font(.system(.footnote, weight: .bold))
                    .tracking(1)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text(Money.whole(month.spent, month.currencyCode))
                    .figureFont(22)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: (month.spent as NSDecimalNumber).doubleValue))
            }
            GeometryReader { proxy in
                let available = proxy.size.width - CGFloat(max(shares.count - 1, 0)) * 3
                HStack(spacing: 3) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        Swatch(opacity: opacities[min(index, opacities.count - 1)],
                               outlined: index == opacities.count - 1, radius: 5)
                            .frame(width: max(0, available * (share.amount as NSDecimalNumber).doubleValue / total))
                    }
                }
            }
            .frame(height: 18)
            .accessibilityElement()
            .accessibilityLabel(shares.map { "\($0.name) \(Money.whole($0.amount, month.currencyCode))" }.joined(separator: ", "))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)],
                      alignment: .leading, spacing: 1) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    NavigationLink(value: TodayRoute.category(.init(name: share.name, keys: share.keys))) {
                        HStack(spacing: 8) {
                            Swatch(opacity: opacities[min(index, opacities.count - 1)],
                                   outlined: index == opacities.count - 1, radius: 3)
                                .frame(width: 10, height: 10)
                            Text(share.name)
                                .font(.system(.subheadline))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                            Spacer(minLength: 4)
                            Text(Money.whole(share.amount, month.currencyCode))
                                .figureFont(16)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Shows these transactions")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.band, in: .rect(cornerRadius: asCard ? 24 : 0))
        .animation(.snappy(duration: 0.45), value: month.spent)
    }
}

private struct Swatch: View {
    let opacity: Double
    let outlined: Bool
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.white.opacity(opacity))
            .overlay {
                if outlined {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                }
            }
    }
}

/// The next three bills as cards with big dates; the soonest is outlined.
struct ComingUp: View {
    @Environment(MonthModel.self) private var month

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Coming up")
                .padding(.horizontal, 20)
            HStack(alignment: .top, spacing: 10) {
                ForEach(month.bills) { bill in
                    BillCard(bill: bill)
                }
                ForEach(month.bills.count..<3, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct BillCard: View {
    let bill: MonthModel.Bill

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(bill.label)
                .font(.system(.caption2, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(bill.isSoon ? Palette.caution : Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(bill.date)
                .figureFont(42, weight: .black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Palette.ink)
            Text(bill.name)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.top, 8)
            Text(Money.natural(bill.amount, bill.currencyCode))
                .font(.system(.subheadline))
                .monospacedDigit()
                .foregroundStyle(Palette.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
        .overlay {
            if bill.isSoon {
                RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.cautionLine.opacity(0.55), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecentList: View {
    @Environment(MonthModel.self) private var month

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Recent")
                .frame(minHeight: 44)
            ForEach(Array(month.recent.enumerated()), id: \.element.id) { index, expense in
                NavigationLink(value: TodayRoute.transaction(expense.id, fallback: nil)) {
                    TransactionRow(expense: expense, displayCurrency: month.currencyCode)
                }
                .buttonStyle(.plain)
                .motionTransition(.move(edge: .top).combined(with: .opacity))
                if index < month.recent.count - 1 {
                    Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                }
            }
        }
        .animation(.snappy(duration: 0.4), value: month.recent.map(\.id))
    }
}
