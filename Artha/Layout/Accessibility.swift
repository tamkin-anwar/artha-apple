import SwiftUI

// Two things Apple's App Store accessibility criteria check that SwiftUI
// doesn't do on its own.

extension View {
    /// Speaks `message` with VoiceOver when this text appears or changes.
    /// For text that shows up away from where the person is (an error under
    /// a form, the undo bar after a delete), which VoiceOver otherwise never
    /// reads unless they happen to swipe onto it.
    func announcedWhenShown(_ message: String) -> some View {
        onAppear { Self.announce(message) }
            .onChange(of: message) { _, new in Self.announce(new) }
    }

    /// A transition that moves, or only fades when Reduce Motion is on: the
    /// change still happens, without the movement (Design.md, Motion).
    func motionTransition(_ moving: AnyTransition) -> some View {
        modifier(MotionTransition(moving: moving))
    }

    private static func announce(_ message: String) {
        guard !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}

private struct MotionTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let moving: AnyTransition

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : moving)
    }
}
