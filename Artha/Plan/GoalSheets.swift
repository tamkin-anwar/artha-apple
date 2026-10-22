import SwiftUI

/// Which goal sheet is open: a new goal, or one to change.
struct GoalTarget: Identifiable {
    let goal: PlanSummary.Goal?
    var id: String { goal.map { "goal-\($0.id)" } ?? "new" }
}

/// Add or change a savings goal: what it's for, how much, and optionally
/// by when (then Plan shows what to set aside each month to get there).
struct GoalSheet: View {
    let existing: PlanSummary.Goal?

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var text = ""
    @State private var hasDate = false
    @State private var date = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @FocusState private var amountFocused: Bool
    @FocusState private var nameFocused: Bool

    private var plan: PlanModel { session.plan }
    private var currencyCode: String { existing?.currency ?? plan.currencyCode }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Palette.secondary)
                    .frame(minHeight: 44)
                Spacer()
                Text(existing == nil ? "New goal" : "Goal")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }

            TextField("What it's for", text: $name)
                .font(.system(.title3, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.ink)
                .focused($nameFocused)
                .submitLabel(.next)
                .onSubmit { amountFocused = true }
                .padding(.top, 26)

            AmountField(text: $text, currencyCode: currencyCode, size: 56, focus: $amountFocused)
                .padding(.top, 20)

            VStack(spacing: 0) {
                Toggle("By a date", isOn: $hasDate.animation(.snappy))
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.good)
                    .frame(minHeight: 48)
                if hasDate {
                    DatePicker("Date", selection: $date, in: Date.now..., displayedComponents: .date)
                        .font(.system(.callout))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 48)
                    if let perMonth {
                        Text("About \(Money.whole(perMonth, currencyCode)) a month from now")
                            .font(.system(.footnote))
                            .foregroundStyle(Palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 10)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
            .padding(.top, 24)

            if let error {
                Text(error)
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.caution)
                    .padding(.top, 14)
            }

            Spacer(minLength: 20)

            if existing != nil {
                Button("Delete goal", role: .destructive) { confirmingDelete = true }
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
                        Text(existing == nil ? "Add goal" : "Save")
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
        .confirmationDialog("Delete this goal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete goal", role: .destructive) {
                guard let existing else { return }
                run { try await plan.deleteGoal(existing.id) }
            }
        } message: {
            Text("What you've saved toward it is only a note in Artha, so no money moves.")
        }
        .onAppear {
            if let existing {
                name = existing.name
                text = Decimal.api(existing.target).entryText
                if let saved = Date.apiDay(existing.targetDate) {
                    hasDate = true
                    date = saved
                }
            } else {
                nameFocused = true
            }
        }
    }

    private var amount: Decimal? { Decimal.entry(text) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !isSaving && amount != nil && !trimmedName.isEmpty }

    /// A preview of the monthly figure, counting this month like the server.
    private var perMonth: Decimal? {
        guard let amount else { return nil }
        let saved = existing.map { Decimal.api($0.saved) } ?? 0
        let left = amount - saved
        guard left > 0 else { return nil }
        let calendar = Calendar.current
        let now = calendar.dateComponents([.year, .month], from: .now)
        let then = calendar.dateComponents([.year, .month], from: date)
        let months = ((then.year ?? 0) - (now.year ?? 0)) * 12 + ((then.month ?? 0) - (now.month ?? 0)) + 1
        guard months > 0 else { return nil }
        return left / Decimal(months)
    }

    private func save() {
        guard let amount else { return }
        let id = existing?.id
        let name = trimmedName
        let date = hasDate ? date : nil
        run { try await plan.saveGoal(id: id, name: name, target: amount, date: date) }
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

/// Put money toward a goal, or take some back out.
struct GoalMoneySheet: View {
    let goal: PlanSummary.Goal

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var takingOut = false
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
                Text(goal.name)
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }

            Picker("Direction", selection: $takingOut) {
                Text("Add").tag(false)
                Text("Take out").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.top, 22)

            AmountField(text: $text, currencyCode: goal.currency, size: 64, focus: $focused)
                .padding(.top, 30)

            Text("\(Money.natural(Decimal.api(goal.saved), goal.currency)) of \(Money.natural(Decimal.api(goal.target), goal.currency)) so far")
                .font(.system(.subheadline))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 8)

            if !takingOut, let perMonth = monthShare {
                SuggestionChip(text: "This month's share: \(Money.whole(perMonth, goal.currency))") {
                    text = perMonth.entryText
                }
                .padding(.top, 20)
            }

            if let error {
                Text(error)
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.caution)
                    .padding(.top, 14)
            }

            Spacer(minLength: 20)

            Button(action: save) {
                ZStack {
                    if isSaving {
                        ProgressView().tint(Palette.onInverse)
                    } else {
                        Text(takingOut ? "Take out" : "Add")
                    }
                }
                .font(.system(.body, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Palette.inverse, in: Capsule())
                .foregroundStyle(Palette.onInverse)
            }
            .buttonStyle(.plain)
            .disabled(amount == nil || isSaving)
            .opacity(amount == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Palette.ground)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: isSaving) { old, new in old && !new && error == nil }
        .onAppear { focused = true }
    }

    private var amount: Decimal? {
        guard let value = Decimal.entry(text), value > 0 else { return nil }
        return value
    }

    private var monthShare: Decimal? {
        guard let raw = goal.perMonth else { return nil }
        let value = Decimal.api(raw)
        return value > 0 ? value : nil
    }

    private func save() {
        guard let amount else { return }
        let change = takingOut ? -amount : amount
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await plan.addToGoal(goal.id, amount: change)
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }
}
