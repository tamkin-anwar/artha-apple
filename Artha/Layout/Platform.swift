import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// The few things iPhone and iPad do that a Mac doesn't (on-screen keyboards,
// navigation bar title styles, the tab bar shrinking on scroll), wrapped so
// every screen is written once. On iPhone and iPad these are exactly the
// UIKit-era modifiers they replace; on the Mac they step aside.

enum Keyboard {
    case email, number, decimal, ascii
}

extension View {
    /// The on-screen keyboard to show; Macs type on a real one.
    func keyboard(_ kind: Keyboard) -> some View {
        #if os(iOS)
        switch kind {
        case .email: return AnyView(keyboardType(.emailAddress))
        case .number: return AnyView(keyboardType(.numberPad))
        case .decimal: return AnyView(keyboardType(.decimalPad))
        case .ascii: return AnyView(keyboardType(.asciiCapable))
        }
        #else
        return AnyView(self)
        #endif
    }

    /// Usernames, emails and codes: never capitalize the first letter.
    func noAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// Names: capitalize each word.
    func capitalizeWords() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words)
        #else
        self
        #endif
    }

    /// A small title in the navigation bar (iPhone and iPad).
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Large under the floating iPad tab bar, inline-large on iPhone; a Mac
    /// window shows the title in its toolbar.
    func screenTitleStyle(large: Bool) -> some View {
        #if os(iOS)
        toolbarTitleDisplayMode(large ? .large : .inlineLarge)
        #else
        self
        #endif
    }

    /// Today draws its own header, so it hides the iPhone/iPad navigation
    /// bar; a Mac window keeps its toolbar.
    func hideNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// The iPhone tab bar shrinks while scrolling down.
    func minimizeTabBarOnScroll() -> some View {
        #if os(iOS)
        tabBarMinimizeBehavior(.onScrollDown)
        #else
        self
        #endif
    }
}

extension SearchFieldPlacement {
    /// Always showing under the title on iPhone and iPad; in the window's
    /// toolbar on a Mac, where Command-F reaches it.
    static var alwaysVisible: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .toolbar
        #endif
    }
}

/// What to call this device in the app's words.
enum ThisDevice {
    /// "iPhone", "iPad" or "Mac".
    static var name: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// Apple Pay purchases can log themselves only through the iPhone's
    /// Wallet automation in Shortcuts; a Mac has none.
    static var canAutomateApplePay: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

enum SystemSettings {
    /// Where this app's notification settings live: the iPhone's Settings
    /// app, or System Settings > Notifications on a Mac.
    static var notificationsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openNotificationSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #endif
    }
}
