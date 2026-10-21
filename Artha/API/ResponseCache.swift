import Foundation

/// The last good response for each screen, kept on this device so the app
/// opens straight to real numbers and refreshes them in the background,
/// instead of opening to a spinner. Stored in the app's Caches folder with
/// complete file protection (encrypted whenever the phone is locked) and
/// wiped on sign-out, so nothing outlives the session that fetched it.
nonisolated enum ResponseCache {
    enum Key: String, CaseIterable {
        case me, today, plan, activity, wealth
    }

    private static var directory: URL {
        URL.cachesDirectory.appending(path: "Responses", directoryHint: .isDirectory)
    }

    static func load(_ key: Key) -> Data? {
        try? Data(contentsOf: directory.appending(path: key.rawValue))
    }

    /// Written off the main thread so saving never costs a frame.
    static func save(_ data: Data, as key: Key) {
        let folder = directory
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: folder.appending(path: key.rawValue), options: [.atomic, .completeFileProtection])
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
