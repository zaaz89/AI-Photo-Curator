import SwiftUI
import CuratorCore

// Design tokens (M12b). New screens use these instead of raw numbers and colours; the values live in
// CuratorCore (`DesignTokens.swift`) so they are unit-tested. See notes/m12b-design-system.md.

/// Spacing in points: paddings and stack spacings.
enum Space {
    static let xxs = CGFloat(SpaceScale.xxs)    // 2
    static let xs = CGFloat(SpaceScale.xs)      // 4
    static let s = CGFloat(SpaceScale.s)        // 6
    static let m = CGFloat(SpaceScale.m)        // 8
    static let l = CGFloat(SpaceScale.l)        // 12
    static let xl = CGFloat(SpaceScale.xl)      // 16
    static let xxl = CGFloat(SpaceScale.xxl)    // 20
    static let xxxl = CGFloat(SpaceScale.xxxl)  // 24
    static let huge = CGFloat(SpaceScale.huge)  // 32
    static let giant = CGFloat(SpaceScale.giant) // 40
}

/// Corner radii in points.
enum Radius {
    static let small = CGFloat(RadiusScale.small)   // 8: badges, chips
    static let medium = CGFloat(RadiusScale.medium) // 12: thumbnails, inner buttons
    static let large = CGFloat(RadiusScale.large)   // 16: photo tiles, inner panels
    static let card = CGFloat(RadiusScale.card)     // 22: cards
    static let hero = CGFloat(RadiusScale.hero)     // 26: hero cards on the album home
}

/// Text roles. Semantic styles so Dynamic Type and the system look keep working; fixed sizes only for
/// big numbers and hero symbols.
enum TypeRole {
    static var pageTitle: Font { .largeTitle.bold() }
    static var sectionTitle: Font { .title2.weight(.semibold) }
    static var cardTitle: Font { .headline }
    static var body: Font { .body }
    static var supporting: Font { .callout }
    static var label: Font { .subheadline }
    static var caption: Font { .caption }
    /// Big numeric counters (sorting stage trays, funnel numbers).
    static var counter: Font { .system(size: 34, weight: .bold, design: .rounded).monospacedDigit() }
    /// Large symbol on hero and empty-state cards.
    static var heroSymbol: Font { .system(size: 44) }
}

/// Status colours. System colours, so light and dark appearance both work.
enum StatusColor {
    /// In the album / kept.
    static var kept: Color { .green }
    /// Removed (blurry, left out).
    /// System red, not the softer (1, .42, .42): white text on the softer one is only ~2.8:1.
    static var removed: Color { .red }
    /// "Have a look": the app is not sure and asks the owner.
    static var look: Color { .orange }
    /// Near-identical frames stacked behind the best one.
    static var stacked: Color { .cyan }
    /// Warnings and pending work (clocks to fix, errors that are not fatal).
    static var warning: Color { .orange }
    /// The app's accent.
    static var accent: Color { .accentColor }
}
