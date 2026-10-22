import SwiftUI
import UserNotifications

/// What Artha reminds you about, and when. The bill and budget switches and
/// the hour are the same ones the website uses; Apple Pay is this iPhone's.
struct NotificationsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var status: UNAuthorizationStatus?
    @State private var applePay = UserDefaults.standard.object(forKey: Reminders.applePayKey) as? Bool ?? true
    @State private var error: String?

    var body: some View {
        Form {
            permissionSection
            if let user = session.user {
                Section {
                    Toggle(isOn: binding(\.notifyBillsDue, key: "notify_bills_due", user: user)) {
                        Label("Bills due tomorrow", systemImage: "calendar")
                    }
                    Toggle(isOn: binding(\.notifyBudgetAlerts, key: "notify_budget_alerts", user: user)) {
                        Label("Over budget", systemImage: "exclamationmark.circle")
                    }
                    if ThisDevice.canAutomateApplePay {
                        Toggle(isOn: $applePay) {
                            Label("Apple Pay purchases", systemImage: "wave.3.right")
                        }
                    }
                    Picker(selection: hourBinding(user)) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(Self.hourLabel(hour)).tag(hour)
                        }
                    } label: {
                        Label("Bill reminders at", systemImage: "clock")
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.secondary)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(Palette.caution).announcedWhenShown(error)
                    } else {
                        Text("A bill reminder comes the day before it's due. Budget alerts come once a month per budget, the moment it's reached. The bill and budget settings and the time also apply on arthaapp.com.")
                    }
                }
                .listRowBackground(Palette.surface)
                .tint(Palette.accent)
            }
            Section {
            } footer: {
                Text("Notifications are made on this \(ThisDevice.name) from numbers it already has, so no notification service sees your money.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle("Notifications")
        .inlineTitle()
        .task { status = await Reminders.status() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { status = await Reminders.status() } }
        }
        .onChange(of: applePay) { _, on in UserDefaults.standard.set(on, forKey: Reminders.applePayKey) }
        .sensoryFeedback(.error, trigger: error) { _, value in value != nil }
    }

    // MARK: Permission

    @ViewBuilder
    private var permissionSection: some View {
        switch status {
        case .denied:
            Section {
                Text("Notifications are off for Artha in your \(ThisDevice.name)'s settings.")
                    .foregroundStyle(Palette.ink)
                Button(ThisDevice.name == "Mac" ? "Open System Settings" : "Open \(ThisDevice.name) Settings") {
                    if let url = SystemSettings.notificationsURL { openURL(url) }
                }
            }
            .listRowBackground(Palette.surface)
        case .notDetermined, .provisional:
            Section {
                Text(status == .provisional
                     ? "Right now they arrive quietly in Notification Center. Turn on banners and sounds so a bill reminder actually gets seen."
                     : "Turn on notifications for bill reminders and budget alerts.")
                    .foregroundStyle(Palette.ink)
                Button("Turn on banners and sounds") {
                    Task {
                        _ = await Reminders.askForBanners()
                        status = await Reminders.status()
                        await session.updateReminders()
                    }
                }
            }
            .listRowBackground(Palette.surface)
        default:
            EmptyView()
        }
    }

    // MARK: Saving

    /// A switch saved to the account (shared with the website).
    private func binding(_ keyPath: KeyPath<APIUser, Bool?>, key: String, user: APIUser) -> Binding<Bool> {
        Binding(
            get: { session.user?[keyPath: keyPath] ?? true },
            set: { value in save([key: value]) }
        )
    }

    private func hourBinding(_ user: APIUser) -> Binding<Int> {
        Binding(get: { session.user?.reminderHour ?? 8 }, set: { save(["reminder_hour": $0]) })
    }

    private func save(_ change: [String: Any]) {
        error = nil
        Task {
            do {
                try await session.updateProfile(change)
                await session.updateReminders()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }

    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
