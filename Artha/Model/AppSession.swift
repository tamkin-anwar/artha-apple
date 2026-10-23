import Foundation
import Observation
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

/// Whether this device is signed in, who to, and the calls that change
/// that. Owns the API client and every screen's model.
///
/// Fast by design: a signed-in launch shows the last numbers this device
/// saw (ResponseCache) immediately and refreshes them in the background;
/// independent requests run side by side rather than one after another;
/// Plan, Activity and Wealth load behind Today so switching tabs never waits; and
/// coming back to the app within a few seconds doesn't refetch anything.
@Observable
final class AppSession {
    enum Phase { case checking, signedOut, signedIn }

    /// How recent a refresh has to be for coming back to the app to skip
    /// another one (switching apps for a moment shouldn't cost a reload).
    static let freshFor: TimeInterval = 30

    private(set) var phase: Phase = .checking
    private(set) var user: APIUser?
    private(set) var isRefreshing = false
    /// Shown on Today when the latest refresh failed; the last good data
    /// stays on screen underneath it.
    private(set) var refreshError: String?
    /// One-time note: a sign-in that canceled a pending deletion (shown on
    /// Today), or a deletion that just started (shown on Sign In).
    var notice: String?
    /// Opens the monthly budget editor from anywhere (Today's cards, Plan).
    var isEditingBudget = false
    /// Opens the Apple Pay automation guide from anywhere.
    var isShowingApplePaySetup = false
    /// Opens the review of purchases that logged themselves.
    var isReviewing = false
    /// Opens Settings (tapping your initials on Today).
    var isShowingSettings = false
    /// The phone's time zone has been sent this launch (see syncTimeZone).
    private var timeZoneSynced = false
    /// Where a widget tap or artha:// link asked to go; MainTabs consumes it.
    var route: AppRoute?
    /// Bumped by Search Transactions (Command-F) to put the cursor in
    /// Activity's search field.
    var searchRequest = 0
    /// Opens the statement file picker (Activity's Import button, or
    /// Import a Statement, Shift-Command-I).
    var isPickingStatement = false

    let month = MonthModel()
    let activity: ActivityModel
    let plan: PlanModel
    let wealth: WealthModel
    private let api: APIClient
    private var lastRefresh: Date?

    init() {
        let api = APIClient()
        self.api = api
        activity = ActivityModel(api: api)
        plan = PlanModel(api: api)
        wealth = WealthModel(api: api)
        // An edit in Activity, Plan or Wealth changes Today's numbers too.
        activity.onChange = { [weak self] in await self?.refreshAfterChange(reloadActivity: false) }
        plan.onChange = { [weak self] in await self?.refresh() }
        wealth.onChange = { [weak self] in await self?.refresh() }
    }

    func start() async {
        guard phase == .checking else { return }
        guard let token = Keychain.read(account: Keychain.tokenAccount) else {
            phase = .signedOut
            return
        }
        api.token = token
        // Tokens saved before the widgets existed move into the Keychain
        // group the widgets can read.
        Keychain.migrateToSharedGroup(account: Keychain.tokenAccount)
        restoreFromCache()
        phase = .signedIn
        await refresh()
        prefetch()
    }

    /// Throws `.twoFactorRequired` when the account needs a code; call
    /// again with `code` set.
    func signIn(username: String, password: String, code: String?) async throws {
        var body: [String: Any] = ["username": username, "password": password, "device_name": deviceName]
        if let code, !code.isEmpty { body["code"] = code }
        let response: SessionResponse = try await api.post("sessions", body: body)
        if response.deletionCanceled {
            notice = "Welcome back. Your account deletion has been canceled."
        }
        await begin(response)
    }

    /// Creates an account and signs this iPhone in, in one step. The
    /// phone's own timezone goes along so "today" starts out right.
    func signUp(firstName: String, email: String, username: String, password: String, currency: String) async throws {
        let body: [String: Any] = [
            "first_name": firstName, "email": email, "username": username, "password": password,
            "currency": currency, "timezone": TimeZone.current.identifier, "device_name": deviceName,
        ]
        let response: SessionResponse = try await api.post("users", body: body)
        await begin(response)
    }

