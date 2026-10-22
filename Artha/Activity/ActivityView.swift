import SwiftUI

/// Every transaction, grouped by day, newest first. Search and the
/// Expenses/Income filter run on the server, so they cover the whole
/// history, not just what's loaded. Swipe to delete (with a few seconds to
/// undo), tap to edit.
struct ActivityView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Int] = []
    /// The transaction open beside the list on a wide screen.
    @State private var selectedID: Int?
    @State private var width: CGFloat = 0

    private var isWide: Bool { width >= WideLayout.twoColumnWidth }

    var body: some View {
        let activity = session.activity
        Group {
            if isWide {
                // Wide (iPad, landscape): the list and the open transaction
                // side by side, the way Mail and Notes work.
                NavigationSplitView {
                    searchableList
                        // Without a width the list collapses on a Mac,
                        // where it sits beside the window's own sidebar.
                        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 480)
                } detail: {
                    NavigationStack {
                        if let id = selectedID, session.activity.transaction(id: id) != nil {
                            TransactionDetailView(transactionID: id).id(id)
                        } else {
                            ContentUnavailableView("No transaction selected", systemImage: "list.bullet",
                                                   description: Text("Pick one from the list to see it or change it."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Palette.ground)
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $path) {
                    searchableList
                        .navigationDestination(for: Int.self) { id in
                            TransactionDetailView(transactionID: id)
                        }
                }
            }
        }
        .readWidth($width)
        .onChange(of: session.activity.pendingDelete?.id) { _, id in
            if let id, id == selectedID { selectedID = nil }
        }
        .task(id: "\(activity.query)|\(activity.filter.rawValue)") {
            // Wait for a pause in typing before searching; the first load
            // and a filter change go straight away.
            if activity.hasLoaded, !activity.query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            // Already loaded behind Today a moment ago: nothing to wait for.
            if activity.isFresh { return }
            await activity.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { activity.commitPendingDelete() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: activity.deleteCount)
        .alert("Artha", isPresented: Binding(get: { activity.hasLoaded && activity.error != nil },
                                             set: { if !$0 { activity.dismissError() } })) {
            Button("OK") { activity.dismissError() }
        } message: {
            Text(activity.error ?? "")
        }
    }

    private var searchableList: some View {
        @Bindable var activity = session.activity
        return list
            .navigationTitle("Activity")
            .searchable(text: $activity.query, placement: .alwaysVisible,
                        prompt: "Search transactions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Show", selection: $activity.filter) {
                            ForEach(ActivityModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Label("Show", systemImage: activity.filter == .all
                              ? "line.3.horizontal.decrease"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
    }

    private func open(_ id: Int) {
        if isWide { selectedID = id } else { path.append(id) }
    }

    private var list: some View {
        let activity = session.activity
        return List {
            ForEach(activity.days) { day in
                Section {
                    ForEach(day.transactions) { tx in
                        Button {
                            open(tx.id)
                        } label: {
                            TransactionRow(expense: .init(tx, detail: Self.detail(for: tx)),
                                           displayCurrency: activity.currencyCode)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation(.snappy) { activity.delete(tx) }
                            }
                            .tint(.red)
                        }
                        .listRowBackground(isWide && tx.id == selectedID ? Palette.raised : Palette.ground)
                        .listRowSeparatorTint(Palette.ink.opacity(0.07))
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    }
                } header: {
                    HStack(spacing: 8) {
                        SectionLabel(day.title)
                        if day.isUpcoming {
                            Text("SCHEDULED")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.8)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Palette.raised, in: Capsule())
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 8)
                        if day.spent > 0 {
                            Text(Money.cents(day.spent, activity.currencyCode))
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.secondary)
                                .accessibilityLabel("\(Money.cents(day.spent, activity.currencyCode)) spent")
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            if activity.canLoadMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Palette.ground)
                    .listRowSeparator(.hidden)
                    .task { await activity.loadMore() }
            }
            Color.clear
                .frame(height: 60)
                .listRowBackground(Palette.ground)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .refreshable { await activity.reload() }
        .overlay { emptyState }
        // Inside the safe area, so it sits above the floating tab bar
        // rather than behind it.
        .safeAreaInset(edge: .bottom, spacing: 0) { UndoToast() }
        .animation(.snappy(duration: 0.35), value: activity.days.map(\.id))
    }

    @ViewBuilder
    private var emptyState: some View {
        let activity = session.activity
        if !activity.hasLoaded {
            if let error = activity.error {
                ContentUnavailableView {
                    Label("Can't load Activity", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await activity.reload() } }
                        .buttonStyle(.bordered)
                }
            } else {
                ProgressView()
            }
        } else if activity.days.isEmpty {
            let search = activity.query.trimmingCharacters(in: .whitespaces)
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if activity.filter == .income {
                ContentUnavailableView("No income yet", systemImage: "arrow.down.left",
                                       description: Text("Paychecks and other money in will show up here."))
            } else if activity.filter == .expenses {
                ContentUnavailableView("No expenses yet", systemImage: "cart",
                                       description: Text("Everything you spend will show up here."))
            } else {
                ContentUnavailableView("Nothing here yet", systemImage: "list.bullet",
                                       description: Text("Tap + to add your first transaction. Anything you add on arthaapp.com shows up here too."))
            }
        }
    }

    /// The line under a transaction's name: its category, and how often it
    /// repeats if it does. The date is already the section it sits in.
    static func detail(for tx: APITransaction) -> String {
        var parts = [tx.type == "income" ? "Income" : tx.categoryLabel]
        if tx.isRecurring { parts.append(repeatLabel(tx.recurrenceInterval)) }
        if tx.source == "apple_pay" { parts.append("Apple Pay") }
        return parts.joined(separator: " · ")
    }

    static func repeatLabel(_ interval: String?) -> String {
        switch interval {
        case "weekly": "Repeats weekly"
        case "biweekly": "Repeats every 2 weeks"
        default: "Repeats monthly"
        }
    }
}

/// "Deleted Blue Bottle Coffee · Undo", floating above the tab bar for as
/// long as the delete is being held back. On Today too, since a
/// transaction can be opened and deleted from there.
struct UndoToast: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let activity = session.activity
        ZStack {
            if let tx = activity.pendingDelete {
                HStack(spacing: 12) {
                    Text(tx.isRecurring ? "Deleted \(tx.description) and stopped it repeating" : "Deleted \(tx.description)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Undo") {
                        withAnimation(.snappy) { activity.undoDelete() }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.leading, 20)
                .padding(.trailing, 10)
                .frame(minHeight: 52)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Undo") { activity.undoDelete() }
            }
        }
        .animation(.snappy(duration: 0.3), value: activity.pendingDelete?.id)
    }
}
