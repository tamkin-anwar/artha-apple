import SwiftUI

/// The big amount you type into, with the currency's symbol in front: the
/// same look as Add, for anywhere an amount is entered.
struct AmountField: View {
    @Binding var text: String
    let currencyCode: String
    var size: CGFloat = 64
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(Money.symbol(for: currencyCode))
                .foregroundStyle(text.isEmpty ? Palette.secondary.opacity(0.5) : Palette.secondary)
            TextField("0", text: $text)
                .keyboard(.decimal)
                .foregroundStyle(Palette.ink)
                .fixedSize()
                .focused(focus)
                .accessibilityLabel("Amount")
        }
        .figureFont(size)
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }
}

/// "You usually spend $2,812 a month", tappable to use the suggestion.
struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(.caption, weight: .semibold))
                Text(text)
                    .font(.system(.subheadline, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Palette.raised, in: Capsule())
            .foregroundStyle(Palette.ink)
        }
        .buttonStyle(.plain)
    }
}
