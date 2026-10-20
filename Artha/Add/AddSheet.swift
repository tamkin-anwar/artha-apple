import SwiftUI

/// Add in two taps: the Apple Pay purchase has already filled everything in,
/// and Artha remembered the merchant's category from last time.
struct AddSheet: View {
    @Environment(MonthModel.self) private var month
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "Expense"

    private let amount: Decimal = 6.75

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.secondary)
                    .frame(minHeight: 44)
                Spacer()
                Picker("Type", selection: $kind) {
                    ForEach(["Expense", "Income", "Transfer"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }

            HStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 15))
                    .frame(width: 34, height: 34)
                    .background(Palette.inverse, in: .rect(cornerRadius: 10))
                    .foregroundStyle(Palette.onInverse)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Filled from your Apple Pay tap")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Blue Bottle Coffee · 2 minutes ago")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            .padding(12)
            .background(Palette.accent.opacity(0.1), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.accent.opacity(0.25), lineWidth: 1))
            .padding(.top, 14)

            VStack(spacing: 12) {
                Text(Money.cents(amount))
                    .font(.figure(76))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                Text("USD")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Palette.raised, in: Capsule())
                    .foregroundStyle(Palette.ink)
            }
            .padding(.top, 26)

            VStack(spacing: 0) {
                FieldRow(label: "Merchant") { Text("Blue Bottle Coffee") }
                Divider()
                FieldRow(label: "Category") {
                    Label("Coffee", systemImage: "sparkle")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Palette.raised, in: Capsule())
                }
                Divider()
                FieldRow(label: "Date") { Text("Today, 8:41 AM") }
                Divider()
                FieldRow(label: "Paid with") { Text("Everyday card") }
            }
            .background(Palette.surface, in: .rect(cornerRadius: 18))
            .padding(.top, 26)

            Text("Artha remembered that Blue Bottle Coffee goes under Coffee.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 10)

            Spacer(minLength: 20)

            Button {
                month.add(.init(merchant: "Blue Bottle Coffee", detail: "Coffee · Just now", symbol: "cup.and.saucer",
                                amount: amount, currencyCode: "USD", usdEquivalent: nil))
                dismiss()
            } label: {
                Text("Add \(Money.cents(amount))")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(Palette.inverse, in: Capsule())
                    .foregroundStyle(Palette.onInverse)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .presentationDragIndicator(.visible)
    }
}

private struct FieldRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondary)
            Spacer()
            value
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }
}
