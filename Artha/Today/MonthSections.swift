import SwiftUI

/// "Where October went": a full-width band, the top three categories and
/// everything else, told apart by four clear steps of white.
struct WhereItWent: View {
    @Environment(MonthModel.self) private var month
    private let opacities: [Double] = [1, 0.66, 0.4, 0.12]

    var body: some View {
        let shares = month.shares
        let total = max(1, (month.spent as NSDecimalNumber).doubleValue)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("WHERE \(month.monthName.uppercased()) WENT")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1)
                Spacer()
                Text(Money.whole(month.spent))
                    .font(.figure(22))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: total))
            }
            GeometryReader { proxy in
                let available = proxy.size.width - CGFloat(shares.count - 1) * 3
                HStack(spacing: 3) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        Swatch(opacity: opacities[index], outlined: index == shares.count - 1, radius: 5)
                            .frame(width: max(0, available * (share.amount as NSDecimalNumber).doubleValue / total))
                    }
                }
            }
            .frame(height: 18)
            .accessibilityElement()
            .accessibilityLabel(shares.map { "\($0.name) \(Money.whole($0.amount))" }.joined(separator: ", "))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)],
                      alignment: .leading, spacing: 11) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: 8) {
                        Swatch(opacity: opacities[index], outlined: index == shares.count - 1, radius: 3)
                            .frame(width: 10, height: 10)
                        Text(share.name)
                            .font(.system(size: 15))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text(Money.whole(share.amount))
                            .font(.figure(16))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.band)
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
            HStack(spacing: 10) {
                ForEach(month.bills) { bill in
                    BillCard(bill: bill)
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
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(bill.isSoon ? Palette.caution : Palette.secondary)
                .lineLimit(1)
            Text(bill.date)
                .font(.figure(42, weight: .black))
                .foregroundStyle(Palette.ink)
            Text(bill.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.top, 8)
            Text(bill.isThisMonth ? Money.cents(bill.amount) : Money.whole(bill.amount))
                .font(.system(size: 14))
                .monospacedDigit()
                .foregroundStyle(Palette.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 20))
        .overlay {
            if bill.isSoon {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.cautionLine.opacity(0.55), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecentList: View {
    @Environment(MonthModel.self) private var month

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Recent")
                Spacer()
                Button("See all") {}
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
            }
            ForEach(Array(month.recent.enumerated()), id: \.element.id) { index, expense in
                ExpenseRow(expense: expense)
                    .transition(.move(edge: .top).combined(with: .opacity))
                if index < month.recent.count - 1 {
                    Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                }
            }
        }
        .animation(.snappy(duration: 0.4), value: month.addCount)
    }
}

private struct ExpenseRow: View {
    let expense: MonthModel.Expense

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: expense.symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .background(Palette.raised, in: .rect(cornerRadius: 12))
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(expense.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.native(expense.amount, code: expense.currencyCode))
                    .font(.figure(17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                if let usd = expense.usdEquivalent {
                    Text("≈ \(Money.cents(usd))")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}