    /// Starts the 30-day deletion window (signing back in cancels it). The
    /// server signs every device out, so this one forgets everything too.
    func deleteAccount(password: String) async throws {
        let response: DeletionResponse = try await api.delete("me", body: ["password": password])
        signOutLocally()
        notice = "Your account will be deleted on \(response.purgeDate). Sign in before then if you change your mind."
    }

    private func begin(_ response: SessionResponse) async {
        Keychain.save(response.token, account: Keychain.tokenAccount)
        api.token = response.token
        user = response.user
        phase = .signedIn
        await refresh()
        prefetch()
        await Reminders.startQuietTrial()
        await updateReminders()
    }

    func signOut() async {
        try? await api.delete("sessions/current")
        signOutLocally()
    }

    /// Refreshes Today (and who's signed in, the first time) in parallel.
    func refresh() async {
        guard phase == .signedIn else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let today: (TodaySummary, Data) = api.fetch("today")
            if user == nil {
                let (envelope, data): (UserEnvelope, Data) = try await api.fetch("me")
                user = envelope.user
                ResponseCache.save(data, as: .me)
            }
            let (summary, data) = try await today
            // The currency changed somewhere else (the website, another
            // device): every screen and Settings follow it, not just Today.
            let previousCurrency = month.summary?.currency ?? user?.currency
            month.apply(summary)
            // (A change made in this app's Settings already updated `user`
            // and reloads everything itself.)
            if let previousCurrency, previousCurrency != summary.currency, user?.currency != summary.currency {
                Task { await self.followCurrencyChange() }
            }
            ResponseCache.save(data, as: .today)
            Self.publishToWidgets(data)
            refreshError = nil
            lastRefresh = .now
            await syncTimeZone()
            await updateReminders()
        } catch APIError.unauthorized {
            signOutLocally()
        } catch let error as APIError {
            refreshError = error.message
        } catch {
            refreshError = "Artha couldn't read today's numbers. Pull down to try again."
        }
    }

    /// Coming back to the app: refresh whatever's been loaded, unless it
    /// was refreshed a moment ago.
    func becameActive() async {
        guard phase == .signedIn else { return }
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < Self.freshFor { return }
        let planShown = plan.summary != nil
        let wealthShown = wealth.summary != nil
        async let today: Void = refresh()
        async let plan: Void = planShown ? self.plan.load() : ()
        async let wealth: Void = wealthShown ? self.wealth.load() : ()
        _ = await (today, plan, wealth)
        // Category limits come from the plan, which may land after Today.
        if planShown { await updateReminders() }
    }

    /// `currency` is the one it was paid in; nil means the display currency.
    func addTransaction(description: String, amount: Decimal, type: String, currency: String? = nil) async throws {
        let body: [String: Any] = [
            "description": description,
            "amount": NSDecimalNumber(decimal: amount).stringValue,
            "type": type,
            "currency": currency ?? month.currencyCode,
        ]
        let _: TransactionEnvelope = try await api.post("transactions", body: body)
        month.noteAdded()
        await refreshAfterChange(reloadActivity: true)
    }

    /// This month's transactions in the given categories ("none" for
    /// uncategorized), for the transactions behind a Today number.
    func monthTransactions(categories: [String]) async throws -> TransactionPage {
        var components = URLComponents()
        components.path = "transactions"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "type", value: "expense"),
            URLQueryItem(name: "month", value: String((month.summary?.date ?? "").prefix(7))),
            URLQueryItem(name: "category", value: categories.joined(separator: ",")),
        ]
        return try await api.get(components.string ?? "transactions")
    }

    // MARK: Notifications

    /// Reschedules bill reminders and checks the budget against the latest
    /// numbers. Runs after every refresh, including in the background.
    func updateReminders() async {
        guard let summary = month.summary, let user else { return }
        await Reminders.scheduleBills(summary, user: user)
        await Reminders.checkBudget(summary, limits: plan.limits, user: user)
        await Reminders.checkPace(summary, user: user)
    }

    /// Answers Today's one-time pace heads-up card. Turning it on also asks
    /// for notifications, since that's how it arrives. Either answer is
    /// kept on the account, so the card doesn't come back on any device.
    func answerPacePrompt(turnOn: Bool) async throws {
        if turnOn { _ = await Reminders.askForBanners() }
        try await updateProfile(["notify_pace_heads_up": turnOn, "pace_prompt_answered": true])
        await refresh()
    }

    /// A background refresh: the numbers, then reminders and widgets, with
    /// nothing on screen. iOS decides when (Settings > General >
    /// Background App Refresh has to be on).
    func backgroundRefresh() async {
        guard phase == .signedIn else { return }
        await plan.load()
        await refresh()  // ends with updateReminders(), with the plan already in
    }

    // MARK: Settings

    /// Saves profile changes (any of first_name, last_name, email,
    /// currency, timezone). A new currency changes every total, so all
    /// of them reload.
    func updateProfile(_ changes: [String: Any]) async throws {
        let (envelope, data): (UserEnvelope, Data) = try await api.patchKeeping("me", body: changes)
        let currencyChanged = envelope.user.currency != user?.currency
        user = envelope.user
        ResponseCache.save(data, as: .me)
        if currencyChanged { await refreshEverything() }
    }

    /// The new password signs every device out, this one included, so the
    /// server hands this one a fresh token to keep going.
    func changePassword(current: String, new: String) async throws {
        let response: PasswordChanged = try await api.post("me/password",
                                                           body: ["current_password": current, "new_password": new])
        Keychain.save(response.token, account: Keychain.tokenAccount)
        api.token = response.token
        user = response.user
    }

    /// Who's signed in, fresh from the server, for Settings to show the
    /// current name, email and two-factor state (the saved copy can be
    /// older than a change made on the web).
    func refreshUser() async {
        guard let (envelope, data): (UserEnvelope, Data) = try? await api.fetch("me") else { return }
        user = envelope.user
        ResponseCache.save(data, as: .me)
    }

    func startTwoFactor() async throws -> TwoFactorSetup {
        try await api.post("me/two-factor/setup", body: [:])
    }

    /// Returns the recovery codes, shown once.
    func enableTwoFactor(secret: String, code: String) async throws -> [String] {
        let response: TwoFactorEnabled = try await api.post("me/two-factor", body: ["secret": secret, "code": code])
        user = response.user
        return response.recoveryCodes
    }

    func disableTwoFactor(password: String, code: String) async throws {
        let envelope: UserEnvelope = try await api.delete("me/two-factor", body: ["password": password, "code": code])
        user = envelope.user
    }

    /// Keeps the account's "today" on the phone's clock, the way the
    /// website follows the browser's: once a launch, only if it differs.
    private func syncTimeZone() async {
        guard !timeZoneSynced, let user else { return }
        timeZoneSynced = true
        let here = TimeZone.current.identifier
        guard user.timezone != here else { return }
        try? await updateProfile(["timezone": here])
    }

    /// Command-R: every screen, now, even if it was just refreshed.
    func refreshEverythingNow() async {
        guard phase == .signedIn else { return }
        await refreshEverything()
    }

    /// Today noticed a new display currency set on another device: catch
    /// Settings, Plan, Activity and Wealth up so nothing shows the old one.
    private func followCurrencyChange() async {
        await refreshUser()
        async let plan: Void = self.plan.summary != nil ? self.plan.load() : ()
        async let list: Void = activity.reload()
        async let wealth: Void = self.wealth.summary != nil ? self.wealth.load() : ()
        _ = await (plan, list, wealth)
        await updateReminders()
    }

    /// Every screen at once, e.g. after the display currency changes.
    private func refreshEverything() async {
        async let today: Void = refresh()
        async let plan: Void = self.plan.load()
        async let list: Void = activity.reload()
        async let wealth: Void = self.wealth.load()
        _ = await (today, plan, list, wealth)
    }

    /// Purchases that logged themselves and are waiting for a look,
    /// newest first.
    func reviewQueue() async throws -> TransactionPage {
        try await api.get("transactions?review=1&limit=200")
    }

    /// These look right as they are.
    func markReviewed(_ ids: [Int]) async throws {
        let _: ReviewedResponse = try await api.post("transactions/reviewed", body: ["ids": ids])
    }

    /// Closing the review: the count on Today, and the list in Activity,
    /// catch up with what was confirmed.
    func refreshAfterReview() async {
        await refreshAfterChange(reloadActivity: true)
    }

    /// After anything that changes this month's money: Today, Plan and (if
    /// asked) Activity reload side by side.
    private func refreshAfterChange(reloadActivity: Bool) async {
        let planShown = plan.summary != nil
        let listShown = reloadActivity && activity.hasLoaded
        async let today: Void = refresh()
        async let plan: Void = planShown ? self.plan.load() : ()
        async let list: Void = listShown ? activity.reload() : ()
        _ = await (today, plan, list)
        // Category limits come from the plan, which may land after Today.
        if planShown { await updateReminders() }
    }

    /// Loads Plan, Activity and Wealth behind Today, so the first tap on
    /// any of them shows real content instead of a spinner.
    private func prefetch() {
        guard phase == .signedIn else { return }
        Task {
            async let plan: Void = self.plan.load()
            async let list: Void = activity.reload()
            async let wealth: Void = self.wealth.load()
            _ = await (plan, list, wealth)
            await updateReminders()
        }
    }

    private func restoreFromCache() {
        if user == nil, let data = ResponseCache.load(.me), let envelope = api.decode(UserEnvelope.self, from: data) {
            user = envelope.user
        }
        if month.summary == nil, let data = ResponseCache.load(.today),
           let summary = api.decode(TodaySummary.self, from: data) {
            month.apply(summary)
        }
        if let data = ResponseCache.load(.plan) { plan.restore(from: data) }
        if let data = ResponseCache.load(.activity) { activity.restore(from: data) }
        if let data = ResponseCache.load(.wealth) { wealth.restore(from: data) }
    }

    /// Hands the widgets fresh numbers, and asks them to redraw only when
    /// something actually changed.
    nonisolated static func publishToWidgets(_ todayData: Data) {
        if WidgetStore.saveToday(todayData) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.glanceKind)
        }
    }

    /// artha://add, artha://plan and so on.
    func open(_ url: URL) {
        // A statement opened in Artha from Files, Mail or the share sheet.
        if url.isFileURL {
            statementToImport = url
            route = .activity
            return
        }
        guard url.scheme == "artha", let route = AppRoute(rawValue: url.host() ?? "") else { return }
        self.route = route
    }

    /// A bank statement handed to Artha from outside (Open in Artha), read
    /// in place and never copied; Activity picks it up and starts importing.
    var statementToImport: URL?

    /// Reads a statement without saving anything; the review comes next.
    func previewStatement(_ file: Data, filename: String, password: String?) async throws -> StatementPreview {
        let name = filename.lowercased()
        let mime = name.hasSuffix(".pdf") ? "application/pdf"
            : name.hasSuffix(".csv") ? "text/csv"
            : "application/octet-stream" // OFX, QFX, QIF: the server reads what's inside
        return try await api.upload("imports/preview", file: file, field: "statement", filename: filename,
                                    mimeType: mime, fields: password.map { ["pdf_password": $0] } ?? [:])
    }

    /// Saves the rows kept in review, then refreshes everything they touch.
    func importStatement(_ rows: [StatementRow]) async throws -> ImportResult {
        let result: ImportResult = try await api.post("imports", body: ["rows": rows.map(\.asBody)])
        await refreshAfterChange(reloadActivity: true)
        return result
    }

    private func signOutLocally() {
        Reminders.clearAll()
        Keychain.delete(account: Keychain.tokenAccount)
        ResponseCache.clear()
        WidgetStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
        api.token = nil
        user = nil
        lastRefresh = nil
        month.clear()
        activity.clear()
        plan.clear()
        wealth.clear()
        refreshError = nil
        isEditingBudget = false
        isShowingApplePaySetup = false
        isReviewing = false
        isShowingSettings = false
        timeZoneSynced = false
        phase = .signedOut
    }

    /// How this device appears in the account's list of signed-in devices.
    private var deviceName: String {
        #if os(macOS)
        "Mac"
        #elseif targetEnvironment(simulator)
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad Simulator" : "iPhone Simulator"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}
