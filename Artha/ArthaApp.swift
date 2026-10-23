#if os(iOS)
import BackgroundTasks
#endif
import SwiftUI
import UserNotifications

@main
struct ArthaApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        #if os(iOS)
        mainWindow
            // Keeps bill reminders and budget alerts current while the app
            // is closed: iOS wakes it now and then (more often for people
            // who open it often) to refresh the numbers.
            .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
                BackgroundRefresh.schedule()
                await session.backgroundRefresh()
            }
        #else
        mainWindow
            .defaultSize(width: 1240, height: 860)
            .windowResizability(.contentMinSize)
        // Command-comma, the Mac's own place for settings.
        Settings {
            SettingsView()
                .environment(session)
                .environment(session.month)
                .frame(width: 540, height: 720)
        }
        #endif
    }

    private var mainWindow: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(session.month)
                .onOpenURL { session.open($0) }
                .task { appDelegate.session = session }
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 600)
                // Artha's cards and rows are the borders; without this every
                // Mac text field draws its own box inside them too. (iPhone
                // and iPad fields are already plain.)
                .textFieldStyle(.plain)
                #endif
        }
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            if phase == .background { BackgroundRefresh.schedule() }
            #endif
        }
        // The menu bar on a Mac and on iPad (swipe down from the top, or
        // hold Command to see the shortcuts). Each item carries the symbol
        // it has in the app, and items that don't apply right now are
        // disabled, never hidden, so they stay where people expect them
        // (Apple's iPadOS 26 menu bar guidance).
        .commands {
            let signedIn = session.phase == .signedIn
            // View > Show/Hide Sidebar (Control-Command-S), the toggle
            // Apple's guidance puts in every View menu.
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Add Transaction", systemImage: "plus") { session.route = .add }
                    .keyboardShortcut("n")
                    .disabled(!signedIn)
            }
            #if os(iOS)
            // A Mac has its own Settings window on Command-comma; iPad gets
            // the same shortcut for the Settings sheet.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…", systemImage: "gearshape") { session.isShowingSettings = true }
                    .keyboardShortcut(",")
                    .disabled(!signedIn)
            }
            #endif
            CommandMenu("Go") {
                Group {
                Button("Today", systemImage: "gauge.with.dots.needle.33percent") { session.route = .today }
                    .keyboardShortcut("1")
                Button("Activity", systemImage: "list.bullet") { session.route = .activity }
                    .keyboardShortcut("2")
                Button("Plan", systemImage: "chart.line.uptrend.xyaxis") { session.route = .plan }
                    .keyboardShortcut("3")
                Button("Wealth", systemImage: "chart.bar.fill") { session.route = .wealth }
                    .keyboardShortcut("4")
                Divider()
                Button("Search Transactions", systemImage: "magnifyingglass") {
                    session.route = .activity
                    session.searchRequest += 1
                }
                .keyboardShortcut("f")
                Divider()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await session.refreshEverythingNow() } }
                    .keyboardShortcut("r")
                }
                .disabled(!signedIn)
            }
            CommandMenu("Money") {
                Button("Review Purchases", systemImage: "checkmark.circle") { session.isReviewing = true }
                    .disabled(!signedIn || session.month.toReview == 0)
                Button("Set Budget…", systemImage: "slider.horizontal.3") { session.isEditingBudget = true }
                    .disabled(!signedIn)
                Button("Import a Statement…", systemImage: "square.and.arrow.down") {
                    session.route = .activity
                    session.isPickingStatement = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!signedIn)
            }
        }
    }
}

#if os(iOS)
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
#endif

/// Shows Artha's notifications while the app is open too, and opens the
/// right tab when one is tapped.
final class AppDelegate: NSObject, UNUserNotificationCenterDelegate {
    var session: AppSession?

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

#if os(iOS)
extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}
#else
extension AppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // One window, so no window tabs: otherwise View offers "Show Tab
        // Bar" and "Show All Tabs", which do nothing useful here.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    /// Closing the last window quits, the way single-window Mac apps do.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif

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

    private var windowTitle: String {
        switch selection {
        case .today, .add: "Today"
        case .activity: "Activity"
        case .plan: "Plan"
        case .wealth: "Wealth"
        }
    }

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
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.vertical, 4)
        }
        .minimizeTabBarOnScroll()
        .windowTitle(windowTitle)
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
        // Once, here, not on Activity: the Mac builds a tab's view more
        // than once while it settles, and a copy that gets thrown away
        // would take an opened statement, and its review, with it.
        .statementImport(isPicking: $session.isPickingStatement, isScanning: $session.isScanningStatement)
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
