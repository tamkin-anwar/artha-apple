import SwiftUI

@main
struct ArthaApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(session.month)
                .onOpenURL { session.open($0) }
        }
    }
}

/// Signed in or not, and keeping Today fresh: it refreshes whenever the
/// app comes back to the foreground, since a purchase made on the web (or
/// a bill that came due overnight) should already be there when you look.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.phase {
            case .checking:
                Palette.ground.ignoresSafeArea()
            case .signedOut:
                SignInView()
            case .signedIn:
                MainTabs()
            }
        }
        .task { await session.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await session.becameActive() }
            }
        }
    }
}

/// Where a widget, the Control Center button or an artha:// link can send
/// someone.
enum AppRoute: String {
    case today, activity, plan, wealth, add
}

/// The four tabs plus Add, which sits in its own spot beside them (the
/// search role's slot) and opens a sheet instead of a screen.
struct MainTabs: View {
    enum Destination: Hashable { case today, activity, plan, wealth, add }

    @Environment(AppSession.self) private var session
    @State private var selection: Destination = .today
    @State private var isAdding = false

    var body: some View {
        @Bindable var session = session
        TabView(selection: $selection) {
            Tab("Today", systemImage: "gauge.with.dots.needle.33percent", value: .today) {
                TodayView()
            }
            Tab("Activity", systemImage: "list.bullet", value: .activity) {
                ActivityView()
            }
            Tab("Plan", systemImage: "chart.line.uptrend.xyaxis", value: .plan) {
                PlanView()
            }
            Tab("Wealth", systemImage: "chart.bar.fill", value: .wealth) {
                WealthView()
            }
            Tab("Add", systemImage: "plus", value: .add, role: .search) {
                Color.clear
            }
        }
        .tint(Palette.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: selection) { previous, current in
            if current == .add {
                selection = previous
                isAdding = true
            }
        }
        .sheet(isPresented: $isAdding) {
            AddSheet()
        }
        .sheet(isPresented: $session.isEditingBudget) {
            BudgetSheet()
        }
        .sheet(isPresented: $session.isShowingApplePaySetup) {
            ApplePaySetupView()
        }
        .sheet(isPresented: $session.isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $session.isReviewing, onDismiss: {
            Task { await session.refreshAfterReview() }
        }) {
            ReviewSheet()
        }
        .onChange(of: session.route, initial: true) { _, route in
            guard let route else { return }
            session.route = nil
            switch route {
            case .today: selection = .today
            case .activity: selection = .activity
            case .plan: selection = .plan
            case .wealth: selection = .wealth
            case .add: isAdding = true
            }
        }
    }
}
