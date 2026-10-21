import SwiftUI

/// Today: one number that answers "am I OK?", the month drawn under it,
/// then where the money went, what's coming, and what just happened.
/// Where a tap on Today leads: a transaction, or the transactions behind
/// one of "Where October went"'s numbers.
enum TodayRoute: Hashable {
    struct Category: Hashable {
        let name: String
        let keys: [String]
    }

    case transaction(Int, fallback: APITransaction?)
    case category(Category)
}

struct TodayView: View {
    @Environment(AppSession.self) private var session
    @Environment(MonthModel.self) private var month
    @State private var path: [TodayRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            page
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: TodayRoute.self) { route in
                    switch route {
                    case .transaction(let id, let fallback):
                        TransactionDetailView(transactionID: id, fallback: fallback)
                    case .category(let category):
                        CategoryMonthView(route: category)
                    }
                }
        }
        // An overlay, not a safe-area inset: an inset here changes the
        // stack's layout as the toast comes and goes, and with the
        // navigation bar hidden that fed back into an endless layout loop.
        .overlay(alignment: .bottom) {
            UndoToast()
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TodayHeader()
                content
            }
            .padding(.bottom, 120)
            .animation(.snappy(duration: 0.35), value: month.status)
        }
        .scrollIndicators(.hidden)
        .refreshable { await session.refresh() }
        .background(Palette.ground)
        .sensoryFeedback(.success, trigger: month.addCount)
        .alert("Artha", isPresented: noticeShown) {
            Button("OK") { session.notice = nil }
        } message: {
            Text(session.notice ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if month.summary == nil {
            if let error = session.refreshError {
                ContentUnavailableView {
                    Label("Can't load Today", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { Task { await session.refresh() } }
                }
                .padding(.top, 80)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 160)
            }
        } else if month.isEmpty {
            FirstDay()
        } else {
            if let error = session.refreshError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.caution)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            HeroSection()
                .padding(.horizontal, 20)
                .padding(.top, 26)
            PaceChart()
                .padding(.horizontal, 16)
                .padding(.top, 22)
            if month.toReview > 0 {
                ReviewCard().padding(.horizontal, 16).padding(.top, 24)
            }
            if !month.hasBudget {
                NoBudgetCard().padding(.horizontal, 16).padding(.top, 24)
            } else if month.status == .ahead {
                AheadCard().padding(.horizontal, 16).padding(.top, 24)
            } else if month.status == .over {
                OverCard().padding(.horizontal, 16).padding(.top, 24)
            }
            if !month.shares.isEmpty {
                WhereItWent().padding(.top, 30)
            }
            if !month.bills.isEmpty {
                ComingUp().padding(.top, 30)
            }
            if !month.recent.isEmpty {
                RecentList()
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
            }
        }
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { session.notice != nil }, set: { if !$0 { session.notice = nil } })
    }
}

private struct TodayHeader: View {
    @Environment(AppSession.self) private var session
    @Environment(MonthModel.self) private var month
    @State private var isDeletingAccount = false

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                OrbMark().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(month.headerDate)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Palette.secondary)
                    Text("Today")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
            }
            Spacer()
            Menu {
                Button("Log Apple Pay automatically", systemImage: "wave.3.right") {
                    session.isShowingApplePaySetup = true
                }
                if let user = session.user {
                    Section("Signed in as \(user.username)") {
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                            Task { await session.signOut() }
                        }
                        Button("Delete account", systemImage: "trash", role: .destructive) {
                            isDeletingAccount = true
                        }
                    }
                }
            } label: {
                Text(session.user?.initials ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Palette.raised, in: Circle())
                    .foregroundStyle(Palette.ink)
            }
            .accessibilityLabel("Account")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .sheet(isPresented: $isDeletingAccount) { DeleteAccountView() }
    }
}

struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .bold))
            .tracking(1)
            .foregroundStyle(Palette.secondary)
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(prominent ? Palette.inverse : Palette.raised, in: Capsule())
            .foregroundStyle(prominent ? Palette.onInverse : Palette.ink)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
