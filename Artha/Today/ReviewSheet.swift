import SwiftUI

/// One purchase at a time, the ones Apple Pay logged on their own. If it's
/// right, one tap; if the category's wrong, tapping the right one fixes it
/// (and teaches it for that store, like any other edit) and moves on.
/// Copilot, Monarch and YNAB all have a review step like this; the
/// complaint about them is that it turns into homework, so this never
/// nags, and "Mark all as right" clears the whole pile at once.
struct ReviewSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [APITransaction]?
    @State private var index = 0
    @State private var isSaving = false
    @State private var error: String?
    @State private var reviewedCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if let queue {
                    if index < queue.count {
                        card(queue[index], position: index + 1, of: queue.count)
                            .id(queue[index].id)
                            .motionTransition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    } else {
                        done
                    }
                } else if let error {
                    ContentUnavailableView {
                        Label("Can't load purchases", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.ground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let queue, queue.count - index > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Mark all as right") { markAllRight() }
                            .disabled(isSaving)
                    }
                }
            }
        }
        .task { await load() }
        .sensoryFeedback(.success, trigger: reviewedCount)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .animation(.snappy(duration: 0.35), value: index)
        .presentationDragIndicator(.visible)
    }

    private func card(_ tx: APITransaction, position: Int, of total: Int) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("\(position) of \(total)")
                    .font(.system(.footnote, weight: .bold))
                    .tracking(0.8)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)

                Image(systemName: CategoryStyle.symbol(for: tx.category, type: tx.type))
                    .font(.system(.title2, weight: .medium))
                    .frame(width: 64, height: 64)
                    .background(Palette.raised, in: .rect(cornerRadius: Radius.card))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 20)
                Text(tx.description)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                Text(Money.cents(Decimal.api(tx.amount), tx.currency))
                    .figureFont(40)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 4)
                Text(subtitle(for: tx))
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Category")
                    if tx.category == nil {
                        Text("Artha couldn't tell what this was. Pick one and it'll know next time.")
                            .font(.system(.subheadline))
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(categoryChoices) { choice in
                            let selected = choice.key == tx.category
                            Button {
                                choose(choice.key, for: tx)
                            } label: {
                                Label(choice.label, systemImage: CategoryStyle.symbol(for: choice.key, type: tx.type))
                                    .font(.system(.subheadline, weight: selected ? .semibold : .regular))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 40)
                                    .background(selected ? Palette.inverse : Palette.surface, in: Capsule())
                                    .foregroundStyle(selected ? Palette.onInverse : Palette.ink)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 32)

                if let error {
                    Text(error)
                        .font(.system(.subheadline))
                        .foregroundStyle(Palette.caution)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .announcedWhenShown(error)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button {
                looksRight(tx)
            } label: {
                ZStack {
                    if isSaving {
                        ProgressView().tint(Palette.onInverse)
                    } else {
                        Text("Looks right")
                    }
                }
                .font(.system(.body, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Palette.inverse, in: Capsule())
                .foregroundStyle(Palette.onInverse)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Palette.ground)
        }
    }

    private var done: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Palette.good)
                .symbolEffect(.bounce, value: index)
            Text("All caught up")
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("New Apple Pay purchases will show up on Today for a look.")
                .font(.system(.subheadline))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var categoryChoices: [CategoryList.Category] {
        session.activity.categories.filter { $0.key != "income" }
    }

    private func subtitle(for tx: APITransaction) -> String {
        let day = Date.apiDay(tx.date ?? "")?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) ?? ""
        return "\(day) · Apple Pay"
    }

    // MARK: Actions

    private func load() async {
        // The category list rides along with Activity's first load; if
        // that hasn't happened yet, do it now so there's something to pick.
        if session.activity.categories.isEmpty { await session.activity.reload() }
        do {
            let page = try await session.reviewQueue()
            queue = page.transactions
            index = 0
            error = nil
        } catch let failure as APIError {
            error = failure.message
        } catch {
            self.error = "Artha couldn't load these purchases. Try again in a moment."
        }
    }

    private func looksRight(_ tx: APITransaction) {
        save { try await session.markReviewed([tx.id]) }
    }

    /// Picking the category it already has is the same as "Looks right".
    private func choose(_ key: String, for tx: APITransaction) {
        guard key != tx.category else { return looksRight(tx) }
        save { try await session.activity.update(tx, changes: ["category": key]) }
    }

    private func markAllRight() {
        guard let queue else { return }
        let ids = queue[index...].map(\.id)
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.markReviewed(ids)
                reviewedCount += 1
                self.index = queue.count
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }

    private func save(_ work: @escaping () async throws -> Void) {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await work()
                reviewedCount += 1
                index += 1
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }
}

/// Lays out chips left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
