import SwiftUI

/// One transaction as a row, the same on Today and in Activity: a symbol
/// for its category, the name and a detail line, and the amount in its own
/// currency (plus the display-currency equivalent when they differ).
struct TransactionRow: View {
    let expense: MonthModel.Expense
    let displayCurrency: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: expense.symbol)
                .font(.system(.body, weight: .medium))
                .frame(width: 40, height: 40)
                .background(Palette.raised, in: .rect(cornerRadius: Radius.inner))
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(expense.detail)
                    .font(.system(.footnote))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((expense.isIncome ? "+" : "") + Money.cents(expense.amount, expense.currencyCode))
                    .figureFont(17, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(expense.isIncome ? Palette.good : Palette.ink)
                if let equivalent = expense.displayEquivalent {
                    Text("≈ \(Money.cents(equivalent, displayCurrency))")
                        .font(.system(.caption))
                        .foregroundStyle(Palette.secondary)
                }
            }
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
