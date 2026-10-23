import Foundation
import OSLog
import UserNotifications

/// Artha's notifications, made on this iPhone from numbers the app already
/// has, so no notification service ever sees anyone's money:
///
/// - **Bills due tomorrow**, at the reminder hour. Copilot only says a bill
///   was paid; the day before is when a reminder can still change something.
/// - **Over budget**, once a month for the monthly budget and each category
///   limit, the same rule as the website's alerts.
/// - **Apple Pay purchase logged**, with what's now safe to spend.
///
/// Permission starts as a quiet trial (Apple's provisional authorization:
/// delivered silently to Notification Center, with Keep and Turn Off), and
/// the full prompt only appears when someone asks for banners in Settings.
/// The bill and budget switches and the hour are shared with the website.
@MainActor
enum Reminders {
    static let applePayKey = "notify.applePay"
    private static let alertedKey = "notify.budgetAlerted"
    private static let paceKey = "notify.paceAlerted"
    private static let billPrefix = "bill."
    private static let log = Logger(subsystem: "studio.anwarcreative.artha", category: "Reminders")

    // MARK: Permission

    /// The quiet trial, asked for without a prompt right after signing in.
    static func startQuietTrial() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
    }

    /// The real prompt, for banners and sounds. Returns whether they're on.
    static func askForBanners() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private static func allowed() async -> Bool {
        switch await status() {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    // MARK: Bills

    /// Replaces every scheduled bill reminder with one per day that has
    /// bills due, fired the day before at the reminder hour.
    static func scheduleBills(_ summary: TodaySummary, user: APIUser) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(billPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard user.notifyBillsDue ?? true, await allowed() else { return }

        let calendar = Calendar.current
        let hour = user.reminderHour ?? 8
        let byDay = Dictionary(grouping: summary.comingUp, by: \.due)
        for (due, bills) in byDay {
            guard let dueDate = Date.apiDay(due),
                  let dayBefore = calendar.date(byAdding: .day, value: -1, to: dueDate),
                  let fireAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayBefore),
                  fireAt > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Due tomorrow"
            content.body = billsLine(bills)
            content.sound = .default
            content.threadIdentifier = "bills"
            content.userInfo = ["route": "plan"]
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: billPrefix + due, content: content, trigger: trigger))
        }
        let scheduled = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(billPrefix) }.count
        log.info("Bill reminders scheduled: \(scheduled)")
    }

    /// "Rent, $1,650, is due tomorrow." or "Rent, Spotify and Gym class are
    /// due tomorrow."
    static func billsLine(_ bills: [TodaySummary.Bill]) -> String {
        let sorted = bills.sorted { $0.description < $1.description }
        if sorted.count == 1, let bill = sorted.first {
            return "\(bill.description), \(Money.natural(Decimal.api(bill.amount), bill.currency)), is due tomorrow."
        }
        let names = sorted.map(\.description)
        let list = names.count == 2
            ? "\(names[0]) and \(names[1])"
            : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        return "\(list) are due tomorrow."
    }

    // MARK: Budget

    /// Alerts once a month for the budget and for each category limit, the
    /// moment spending reaches it, like the website does.
    static func checkBudget(_ summary: TodaySummary, limits: [PlanSummary.Limit], user: APIUser) async {
        guard user.notifyBudgetAlerts ?? true, await allowed() else { return }
        let month = String(summary.date.prefix(7))
        let defaults = UserDefaults.standard
        var stored = defaults.dictionary(forKey: alertedKey) as? [String: [String]] ?? [:]
        stored = stored.filter { $0.key == month }
        var alerted = Set(stored[month] ?? [])

        var lines: [String] = []
        if let budget = summary.budget, Decimal.api(budget.spent) >= Decimal.api(budget.cap), !alerted.contains("budget") {
            lines.append("You're over your \(Money.whole(Decimal.api(budget.cap), summary.currency)) monthly budget.")
            alerted.insert("budget")
        }
        for limit in limits where Decimal.api(limit.spent) >= Decimal.api(limit.cap) && !alerted.contains(limit.key) {
            lines.append("You're over your \(limit.label) budget.")
            alerted.insert(limit.key)
        }
        defaults.set([month: Array(alerted)], forKey: alertedKey)
        guard !lines.isEmpty else { return }

        let content = UNMutableNotificationContent()
        log.info("Budget alert: \(lines.count) newly over")
        content.title = "Budget alert"
        content.body = lines.count == 1 ? lines[0] : "\(lines.count) budgets just went over: " + lines.joined(separator: " ")
        content.sound = .default
        content.threadIdentifier = "budget"
        content.userInfo = ["route": "plan"]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "budget.\(month).\(alerted.sorted().joined(separator: "-"))", content: content, trigger: nil))
    }

    // MARK: Pace

    /// A heads-up, once a month, when spending first runs ahead of an even
    /// pace and there's still room to ease off (the server's status
    /// "ahead"; "over" is checkBudget's). Only for someone who turned it
    /// on, never before the 5th, and re-armed once spending is back at an
    /// even pace, like the website's push.
    static func checkPace(_ summary: TodaySummary, user: APIUser) async {
        guard user.notifyPaceHeadsUp == true, let safe = summary.safeToSpend, await allowed() else { return }
        let month = String(summary.date.prefix(7))
        let defaults = UserDefaults.standard
        if defaults.string(forKey: paceKey) == month {
            if Decimal.api(summary.spent) <= Decimal.api(safe.evenPaceSpent) { defaults.removeObject(forKey: paceKey) }
            return
        }
        guard safe.status == "ahead", summary.month.day >= 5 else { return }
        defaults.set(month, forKey: paceKey)

        let content = UNMutableNotificationContent()
        content.title = "Heads-up"
        content.body = "You're ahead of pace for \(summary.month.name). Up to \(Money.whole(Decimal.api(safe.perDay), summary.currency)) a day keeps it on plan."
        content.threadIdentifier = "budget"
        content.userInfo = ["route": "plan"]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "pace.\(month)", content: content, trigger: nil))
    }

    // MARK: Apple Pay

    /// Right after a purchase logs itself: what it was, and where the
    /// month stands now.
    static func purchaseLogged(_ line: String, safeToSpend: String?) async {
        guard UserDefaults.standard.object(forKey: applePayKey) as? Bool ?? true, await allowed() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Apple Pay"
        content.body = [line, safeToSpend.map { "\($0) safe to spend." }].compactMap { $0 }.joined(separator: " ")
        content.threadIdentifier = "applePay"
        content.userInfo = ["route": "today"]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "applePay.\(UUID().uuidString)", content: content, trigger: nil))
    }

    // MARK: Signing out

    static func clearAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        UserDefaults.standard.removeObject(forKey: alertedKey)
        UserDefaults.standard.removeObject(forKey: paceKey)
    }
}
