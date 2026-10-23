import SwiftUI

/// One purchase across categories: a Costco run that's part groceries,
/// part household. Each part counts under its own category everywhere
/// (budgets, Safe to Spend, Where the month went) while Activity keeps it
/// one purchase. The parts must add up to the purchase to the cent; the
/// sheet shows what's left to assign and can share it evenly between the
/// parts with no amount yet, the way YNAB does.
struct SplitSheet: View {
    let transaction: APITransaction
    let onSaved: () -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var parts: [Part]
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focused: UUID?

    private static let maxParts = 20

    struct Part: Identifiable {
        let id = UUID()
        var category: String?
        var amountText: String
    }

    init(transaction: APITransaction, onSaved: @escaping () -> Void) {
        self.transaction = transaction
        self.onSaved = onSaved
        let existing = (transaction.split ?? []).map { Part(category: $0.category, amountText: $0.amount) }
        _parts = State(initialValue: existing.isEmpty
            ? [Part(category: transaction.category, amountText: ""), Part(category: nil, amountText: "")]
            : existing)
    }

    private var total: Decimal { Decimal.api(transaction.amount) }
    private var assigned: Decimal { parts.reduce(0) { $0 + (Self.amount($1.amountText) ?? 0) } }
    private var left: Decimal { total - assigned }
    private var isBalanced: Bool { left == 0 && parts.allSatisfy { (Self.amount($0.amountText) ?? 0) > 0 } }
    private var emptyParts: [Int] { parts.indices.filter { (Self.amount(parts[$0].amountText) ?? 0) == 0 } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($parts) { $part in
                        PartRow(part: $part, currency: transaction.currency,
                                categories: session.activity.categories.filter { $0.key != "income" },
                                focused: $focused)
                    }
                    .onDelete { offsets in
                        guard parts.count - offsets.count >= 2 else { return }
                        parts.remove(atOffsets: offsets)
                    }
                    .deleteDisabled(parts.count <= 2)
                } header: {
                    Text("\(Money.cents(total, transaction.currency)) at \(transaction.description)")
                        .textCase(nil)
                }
                .listRowBackground(Palette.surface)

                Section {
                    Button("Add a Part", systemImage: "plus.circle.fill") {
                        let part = Part(category: nil, amountText: "")
                        parts.append(part)
                        focused = part.id
                    }
                    .disabled(parts.count >= Self.maxParts)
                    if left > 0, !emptyParts.isEmpty {
                        Button("Split the Rest Evenly", systemImage: "equal.circle.fill", action: splitRestEvenly)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        leftText
                        if let error {
                            Text(error).foregroundStyle(Palette.caution).announcedWhenShown(error)
                        }
                    }
                }
                .listRowBackground(Palette.surface)
                .foregroundStyle(Palette.accent)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Split")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save).disabled(!isBalanced)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .sensoryFeedback(.success, trigger: isBalanced) { _, new in new }
            .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    @ViewBuilder
    private var leftText: some View {
        if left == 0, !emptyParts.isEmpty {
            Text("Give every part an amount, or swipe it away.")
                .foregroundStyle(Palette.secondary)
        } else if left == 0 {
            Label("Every cent is assigned.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.good)
        } else if left > 0 {
            Text("\(Money.cents(left, transaction.currency)) left to assign")
                .foregroundStyle(Palette.secondary)
        } else {
            Text("\(Money.cents(-left, transaction.currency)) over")
                .foregroundStyle(Palette.caution)
        }
    }

    /// What's left, shared between the parts with no amount yet; the last
    /// one takes the odd cent.
    private func splitRestEvenly() {
        let slots = emptyParts
        guard !slots.isEmpty, left > 0 else { return }
        let cents = NSDecimalNumber(decimal: left * 100).intValue
        let each = cents / slots.count
        for (n, index) in slots.enumerated() {
            let share = n == slots.count - 1 ? cents - each * (slots.count - 1) : each
            parts[index].amountText = Self.text(cents: share)
        }
        focused = nil
    }

    private func save() {
        guard isBalanced else { return }
        let payload = parts.map { (amount: Self.amount($0.amountText) ?? 0, category: $0.category) }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.activity.split(transaction, into: payload)
                dismiss()
                onSaved()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn\u{2019}t split that. Try again in a moment."
            }
        }
    }

    static func amount(_ text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var rounded = Decimal()
        var source = value
        NSDecimalRound(&rounded, &source, 2, .plain)
        return rounded
    }

    static func text(cents: Int) -> String {
        String(format: "%d.%02d", cents / 100, cents % 100)
    }
}

/// One part: its category and its amount.
private struct PartRow: View {
    @Binding var part: SplitSheet.Part
    let currency: String
    let categories: [CategoryList.Category]
    var focused: FocusState<UUID?>.Binding
    @Environment(\.dynamicTypeSize) private var typeSize

    private var label: String {
        categories.first { $0.key == part.category }?.label ?? "Uncategorized"
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Menu {
                Picker("Category", selection: $part.category) {
                    ForEach(categories) { Text($0.label).tag(Optional($0.key)) }
                    Text("Uncategorized").tag(String?.none)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: CategoryStyle.symbol(for: part.category, type: "expense"))
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(label)
                        .foregroundStyle(Palette.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Category")
            .accessibilityValue(label)

            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }

            HStack(spacing: 2) {
                Text(Money.symbol(for: currency))
                    .foregroundStyle(Palette.secondary)
                TextField("0.00", text: $part.amountText)
                    .keyboard(.decimal)
                    .multilineTextAlignment(.trailing)
                    .focused(focused, equals: part.id)
                    // The symbol hugs the digits, as on the detail screen.
                    .fixedSize()
                    .accessibilityLabel("Amount for \(label)")
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .frame(minWidth: 88, minHeight: 44, alignment: .trailing)
            // The whole amount area answers a tap, not just the digits.
            .contentShape(.rect)
            .onTapGesture { focused.wrappedValue = part.id }
        }
        .foregroundStyle(Palette.ink)
    }
}
