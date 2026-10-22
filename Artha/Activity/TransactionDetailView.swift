import SwiftUI

/// One transaction, editable in place. Save sends only what changed, and
/// goes through the same rules as an edit on the web: a new category is
/// remembered for that merchant, and the amount stays in its own currency.
struct TransactionDetailView: View {
    let transactionID: Int
    /// For one opened from outside Activity's loaded pages (an older
    /// transaction behind a Today category).
    var fallback: APITransaction?

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var original: APITransaction?
    @State private var description = ""
    @State private var amountText = ""
    @State private var category: String?
    @State private var date = Date.now
    @State private var type = "expense"
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let tx = original {
                content(tx)
            } else {
                ContentUnavailableView("Transaction not found", systemImage: "questionmark",
                                       description: Text("It may have been deleted somewhere else."))
            }
        }
        .background(Palette.ground)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: load)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
    }

    private func content(_ tx: APITransaction) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: CategoryStyle.symbol(for: category, type: type))
                        .font(.system(.title2, weight: .medium))
                        .frame(width: 56, height: 56)
                        .background(Palette.raised, in: .rect(cornerRadius: Radius.card))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.symbolEffect(.replace))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(Money.symbol(for: tx.currency))
                            .foregroundStyle(Palette.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboard(.decimal)
                            .fixedSize()
                            .foregroundStyle(Palette.ink)
                            .accessibilityLabel("Amount")
                    }
                    .figureFont(52)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                    if let equivalent = tx.displayAmount, tx.currency != session.activity.currencyCode {
                        Text("≈ \(Money.cents(Decimal.api(equivalent), session.activity.currencyCode)) when it was added")
                            .font(.system(.footnote))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .padding(.top, 12)

                VStack(spacing: 0) {
                    FieldRow("Name") {
                        TextField("Name", text: $description)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                    }
                    Hairline()
                    FieldRow("Type") {
                        Picker("Type", selection: $type) {
                            Text("Expense").tag("expense")
                            Text("Income").tag("income")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    Hairline()
                    FieldRow("Category") {
                        Picker("Category", selection: $category) {
                            ForEach(categoryChoices) { Text($0.label).tag(Optional($0.key)) }
                            Text("Uncategorized").tag(String?.none)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    Hairline()
                    FieldRow("Date") {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }
                    if tx.isRecurring {
                        Hairline()
                        FieldRow("Repeats") {
                            Text(tx.recurrenceInterval == "weekly" ? "Weekly" : tx.recurrenceInterval == "biweekly" ? "Every 2 weeks" : "Monthly")
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                }
                .font(.system(.callout))
                .tint(Palette.accent)
                .padding(.horizontal, 16)
                .background(Palette.surface, in: .rect(cornerRadius: Radius.card))

                VStack(alignment: .leading, spacing: 6) {
                    if category != nil, category != tx.category {
                        Text("Artha will file \(description.isEmpty ? tx.description : description) here from now on.")
                    }
                    if let error {
                        Text(error).foregroundStyle(Palette.caution).announcedWhenShown(error)
                    }
                }
                .font(.system(.footnote))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, -16)

                Button("Delete Transaction", role: .destructive) {
                    confirmingDelete = true
                }
                // Command-Delete, the iPad and Mac shortcut for deleting
                // the thing that's open; it still asks first.
                .keyboardShortcut(.delete, modifiers: .command)
                .font(.system(.callout, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
                .confirmationDialog(tx.isRecurring ? "This repeats. Deleting it also stops it repeating." : "Delete this transaction?",
                                    isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        session.activity.delete(tx)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappy(duration: 0.3), value: category)
    }

    // MARK: Editing

    private var categoryChoices: [CategoryList.Category] {
        let all = session.activity.categories
        return type == "income" ? all : all.filter { $0.key != "income" }
    }

    private var amount: Decimal? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    private var changes: [String: Any] {
        guard let tx = original else { return [:] }
        var changes: [String: Any] = [:]
        let name = description.trimmingCharacters(in: .whitespaces)
        if name != tx.description { changes["description"] = name }
        if let amount, amount != Decimal.api(tx.amount) { changes["amount"] = NSDecimalNumber(decimal: amount).stringValue }
        if type != tx.type { changes["type"] = type }
        if category != tx.category { changes["category"] = category ?? NSNull() }
        let day = Self.apiDay(date)
        if day != tx.date { changes["date"] = day }
        return changes
    }

    private var canSave: Bool {
        !isSaving && amount != nil && !description.trimmingCharacters(in: .whitespaces).isEmpty && !changes.isEmpty
    }

    private func load() {
        guard original == nil, let tx = session.activity.transaction(id: transactionID) ?? fallback else { return }
        original = tx
        description = tx.description
        amountText = tx.amount
        category = tx.category
        date = Date.apiDay(tx.date) ?? .now
        type = tx.type
    }

    private func save() {
        guard canSave, let tx = original else { return }
        let changes = changes
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.activity.update(tx, changes: changes)
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }

    private static func apiDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

private struct FieldRow<Control: View>: View {
    let label: String
    let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 8)
            control
                .foregroundStyle(Palette.ink)
        }
        .frame(minHeight: 52)
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
    }
}
