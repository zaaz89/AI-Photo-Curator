import AppKit
import SwiftUI
import CuratorCore

// Named motions (M12b). Every animation in the app goes through here, so Reduce Motion is handled in one
// place: with it on, a motion becomes a short cross-fade (never a spring), or nothing for ambient motion.
// Specs live in CuratorCore (`MotionToken`) and are unit-tested. See notes/m12b-design-system.md.

enum Motion {
    /// Something appears: photos fly in, a panel or row comes in.
    static var arrive: Animation { animation(for: MotionToken.arrive.curve) }
    /// Things come to rest: overview, page and layout changes, progress.
    static var settle: Animation { animation(for: MotionToken.settle.curve) }
    /// Something falls away: a photo drops into "Removed".
    static var drop: Animation { animation(for: MotionToken.drop.curve) }
    /// Frames slide onto each other and into "Stacked".
    static var stack: Animation { animation(for: MotionToken.stack.curve) }
    /// Hover, press, selection and small value changes.
    static var quick: Animation { animation(for: MotionToken.quick.curve) }
    /// Opacity only: images fading in, a message or flash leaving.
    static var fade: Animation { animation(for: MotionToken.fade.curve) }
    /// The one-off scan sweep.
    static var sweep: Animation { animation(for: MotionToken.sweep.curve) }
    /// Slow background drift, repeating. Only start it when Reduce Motion is off.
    static var ambient: Animation { animation(for: MotionToken.ambient.curve).repeatForever(autoreverses: true) }

    /// The animation for a motion, respecting Reduce Motion (nil means: change without animation).
    static func animation(_ token: MotionToken, reduceMotion: Bool) -> Animation? {
        guard let curve = token.curve(reduceMotion: reduceMotion) else { return nil }
        let a = animation(for: curve)
        return token == .ambient && !reduceMotion ? a.repeatForever(autoreverses: true) : a
    }

    static func animation(for curve: MotionCurve) -> Animation {
        switch curve {
        case let .spring(response, damping): Animation.spring(response: response, dampingFraction: damping)
        case let .snappy(duration): Animation.snappy(duration: duration)
        case let .easeInOut(duration): Animation.easeInOut(duration: duration)
        case let .easeOut(duration): Animation.easeOut(duration: duration)
        }
    }

    /// The system's Reduce Motion setting, for code that has no SwiftUI environment at hand.
    @MainActor static var systemReduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// `withAnimation` with a named motion. Pass the view's `accessibilityReduceMotion` when you have it;
/// otherwise the system setting is read.
@MainActor @discardableResult
func withMotion<Result>(_ token: MotionToken, reduceMotion: Bool? = nil, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.animation(token, reduceMotion: reduceMotion ?? Motion.systemReduceMotion), body)
}

extension View {
    /// `.animation(_:value:)` with a named motion that follows Reduce Motion from the environment.
    func motionAnimation<V: Equatable>(_ token: MotionToken, value: V) -> some View {
        modifier(MotionAnimation(token: token, value: value))
    }
}

private struct MotionAnimation<V: Equatable>: ViewModifier {
    let token: MotionToken
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.animation(token, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// `.transition(_:)` that follows Reduce Motion (M12e): with it on, a movement (slide, push, scale) becomes a
    /// plain cross-fade, so nothing travels across the screen.
    func motionTransition(_ transition: AnyTransition) -> some View {
        modifier(MotionTransition(transition: transition))
    }
}

private struct MotionTransition: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? AnyTransition.opacity : transition)
    }
}
