import Foundation

/// What the app and its widgets share: the latest /api/v1/today response,
/// kept in the App Group container so a widget can draw the moment it's
/// asked, plus where the server is. The widget also fetches a fresh copy
/// itself (with the token from the shared Keychain group), so it stays
/// current even on days the app isn't opened.
nonisolated enum WidgetStore {
    static let appGroup = "group.studio.anwarcreative.artha"
    static let glanceKind = "Glance"

    /// The simulator talks to the Mac's local dev server; a real device to
    /// arthaapp.com. Same rule as APIClient.
    static let baseURL: URL = {
        #if targetEnvironment(simulator)
        URL(string: "http://localhost:5050/api/v1/")!
        #else
        URL(string: "https://arthaapp.com/api/v1/")!
        #endif
    }()

    private static var todayFile: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "today.json")
    }

    static func loadToday() -> Data? {
        todayFile.flatMap { try? Data(contentsOf: $0) }
    }

    /// Saves a new response; returns false when nothing changed, so callers
    /// only ask widgets to redraw when there's something new to show.
    /// Readable after the first unlock since boot, because widgets on the
    /// Lock Screen draw while the phone is locked.
    @discardableResult
    static func saveToday(_ data: Data) -> Bool {
        guard let file = todayFile else { return false }
        if let existing = try? Data(contentsOf: file), existing == data { return false }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }

    static func clear() {
        if let file = todayFile { try? FileManager.default.removeItem(at: file) }
    }
}
