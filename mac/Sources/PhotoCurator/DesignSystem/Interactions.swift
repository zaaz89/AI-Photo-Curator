import SwiftUI
import CuratorCore

// M12f micro-interactions: one hover lift and one pressable card style for every card in the app, symbol effects
// that follow Reduce Motion, and the haptic mapping. See notes/m12b-design-system.md, "Motion choreography".

// MARK: hover lift

extension View {
    /// Lifts a card a little under the pointer: subtle scale and a deeper shadow, `quick` motion. Under Reduce
    /// Motion only the shadow changes (no scale). Never blocks clicks: it only reads hover.
    func hoverLift(_ enabled: Bool = true, radius: CGFloat = Radius.card) -> some View {
        modifier(HoverLift(enabled: enabled, radius: radius))
    }
}

private struct HoverLift: ViewModifier {
    let enabled: Bool
    let radius: CGFloat
    @State private var over = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let lifted = enabled && over
        content
            .shadow(color: .black.opacity(lifted ? 0.14 : 0), radius: lifted ? 16 : 0, y: lifted ? 8 : 0)
            .scaleEffect(lifted && !reduceMotion ? 1.015 : 1)
            .animation(Motion.animation(.quick, reduceMotion: reduceMotion), value: lifted)
            .onHover { inside in if enabled { over = inside } else if over { over = false } }
    }
}

// MARK: pressable card

/// A plain button style for whole cards: hover lift plus a short press-in (0.98) on mouse down, `quick` motion.
/// Under Reduce Motion the press dims slightly instead of scaling.
struct PressableCardStyle: ButtonStyle {
    var radius: CGFloat = Radius.card
    func makeBody(configuration: Configuration) -> some View {
        PressableCardBody(configuration: configuration, radius: radius)
    }
}

private struct PressableCardBody: View {
    let configuration: ButtonStyleConfiguration
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .contentShape(.rect(cornerRadius: radius))
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .opacity(pressed && reduceMotion ? 0.85 : 1)
            .animation(Motion.animation(.quick, reduceMotion: reduceMotion), value: pressed)
            .hoverLift(isEnabled, radius: radius)
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    /// Whole-card buttons (album home, day, guide and tray cards).
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
}

// MARK: symbol effects

extension View {
    /// Bounces an SF Symbol once when it appears and every time `trigger` changes (keep, left out, stacked,
    /// export done, error). Nothing moves under Reduce Motion.
    func symbolBounce<T: Equatable>(on trigger: T) -> some View {
        modifier(SymbolBounce(trigger: trigger))
    }
}

private struct SymbolBounce<T: Equatable>: ViewModifier {
    let trigger: T
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .symbolEffect(.bounce, options: .nonRepeating, value: ticks)
            .onAppear { if !reduceMotion { ticks += 1 } }
            .onChange(of: trigger) { _, _ in if !reduceMotion { ticks += 1 } }
    }
}

// MARK: haptics

extension DecisionFeedback {
    /// Keep and compare pick snap into place (alignment); leaving out is a step down (level change).
    var sensory: SensoryFeedback {
        switch self {
        case .keep, .pick: .alignment
        case .leaveOut: .levelChange
        }
    }
}
