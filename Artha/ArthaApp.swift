import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct ArthaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(session.month)
                .onOpenURL { session.open($0) }
                .task { appDelegate.session = session }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
        // For iPads with a keyboard: hold Command to see these.
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Transaction") { session.route = .add }
                    .keyboardShortcut("n")
                    .disabled(session.phase != .signedIn)
            }
            CommandMenu("Go") {
                Button("Today") { session.route = .today }.keyboardShortcut("1")
                Button("Activity") { session.route = .activity }.keyboardShortcut("2")
                Button("Plan") { session.route = .plan }.keyboardShortcut("3")
                Button("Wealth") { session.route = .wealth }.keyboardShortcut("4")
            }
        }
        // Keeps bill reminders and budget alerts current while the app is
        // closed: iOS wakes it now and then (more often for people who open
        // it often) to refresh the numbers.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()
            await session.backgroundRefresh()
        }
    }
}

/// The background refresh Artha asks iOS for: no sooner than every few
/// hours; iOS picks the real moment.
nonisolated enum BackgroundRefresh {
    static let identifier = "studio.anwarcreative.artha.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Shows Artha's notifications while the app is open too, and opens the
/// right tab when one is tapped.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var session: AppSession?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo["route"] as? String
        await MainActor.run {
            if let route, let url = URL(string: "artha://\(route)") { session?.open(url) }
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
        // iPhone keeps its bottom tab bar; iPad gets Apple's floating top
        // bar that opens into a sidebar.
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            HStack(spacing: 10) {
                OrbMark().frame(width: 26, height: 26)
                Text("Artha")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.vertical, 4)
        }
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
