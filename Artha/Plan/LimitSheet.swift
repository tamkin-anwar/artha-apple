import SwiftUI

/// Add or change a limit on one category ("$400 a month on Dining").
/// Limits are optional: a way to watch one category without budgeting
/// every dollar. Each category shows what's usually spent on it.
struct LimitSheet: View {
    /// The limit being changed, or nil to add a new one.
    let existing: PlanSummary.Limit?

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var category: String?
    @State private var text = ""
    @State private var rollover = false
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var plan: PlanModel { session.plan }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Palette.secondary)
                    .frame(minHeight: 44)
                Spacer()
                Text(existing.map { "\($0.label) limit" } ?? "New limit")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }

            if existing == nil {
                Menu {
                    Picker("Category", selection: $category) {
                        ForEach(plan.unbudgeted) { item in
                            Text(item.label).tag(Optional(item.key))
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if let category {
                            Image(systemName: CategoryStyle.symbol(for: category, type: "expense"))
                        }
                        Text(categoryLabel ?? "Choose a category")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(.caption, weight: .semibold))
                    }
                    .font(.system(.callout, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Palette.raised, in: Capsule())
                    .foregroundStyle(Palette.ink)
                }
                .padding(.top, 28)
            }

            AmountField(text: $text, currencyCode: plan.currencyCode, size: 64, focus: $focused)
                .padding(.top, existing == nil ? 26 : 40)

            Text("a month")
                .font(.system(.subheadline))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 6)

            if let category, let usual = plan.usual(for: category),
               let suggestion = plan.suggestedLimit(for: category), suggestion != amount {
                SuggestionChip(text: "Usually \(Money.whole(usual, plan.currencyCode)) a month. Use \(Money.whole(suggestion, plan.currencyCode))") {
                    text = suggestion.entryText
                }
                .padding(.top, 22)
            }

            Toggle(isOn: $rollover) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carry over what's left")
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text("Unspent money moves to next month. Going over takes it off next month.")
                        .font(.system(.footnote))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.good)
            .padding(16)
            .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
            .padding(.top, 26)

            if let error {
                Text(error)
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.caution)
                    .padding(.top, 14)
                    .announcedWhenShown(error)
            }

            Spacer(minLength: 20)

            if let existing {
                Button("Remove limit", role: .destructive) { remove(existing.key) }
                    .font(.system(.subheadline, weight: .semibold))
                    .frame(minHeight: 44)
                    .disabled(isSaving)
                    .padding(.bottom, 6)
            }

            Button(action: save) {
                ZStack {
                    if isSaving {
                        ProgressView().tint(Palette.onInverse)
                    } else {
                        Text(existing == nil ? "Add limit" : "Save")
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
        .background(Palette.ground)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .onAppear {
            if let existing {
                category = existing.key
                // The limit as set, not this month's with what carried over.
                text = Decimal.api(existing.baseCap ?? existing.cap).entryText
                rollover = existing.rollover ?? false
            } else if category == nil {
                // Lead with the category that usually costs the most.
                category = plan.unbudgeted.max { (plan.usual(for: $0.key) ?? 0) < (plan.usual(for: $1.key) ?? 0) }?.key
            }
            focused = true
        }
    }

    private var amount: Decimal? { Decimal.entry(text) }
    private var canSave: Bool { !isSaving && amount != nil && category != nil }

    private var categoryLabel: String? {
        guard let category else { return nil }
        return plan.unbudgeted.first { $0.key == category }?.label ?? existing?.label
    }

    private func save() {
        guard let category, let amount else { return }
        run { try await plan.saveLimit(category, amount: amount, rollover: rollover) }
    }

    private func remove(_ key: String) {
        run { try await plan.removeLimit(key) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await work()
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }
}
