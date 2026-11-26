import AppKit
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

    // AA-checked foreground/background pairs for small text and glyphs on status colours (M12c, WCAG 1.4.3).
    // Ratios computed for light and dark appearance; see notes/m12b-design-system.md.

    /// Solid fill for small "removed" badges with white text (6.5:1). System red with white is only ~3.5:1.
    static var removedFill: Color { Color(red: 0.72, green: 0.11, blue: 0.11) }
    /// Text or glyph on `removedFill`.
    static var onRemoved: Color { .white }
    /// Text or glyph on a solid `look` / `warning` (orange) fill: dark, 8:1 (white on orange is ~2.2:1).
    static var onLook: Color { Color(white: 0.1) }
    /// Orange-family text on a light tint of `look` (e.g. `look.opacity(0.18)`): dark amber in light mode
    /// (5.0:1 on the tinted window background), system orange in dark mode (5.7:1).
    static var lookText: Color { adaptive(light: NSColor(srgbRed: 0.58, green: 0.28, blue: 0, alpha: 1), dark: .systemOrange) }
    /// Green text on a light tint of `kept`: dark green in light mode (5.0:1), system green in dark mode (5.8:1).
    static var keptText: Color { adaptive(light: NSColor(srgbRed: 0, green: 0.42, blue: 0.13, alpha: 1), dark: .systemGreen) }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

// MARK: M12g: scaled display text, stage ink

/// A fixed point size that still follows the user's text size (`ScaledMetric`). For display text only (hero and
/// stage titles, big numbers); decorative symbols keep fixed sizes. `relativeTo` picks the text style whose
/// scaling curve is used.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// `.font(.system(size:))` that scales with text size. Use for text, never for decorative glyphs.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                    relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: style))
    }

    /// The Sorting Stage and Quick Review stay dark in every system appearance (M12g, audit #31): one place
    /// for that decision. Increase Contrast is handled by `StageInk`, the glows and the tile outlines.
    func stageDarkSurface() -> some View {
        environment(\.colorScheme, .dark)
    }
}

private struct DefaultActionKey: ViewModifier {
    let isOn: Bool
    func body(content: Content) -> some View {
        if isOn { content.keyboardShortcut(.defaultAction) } else { content }
    }
}

extension View {
    /// Return triggers this button when `isOn` (M12g, audit #32): one default action per screen.
    func defaultActionKey(if isOn: Bool = true) -> some View { modifier(DefaultActionKey(isOn: isOn)) }
}

/// Text and outline opacities on the dark stage. Secondary text is 0.78 white (was 0.6); with Increase
/// Contrast it goes to 0.92. Contrast ratios still to be measured on a Mac over the brightest glows.
enum StageInk {
    static func secondaryOpacity(_ contrast: ColorSchemeContrast) -> Double { contrast == .increased ? 0.92 : 0.78 }
    static func secondary(_ contrast: ColorSchemeContrast) -> Color { .white.opacity(secondaryOpacity(contrast)) }
    static func outline(_ contrast: ColorSchemeContrast) -> Color { .white.opacity(contrast == .increased ? 0.5 : 0.14) }
    static func glowOpacity(_ contrast: ColorSchemeContrast) -> Double { contrast == .increased ? 0.12 : 0.3 }
}
