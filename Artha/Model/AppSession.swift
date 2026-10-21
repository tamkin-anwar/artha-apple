import Foundation
import Observation

/// Whether this device is signed in, who to, and the calls that change
/// that. Owns the API client and every screen's model.
///
/// Fast by design: a signed-in launch shows the last numbers this device
/// saw (ResponseCache) immediately and refreshes them in the background;
/// independent requests run side by side rather than one after another;
/// Plan and Activity load behind Today so switching tabs never waits; and
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
    /// One-time note after a sign-in that canceled a pending deletion.
    var notice: String?
    /// Opens the monthly budget editor from anywhere (Today's cards, Plan).
    var isEditingBudget = false

    let month = MonthModel()
    let activity: ActivityModel
    let plan: PlanModel
    private let api: APIClient
    private var lastRefresh: Date?

    init() {
        let api = APIClient()
        self.api = api
        activity = ActivityModel(api: api)
        plan = PlanModel(api: api)
        // An edit in Activity or Plan changes this month's numbers too.
        activity.onChange = { [weak self] in await self?.refreshAfterChange(reloadActivity: false) }
        plan.onChange = { [weak self] in await self?.refresh() }
    }

    func start() async {
        guard phase == .checking else { return }
        guard let token = Keychain.read(account: Keychain.tokenAccount) else {
            phase = .signedOut
            return
        }
        api.token = token
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
        Keychain.save(response.token, account: Keychain.tokenAccount)
        api.token = response.token
        user = response.user
        if response.deletionCanceled {
            notice = "Welcome back. Your account deletion has been canceled."
        }
        phase = .signedIn
        await refresh()
        prefetch()
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
            month.apply(summary)
            ResponseCache.save(data, as: .today)
            refreshError = nil
            lastRefresh = .now
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
        async let today: Void = refresh()
        async let plan: Void = planShown ? self.plan.load() : ()
        _ = await (today, plan)
    }

    func addTransaction(description: String, amount: Decimal, type: String) async throws {
        let body: [String: Any] = [
            "description": description,
            "amount": NSDecimalNumber(decimal: amount).stringValue,
            "type": type,
            "currency": month.currencyCode,
        ]
        let _: TransactionEnvelope = try await api.post("transactions", body: body)
        month.noteAdded()
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
    }

    /// Loads Plan and Activity behind Today, so the first tap on either
    /// shows real content instead of a spinner.
    private func prefetch() {
        guard phase == .signedIn else { return }
        Task {
            async let plan: Void = self.plan.load()
            async let list: Void = activity.reload()
            _ = await (plan, list)
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
    }

    private func signOutLocally() {
        Keychain.delete(account: Keychain.tokenAccount)
        ResponseCache.clear()
        api.token = nil
        user = nil
        lastRefresh = nil
        month.clear()
        activity.clear()
        plan.clear()
        refreshError = nil
        isEditingBudget = false
        phase = .signedOut
    }

    private var deviceName: String {
        #if targetEnvironment(simulator)
        "iPhone Simulator"
        #else
        "iPhone"
        #endif
    }
}
