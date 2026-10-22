import SwiftUI

/// One transaction as a row, the same on Today and in Activity: a symbol
/// for its category, the name and a detail line, and the amount in its own
/// currency (plus the display-currency equivalent when they differ).
struct TransactionRow: View {
    let expense: MonthModel.Expense
    let displayCurrency: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes a side-by-side row leaves the amount a
        // sliver and it breaks mid-number ("$6.7" / "5"), so the row stacks:
        // name and detail, then the amount on its own line, and the symbol
        // tile steps aside to give the words the width.
        let isLarge = typeSize.isAccessibilitySize
        let layout = isLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 14))
        layout {
            if !isLarge {
                Image(systemName: expense.symbol)
                    .font(.system(.body, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Palette.raised, in: .rect(cornerRadius: Radius.inner))
                    .foregroundStyle(Palette.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(isLarge ? 4 : 1)
                Text(expense.detail)
                    .font(.system(.footnote))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(isLarge ? 3 : 1)
            }
            if !isLarge { Spacer(minLength: 8) }
            VStack(alignment: isLarge ? .leading : .trailing, spacing: 2) {
                Text((expense.isIncome ? "+" : "") + Money.cents(expense.amount, expense.currencyCode))
                    .figureFont(17, weight: .bold)
                    .monospacedDigit()
                    .lineLimit(1)
                    // Only stacked rows may shrink a long figure to fit; side by
                    // side it was shrinking even with room to spare (a 60%
                    // "$6.75" in Today's Recent on iPad).
                    .minimumScaleFactor(isLarge ? 0.6 : 1)
                    .foregroundStyle(expense.isIncome ? Palette.good : Palette.ink)
                if let equivalent = expense.displayEquivalent {
                    Text("≈ \(Money.cents(equivalent, displayCurrency))")
                        .font(.system(.caption))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The SF Symbol for each of the web app's categories
/// (finance.routes.TRANSACTION_CATEGORIES).
enum CategoryStyle {
    static func symbol(for category: String?, type: String) -> String {
        if type == "income" { return "arrow.down.left" }
        switch category {
        case "groceries": return "cart"
        case "dining": return "fork.knife"
        case "transport": return "car"
        case "housing": return "house"
        case "utilities": return "bolt"
        case "subscriptions": return "repeat"
        case "shopping": return "bag"
        case "health": return "heart"
        case "entertainment": return "film"
        case "debt": return "creditcard"
        case "income": return "arrow.down.left"
        default: return "circle.grid.2x2"
        }
    }
}
