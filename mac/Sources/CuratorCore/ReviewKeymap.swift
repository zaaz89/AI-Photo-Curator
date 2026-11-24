import Foundation

// M12d (UX audit #18, #9): the one keymap of the quick review and its compare mode, and what VoiceOver says.
// Pure, so the views, the keys card and the tests agree. The grid has its own key family (see the note).

/// A key the review understands, independent of SwiftUI's key types.
public enum ReviewKey: Hashable, Sendable {
    case left, right, up, down, space, delete, escape, returnKey
    /// A printable character, as typed (case does not matter).
    case character(String)
}

/// The modifier keys held with a key.
public struct ReviewKeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = ReviewKeyModifiers(rawValue: 1)
    public static let command = ReviewKeyModifiers(rawValue: 2)
    public static let option = ReviewKeyModifiers(rawValue: 4)
    public static let control = ReviewKeyModifiers(rawValue: 8)
}

/// Where the key was pressed: one photo at a time, or two frames of a moment side by side.
public enum ReviewContext: String, CaseIterable, Sendable { case single, compare }

/// What a key does.
public enum ReviewCommand: String, CaseIterable, Sendable {
    case keep, leaveOut, back, skip, favourite, zoom, faces, compare, keys, close
    case pickFirst, pickSecond, nextChallenger, previousChallenger
}

public enum ReviewKeymap {
    /// The command for a key, or nil: the key is not the review's and must pass through (so VoiceOver, menus
    /// and ⌘Z keep working). Any key held with ⌘, ⌥ or ⌃ is never the review's; ⇧ is allowed (for "?").
    public static func command(for key: ReviewKey, modifiers: ReviewKeyModifiers = [], in context: ReviewContext) -> ReviewCommand? {
        if !modifiers.intersection([.command, .option, .control]).isEmpty { return nil }
        switch context {
        case .single:
            switch key {
            case .right: return .keep
            case .left: return .leaveOut
            case .delete: return .back
            case .space: return .skip
            case .escape: return .close
            case .character(let c):
                switch c.lowercased() {
                case "f": return .favourite
                case "z": return .zoom
                case "e": return .faces
                case "c": return .compare
                case "?", "/": return .keys
                default: return nil
                }
            default: return nil
            }
        case .compare:
            switch key {
            case .right: return .nextChallenger
            case .left: return .previousChallenger
            case .escape: return .close
            case .character(let c):
                switch c.lowercased() {
                case "1": return .pickFirst
                case "2": return .pickSecond
                case "z": return .zoom
                case "c": return .close
                case "?", "/": return .keys
                default: return nil
                }
            default: return nil
            }
        }
    }

    /// One row of the keys card: the keys as shown, and the string key of what they do.
    public struct Entry: Equatable, Sendable {
        public let keys: String
        public let command: ReviewCommand
        public let textKey: String
        public init(keys: String, command: ReviewCommand, textKey: String) {
            self.keys = keys; self.command = command; self.textKey = textKey
        }
    }

    /// The keys card of a context. ⌘Z is listed with Back: it is the menu's Undo, which the review maps to Back.
    public static func entries(_ context: ReviewContext) -> [Entry] {
        switch context {
        case .single:
            return [Entry(keys: "→", command: .keep, textKey: "keyKeep"),
                    Entry(keys: "←", command: .leaveOut, textKey: "keyLeaveOut"),
                    Entry(keys: "⌫  ⌘Z", command: .back, textKey: "keyBack"),
                    Entry(keys: "␣", command: .skip, textKey: "keySkip"),
                    Entry(keys: "F", command: .favourite, textKey: "keyFavourite"),
                    Entry(keys: "Z", command: .zoom, textKey: "keyZoom"),
                    Entry(keys: "E", command: .faces, textKey: "keyFaces"),
                    Entry(keys: "C", command: .compare, textKey: "keyCompare"),
                    Entry(keys: "?", command: .keys, textKey: "keyKeys"),
                    Entry(keys: "esc", command: .close, textKey: "keyClose")]
        case .compare:
            return [Entry(keys: "1", command: .pickFirst, textKey: "keyPickFirst"),
                    Entry(keys: "2", command: .pickSecond, textKey: "keyPickSecond"),
                    Entry(keys: "→", command: .nextChallenger, textKey: "keyNextChallenger"),
                    Entry(keys: "←", command: .previousChallenger, textKey: "keyPrevChallenger"),
                    Entry(keys: "Z", command: .zoom, textKey: "keyZoom"),
                    Entry(keys: "?", command: .keys, textKey: "keyKeys"),
                    Entry(keys: "esc  C", command: .close, textKey: "keyCloseCompare")]
        }
    }
}

// MARK: VoiceOver texts

/// What VoiceOver says after a decision: "Kept, 12 of 80". `position` is 1-based.
public func reviewAnnouncement(_ action: ReviewAction, position: Int, total: Int, _ lang: Lang) -> String {
    let key = switch action {
    case .keep: "a11yKeptN"
    case .leaveOut: "a11yLeftOutN"
    case .skip: "a11ySkippedN"
    }
    return String(format: Strings.text(key, lang), position, total)
}

/// The main photo's accessibility value: zoom state, and the decision while its flash shows.
public func reviewAccessibilityValue(zoomed: Bool, flash: ReviewAction?, _ lang: Lang) -> String {
    var parts = [Strings.text(zoomed ? "a11yZoomActual" : "a11yZoomFit", lang)]
    if let flash {
        parts.append(Strings.text(flash == .keep ? "a11yFlashKept" : (flash == .leaveOut ? "a11yFlashLeftOut" : "a11yFlashSkipped"), lang))
    }
    return parts.joined(separator: ", ")
}
