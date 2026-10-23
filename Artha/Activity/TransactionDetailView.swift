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
    @State private var confirmingUnpair = false
    @State private var isUnpairing = false
    @State private var choosingBill = false
    @State private var splitting = false
    @State private var isUnsplitting = false

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
                    Image(systemName: CategoryStyle.symbol(for: category, type: type, isSplit: tx.isSplit))
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
                            // A split purchase's amounts change in Split.
                            .disabled(tx.isSplit)
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
                    if !tx.isSplit {
                        Hairline()
                        FieldRow("Category") {
                            Picker("Category", selection: $category) {
                                ForEach(categoryChoices) { Text($0.label).tag(Optional($0.key)) }
                                Text("Uncategorized").tag(String?.none)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
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

                if let charge = tx.pairedCharge {
                    PairedCard(charge: charge, isIncome: tx.type == "income", isWorking: isUnpairing) {
                        confirmingUnpair = true
                    }
                    .confirmationDialog("Unpair these? Both will count again, and Artha won\u{2019}t pair this charge on its own again.",
                                        isPresented: $confirmingUnpair, titleVisibility: .visible) {
                        Button("Unpair") { unpair(tx) }
                    }
                }

                if let parts = tx.split, !parts.isEmpty {
                    SplitCard(parts: parts, currency: tx.currency, isWorking: isUnsplitting,
                              onEdit: { splitting = true }, onUnsplit: { unsplit(tx) })
                } else if tx.canSplit == true, tx.type == "expense", type == "expense" {
                    Button {
                        splitting = true
                    } label: {
                        Label("Split Across Categories", systemImage: "square.split.2x1")
                    }
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
                    .accessibilityHint("Count parts of this purchase under different categories")
                }

                if tx.canPair == true {
                    Button {
                        choosingBill = true
                    } label: {
                        Label(tx.type == "income" ? "Pair with Repeating Income" : "Pair with a Bill", systemImage: "link")
                    }
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
                    .accessibilityHint("Pick the bill this paid, so it counts once")
                    .sheet(isPresented: $choosingBill) {
                        PairBillSheet(transaction: tx) { dismiss() }
                    }
                }

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
        .sheet(isPresented: $splitting) {
            SplitSheet(transaction: tx) { dismiss() }
        }
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

    private func unsplit(_ tx: APITransaction) {
        isUnsplitting = true
        error = nil
        Task {
            defer { isUnsplitting = false }
            do {
                try await session.activity.unsplit(tx)
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn\u{2019}t join that back. Try again in a moment."
            }
        }
    }

    private func unpair(_ tx: APITransaction) {
        isUnpairing = true
        error = nil
        Task {
            defer { isUnpairing = false }
            do {
                try await session.activity.unpair(tx)
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn\u{2019}t split those. Try again in a moment."
            }
        }
    }

    private static func apiDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The bills a charge could have paid, likeliest first. Picking one pairs
/// them (counted once, and Unpair splits them again), then closes the
/// transaction, since the charge now lives on the bill.
private struct PairBillSheet: View {
    let transaction: APITransaction
    let onPaired: () -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var bills: [APITransaction]?
    @State private var working: Int?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var error: String?

    private var isIncome: Bool { transaction.type == "income" }

    var body: some View {
        NavigationStack {
            Group {
                if let bills, bills.isEmpty {
                    ContentUnavailableView(isIncome ? "No Repeating Income Nearby" : "No Unpaid Bills Nearby",
                                           systemImage: "calendar.badge.clock",
                                           description: Text(error ?? (isIncome
                                               ? "Repeating income you track shows up here."
                                               : "Bills you track in Plan show up here when one is due near this date.")))
                } else if let bills {
                    List {
                        Section {
                            ForEach(bills) { bill in
                                row(bill)
                            }
                        } footer: {
                            if let error {
                                Text(error).foregroundStyle(Palette.caution).announcedWhenShown(error)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.ground)
            .navigationTitle(isIncome ? "Which Income Is This?" : "Which Bill Did This Pay?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
    }

    private func row(_ bill: APITransaction) -> some View {
        let stacked = typeSize.isAccessibilitySize
        return Button {
            pair(with: bill)
        } label: {
            // Name above amount at the largest text sizes.
            (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.description)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(stacked ? nil : 1)
                    Text(Date.apiDay(bill.date)?.formatted(.dateTime.month(.abbreviated).day()) ?? "")
                        .font(.system(.footnote))
                        .foregroundStyle(Palette.secondary)
                }
                if !stacked { Spacer(minLength: 8) }
                if working == bill.id {
                    ProgressView()
                } else {
                    Text(Money.cents(Decimal.api(bill.amount), bill.currency))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
        .listRowBackground(Palette.surface)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Pairs this transaction with \(bill.description)")
    }

    private func load() async {
        do {
            bills = try await session.activity.bills(for: transaction)
        } catch {
            bills = []
            self.error = "Artha couldn\u{2019}t load your bills. Try again in a moment."
        }
    }

    private func pair(with bill: APITransaction) {
        working = bill.id
        error = nil
        Task {
            defer { working = nil }
            do {
                try await session.activity.pair(transaction, with: bill)
                dismiss()
                onPaired()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn\u{2019}t pair those. Try again in a moment."
            }
        }
    }
}

/// A bill and the real charge for it, counted once
/// (bill_matching on the server). Unpair splits them if Artha got it wrong.
private struct PairedCard: View {
    let charge: String
    let isIncome: Bool
    let isWorking: Bool
    let unpair: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "link")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 38, height: 38)
                .background(Palette.raised, in: .rect(cornerRadius: Radius.small))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(isIncome ? "Paired with its repeating income" : "Paired with its bill")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Artha matched \u{201C}\(charge)\u{201D} to this, so it counts once.")
                    .font(.system(.footnote))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(action: unpair) {
                            Text("Unpair")
                                .frame(minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 6, trailing: 16))
        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .contain)
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


/// A split purchase's parts, each under its own category.
private struct SplitCard: View {
    let parts: [SplitPart]
    let currency: String
    let isWorking: Bool
    let onEdit: () -> Void
    let onUnsplit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Split")
                Spacer()
                Button("Edit Split", action: onEdit)
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            ForEach(parts) { part in
                HStack(spacing: 12) {
                    Image(systemName: CategoryStyle.symbol(for: part.category, type: "expense"))
                        .frame(width: 22)
                        .foregroundStyle(Palette.secondary)
                        .accessibilityHidden(true)
                    Text(part.categoryLabel)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text(Money.cents(Decimal.api(part.amount), currency))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                if part.id != parts.last?.id { Hairline() }
            }
            Button(action: onUnsplit) {
                if isWorking { ProgressView() } else { Text("Unsplit") }
            }
            .font(.system(.callout, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .disabled(isWorking)
            .accessibilityHint("Joins the parts back into one transaction")
        }
        .font(.system(.callout))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
    }
}
