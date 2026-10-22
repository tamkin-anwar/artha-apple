import SwiftUI

/// Add an expense or income. The amount comes first and fills the screen;
/// Artha picks the category itself (remembered merchant, then keywords,
/// then AI, the same as the web app), so there's nothing else to choose.
/// The currency starts as the display currency; tapping it logs a purchase
/// in whatever it was paid in (a coffee abroad), which the server locks to
/// a USD value and totals convert, exactly as on the web.
struct AddSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(MonthModel.self) private var month
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Kind: String, CaseIterable { case expense = "Expense", income = "Income" }
    private enum Field { case amount, description }

    @State private var kind: Kind = .expense
    @State private var amountText = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var showingApplePaySetup = false
    @State private var paidIn: String?
    @State private var isPickingCurrency = false
    @FocusState private var focus: Field?

    /// The currency this purchase was paid in.
    private var currencyCode: String { paidIn ?? month.currencyCode }

    var body: some View {
        VStack(spacing: 0) {
            header

            // Scrolls only when it has to (the largest text sizes, with the
            // keyboard up), so nothing below the amount gets cut off.
            ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Money.symbol(for: currencyCode))
                        .foregroundStyle(amountText.isEmpty ? Palette.secondary.opacity(0.5) : Palette.ink)
                    TextField("0.00", text: $amountText)
                        .keyboard(.decimal)
                        .foregroundStyle(Palette.ink)
                        .fixedSize()
                        .focused($focus, equals: .amount)
                        .accessibilityLabel("Amount")
                }
                .figureFont(76)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { focus = .amount }
                Button { isPickingCurrency = true } label: {
                    HStack(spacing: 4) {
                        Text(currencyCode)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(.caption2, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.system(.footnote, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Palette.raised, in: Capsule())
                    .foregroundStyle(Palette.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Currency")
                .accessibilityValue(Currencies.name(currencyCode))
                .accessibilityHint("Opens the list of currencies")
                if currencyCode != month.currencyCode {
                    Text("Your totals count it in \(month.currencyCode) at today's rate.")
                        .font(.system(.footnote))
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 36)

            TextField(kind == .expense ? "What was it? (Blue Bottle Coffee)" : "Where's it from? (Salary)", text: $description)
                .font(.system(.body))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
                .focused($focus, equals: .description)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.top, 32)

            Text(kind == .expense
                 ? "Artha sorts it into a category for you, and remembers what you change."
                 : "Counts toward this month's income.")
                .font(.system(.footnote))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 10)

            if let error {
                Text(error)
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.caution)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .announcedWhenShown(error)
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
            }

            // Only until Apple Pay has logged something on its own: after
            // that it's set up, and the link would just be clutter here.
            if month.applePay == nil, ThisDevice.canAutomateApplePay {
                Button { showingApplePaySetup = true } label: {
                    Label("Paid with Apple Pay? Log it automatically", systemImage: "wave.3.right")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 44)
                }
                .padding(.top, 20)
            }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .padding(.bottom, 6)

            Button(action: save) {
                ZStack {
                    if isSaving {
                        ProgressView().tint(Palette.onInverse)
                    } else {
                        Text(amount.map { "Add \(Money.cents($0, currencyCode))" } ?? "Add")
                    }
                }
                .font(.system(.body, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Palette.inverse, in: Capsule())
                .foregroundStyle(Palette.onInverse)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        // The same ground as every other sheet: without it the system's
        // sheet color shows, and in Day the white name field disappears
        // into it.
        .background(Palette.ground)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .onAppear { focus = .amount }
        .sheet(isPresented: $showingApplePaySetup) { ApplePaySetupView() }
        .sheet(isPresented: $isPickingCurrency) {
            CurrencyPicker(selection: currencyCode) { paidIn = $0 == month.currencyCode ? nil : $0 }
        }
    }

    /// Cancel and the Expense/Income switch side by side; at accessibility
    /// sizes the switch goes under Cancel so neither gets cut to "Ca...".
    @ViewBuilder private var header: some View {
        let cancel = Button("Cancel") { dismiss() }
            .font(.system(.callout))
            .foregroundStyle(Palette.secondary)
            .frame(minHeight: 44)
        let picker = Picker("Type", selection: $kind) {
            ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
        }
        .pickerStyle(.segmented)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                cancel
                picker
            }
        } else {
            HStack {
                cancel
                Spacer()
                picker.frame(width: 200)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }
        }
    }

    private var amount: Decimal? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        !isSaving && amount != nil && !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        guard canSave, let amount else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.addTransaction(description: description.trimmingCharacters(in: .whitespaces),
                                                 amount: amount,
                                                 type: kind == .expense ? "expense" : "income",
                                                 currency: currencyCode)
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }
}
