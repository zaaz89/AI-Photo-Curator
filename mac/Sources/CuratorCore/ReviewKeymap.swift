import Foundation

// M12d (UX audit #18, #9), M14c: the one keymap of the review family (single review and Survey), and what
// VoiceOver says. Pure, so the views, the keys card, the shortcut bar, the coach and the tests agree. The grid has
// its own key family (see notes/m12b-design-system.md); K and X mean the same in all of them.

/// A key the review understands, independent of SwiftUI's key types.
public enum ReviewKey: Hashable, Sendable {
    case left, right, up, down, space, delete, escape, returnKey, tab
    /// A printable character, as typed (case does not matter).
    case character(String)
    /// A number-row or keypad digit 1–9 by its physical key (M14c), so ⇧1 works on every keyboard layout.
    case digit(Int)
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

/// Where the key was pressed: one photo at a time, or all frames of a moment side by side (Survey, M14c).
public enum ReviewContext: String, CaseIterable, Sendable { case single, survey }

/// What a key does. `pick` and `addKeeper` carry their frame number in `KeyAction`.
public enum ReviewCommand: String, CaseIterable, Sendable {
    case keep, leaveOut, back, skip, favourite, zoom, faces, survey, keys, close
    // M14c Survey
    case pick, addKeeper, confirm, accept, focusNext, focusPrevious, nextFace, zoomHold
}

/// A key's meaning with its argument: a command, or a frame number for 1–9 / ⇧1–9.
public enum KeyAction: Equatable, Sendable {
    case command(ReviewCommand)
    /// 1–9: that frame is the only keeper.
    case pick(Int)
    /// ⇧1–9: that frame is added as a keeper, or taken out again.
    case toggleKeeper(Int)
}

public enum ReviewKeymap {
    /// The command for a key, or nil: the key is not the review's and must pass through (so VoiceOver, menus
    /// and ⌘Z keep working). Any key held with ⌘, ⌥ or ⌃ is never the review's; ⇧ is allowed (for "?").
    /// Digits are not commands: use `action(for:modifiers:in:)`.
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
                case "k": return .keep
                case "x": return .leaveOut
                case "f": return .favourite
                case "z": return .zoom
                case "e": return .faces
                case "c": return .survey
                case "?", "/": return .keys
                default: return nil
                }
            default: return nil
            }
        case .survey:
            switch key {
            case .returnKey: return .confirm
            case .right: return .focusNext
            case .left: return .focusPrevious
            case .tab: return .nextFace
            case .delete: return .back
            case .space: return .zoomHold
            case .escape: return .close
            case .character(let c):
                switch c.lowercased() {
                case "a": return .accept
                case "k": return .keep
                case "x": return .leaveOut
                case "f": return .favourite
                case "s": return .skip
                case "z": return .zoom
                case "?", "/": return .keys
                default: return nil
                }
            default: return nil
            }
        }
    }

    /// ⇧ + number row on a US keyboard, for when only the typed character is known.
    static let shiftedDigits: [String: Int] = ["!": 1, "@": 2, "#": 3, "$": 4, "%": 5, "^": 6, "&": 7, "*": 8, "(": 9]

    /// A key's action. In Survey 1–9 pick a frame and ⇧1–9 add or remove one; everything else is `command(for:)`.
    public static func action(for key: ReviewKey, modifiers: ReviewKeyModifiers = [], in context: ReviewContext) -> KeyAction? {
        if !modifiers.intersection([.command, .option, .control]).isEmpty { return nil }
        if context == .survey {
            var number: Int?
            var shifted = modifiers.contains(.shift)
            switch key {
            case .digit(let n): number = n
            case .character(let c):
                if let n = Int(c), (1...9).contains(n) { number = n }
                else if let n = shiftedDigits[c] { number = n; shifted = true }
            default: break
            }
            if let n = number {
                guard (1...9).contains(n) else { return nil }
                return shifted ? .toggleKeeper(n) : .pick(n)
            }
        }
        if case .digit = key { return nil }
        return command(for: key, modifiers: modifiers, in: context).map(KeyAction.command)
    }

    /// The digit of a number-row or keypad key code (macOS virtual key codes; physical keys, any layout).
    public static func digit(forKeyCode code: UInt16) -> Int? {
        let table: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
                                    83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]
        return table[code]
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
            return [Entry(keys: "→  K", command: .keep, textKey: "keyKeep"),
                    Entry(keys: "←  X", command: .leaveOut, textKey: "keyLeaveOut"),
                    Entry(keys: "⌫  ⌘Z", command: .back, textKey: "keyBack"),
                    Entry(keys: "␣", command: .skip, textKey: "keySkip"),
                    Entry(keys: "F", command: .favourite, textKey: "keyFavourite"),
                    Entry(keys: "Z", command: .zoom, textKey: "keyZoom"),
                    Entry(keys: "E", command: .faces, textKey: "keyFaces"),
                    Entry(keys: "C", command: .survey, textKey: "keySurvey"),
                    Entry(keys: "?", command: .keys, textKey: "keyKeys"),
                    Entry(keys: "esc", command: .close, textKey: "keyClose")]
        case .survey:
            return [Entry(keys: "1 – 9", command: .pick, textKey: "keyPick"),
                    Entry(keys: "⇧1 – 9", command: .addKeeper, textKey: "keyAddKeeper"),
                    Entry(keys: "↩", command: .confirm, textKey: "keyConfirm"),
                    Entry(keys: "A", command: .accept, textKey: "keyAccept"),
                    Entry(keys: "← →", command: .focusNext, textKey: "keyFocus"),
                    Entry(keys: "K", command: .keep, textKey: "keyKeepFocused"),
                    Entry(keys: "X", command: .leaveOut, textKey: "keyLeaveOutFocused"),
                    Entry(keys: "Z", command: .zoom, textKey: "keyZoomSurvey"),
                    Entry(keys: "␣ (hold)", command: .zoomHold, textKey: "keyZoomHold"),
                    Entry(keys: "⇥", command: .nextFace, textKey: "keyNextFace"),
                    Entry(keys: "⌫  ⌘Z", command: .back, textKey: "keyBackMoment"),
                    Entry(keys: "F", command: .favourite, textKey: "keyFavourite"),
                    Entry(keys: "S", command: .skip, textKey: "keySkipMoment"),
                    Entry(keys: "?", command: .keys, textKey: "keyKeys"),
                    Entry(keys: "esc", command: .close, textKey: "keyCloseSurvey")]
        }
    }

    /// The always-visible shortcut bar at the bottom: the keys that matter, with short words.
    public static func bar(_ context: ReviewContext) -> [Entry] {
        switch context {
        case .single:
            return [Entry(keys: "→ K", command: .keep, textKey: "barKeep"),
                    Entry(keys: "← X", command: .leaveOut, textKey: "barLeaveOut"),
                    Entry(keys: "␣", command: .skip, textKey: "barSkip"),
                    Entry(keys: "Z", command: .zoom, textKey: "barZoom"),
                    Entry(keys: "⌫", command: .back, textKey: "barBack"),
                    Entry(keys: "?", command: .keys, textKey: "barKeys")]
        case .survey:
            return [Entry(keys: "1–9", command: .pick, textKey: "barPick"),
                    Entry(keys: "⇧1–9", command: .addKeeper, textKey: "barAdd"),
                    Entry(keys: "↩", command: .confirm, textKey: "barConfirm"),
                    Entry(keys: "A", command: .accept, textKey: "barAccept"),
                    Entry(keys: "← →", command: .focusNext, textKey: "barFocus"),
                    Entry(keys: "Z", command: .zoom, textKey: "barZoom"),
                    Entry(keys: "⌫", command: .back, textKey: "barBack"),
                    Entry(keys: "?", command: .keys, textKey: "barKeys")]
        }
    }

    /// The first-time coach (shown once): the four keys that matter in Survey.
    public static let coach: [Entry] = [Entry(keys: "1 – 9", command: .pick, textKey: "coachPick"),
                                        Entry(keys: "↩", command: .confirm, textKey: "coachConfirm"),
                                        Entry(keys: "Z", command: .zoom, textKey: "coachZoom"),
                                        Entry(keys: "← →", command: .focusNext, textKey: "coachFocus")]
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
