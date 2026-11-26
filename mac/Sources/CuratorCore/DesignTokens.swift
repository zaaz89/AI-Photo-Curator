import Foundation

// Design tokens as plain numbers (M12b). No SwiftUI here: the app's `DesignSystem/` turns these values into
// CGFloat, Font, Color and Animation, and the tests below check the scales and the motion specs.

/// Spacing scale in points, taken from the paddings and stack spacings the app already uses most.
public enum SpaceScale {
    public static let xxs: Double = 2
    public static let xs: Double = 4
    public static let s: Double = 6
    public static let m: Double = 8
    public static let l: Double = 12
    public static let xl: Double = 16
    public static let xxl: Double = 20
    public static let xxxl: Double = 24
    public static let huge: Double = 32
    public static let giant: Double = 40

    /// Smallest to largest.
    public static let all: [Double] = [xxs, xs, s, m, l, xl, xxl, xxxl, huge, giant]
}

/// Corner radii in points.
public enum RadiusScale {
    /// Badges, small chips.
    public static let small: Double = 8
    /// Thumbnails, buttons inside cards.
    public static let medium: Double = 12
    /// Photo tiles, inner panels.
    public static let large: Double = 16
    /// Cards (the default of `.card()`).
    public static let card: Double = 22
    /// Hero cards on the album home.
    public static let hero: Double = 26

    public static let all: [Double] = [small, medium, large, card, hero]
}

/// How a motion moves, independent of SwiftUI.
public enum MotionCurve: Equatable, Sendable {
    case spring(response: Double, dampingFraction: Double)
    case snappy(duration: Double)
    case easeInOut(duration: Double)
    case easeOut(duration: Double)

    public var isSpring: Bool {
        switch self {
        case .spring, .snappy: true
        case .easeInOut, .easeOut: false
        }
    }
}

/// The app's named motions. Every animation in the app uses one of these (see `notes/m12b-design-system.md`).
public enum MotionToken: String, CaseIterable, Sendable {
    /// Something appears: photos fly in, a panel or row comes in.
    case arrive
    /// Things come to rest: overview, page and layout changes, progress.
    case settle
    /// Something falls away: a photo drops into "Removed".
    case drop
    /// Frames slide onto each other: near-identical frames stack behind the best one.
    case stack
    /// Hover, press, selection and small value changes.
    case quick
    /// Opacity only: images fading in, a message or flash leaving, a reset.
    case fade
    /// The one-off scan sweep across a photo.
    case sweep
    /// Slow background drift (repeats forever; off with Reduce Motion).
    case ambient

    public var curve: MotionCurve {
        switch self {
        case .arrive: .spring(response: 0.45, dampingFraction: 0.82)
        case .settle: .spring(response: 0.6, dampingFraction: 0.9)
        case .drop: .spring(response: 0.55, dampingFraction: 0.72)
        case .stack: .spring(response: 0.5, dampingFraction: 0.85)
        case .quick: .snappy(duration: 0.2)
        case .fade: .easeInOut(duration: 0.2)
        case .sweep: .easeInOut(duration: 0.55)
        case .ambient: .easeInOut(duration: 9)
        }
    }

    /// The motion with Reduce Motion on: a short cross-fade, never a spring; nil means no animation at all.
    public var reduced: MotionCurve? {
        switch self {
        case .ambient, .sweep: nil
        default: MotionToken.reducedCrossFade
        }
    }

    public static let reducedCrossFade: MotionCurve = .easeInOut(duration: 0.15)

    /// The curve to use for the current Reduce Motion setting.
    public func curve(reduceMotion: Bool) -> MotionCurve? { reduceMotion ? reduced : curve }
}
