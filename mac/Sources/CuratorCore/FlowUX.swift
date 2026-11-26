import Foundation

// M12e (UX audit P1, flow): human error texts, the engine start failure, the menu order of the flow, the grid's
// keys, the grid badge for photos the app left out by itself, and the Finish Album wording. Pure functions, so
// the views and the tests agree. See notes/m12b-ux-audit.md rows 8, 15, 18, 21, 22.

// MARK: errors (#8)

/// What went wrong, in the owner's terms. Each kind has an `err_<kind>` string.
public enum ErrorKind: String, CaseIterable, Sendable {
    /// The background service does not answer.
    case unreachable
    /// Another job (analysis, export) runs for this album.
    case busy
    /// A folder is inside, or contains, a folder already in the album.
    case folderOverlap
    /// The path is not a folder (moved, renamed, a file).
    case notAFolder
    /// The album, photo or chapter is gone (another window, Finish Album).
    case notFound
    /// macOS refused access to a folder.
    case permission
    /// The export destination is full.
    case diskFull
    /// A value the service did not accept (a setting, a name).
    case invalid
    /// The service failed inside (HTTP 5xx).
    case server
    /// Anything else.
    case unknown
}

/// An error as the owner sees it: a human sentence (localised) and the raw text for "Details".
public struct HumanError: Equatable, Sendable {
    public let kind: ErrorKind
    public let message: String
    public let details: String
    public init(kind: ErrorKind, message: String, details: String) {
        self.kind = kind; self.message = message; self.details = details
    }
}

/// The kind of an engine error text (`{"error": "..."}` or `job.error`). The engine writes short English
/// sentences for developers, so they are matched by their stable words.
public func errorKind(engineText: String) -> ErrorKind {
    let t = engineText.lowercased()
    func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
    if has("still running", "still being worked on") { return .busy }
    if has("overlaps", "cannot contain or be inside") { return .folderOverlap }
    if has("not a folder") { return .notAFolder }
    if has("not enough free space", "no space left", "disk full") { return .diskFull }
    if has("permission", "not permitted", "read-only", "access denied") { return .permission }
    if has("not found", "unknown event", "unknown photo", "unknown clock", "unknown duplicate", "no such file") { return .notFound }
    if has("required", "must be", "invalid", "unknown setting") { return .invalid }
    if has("could not connect", "connection refused", "timed out") { return .unreachable }
    return .unknown
}

/// The kind of an HTTP status without an engine message.
public func errorKind(httpStatus: Int) -> ErrorKind {
    switch httpStatus {
    case 404, 410: .notFound
    case 409, 423, 429: .busy
    case 400, 405, 415, 422: .invalid
    case 401, 403: .permission
    case 503: .unreachable
    case 500...599: .server
    default: .unknown
    }
}

/// The human text for any error the app gets (API errors, URL errors, anything else).
public func humanError(_ error: Error, _ lang: Lang) -> HumanError {
    let kind: ErrorKind
    let details: String
    switch error {
    case APIError.engine(let e): kind = errorKind(engineText: e); details = e
    case APIError.http(let c): kind = errorKind(httpStatus: c); details = "HTTP \(c)"
    case APIError.unreachable(let e): kind = .unreachable; details = e
    case let e as URLError: kind = .unreachable; details = e.localizedDescription
    default: kind = .unknown; details = error.localizedDescription
    }
    return HumanError(kind: kind, message: errorMessage(kind, lang), details: details)
}

/// The human text for an engine error string (e.g. `job.error`); "Error: " is dropped from the details.
public func humanError(engineText: String, _ lang: Lang) -> HumanError {
    var raw = engineText.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.hasPrefix("Error: ") { raw = String(raw.dropFirst(7)) }
    let kind = errorKind(engineText: raw)
    return HumanError(kind: kind, message: errorMessage(kind, lang), details: raw)
}

/// The sentence for a kind: what happened and what to do.
public func errorMessage(_ kind: ErrorKind, _ lang: Lang) -> String {
    switch kind {
    case .unreachable: Strings.text("err_unreachable", lang)
    case .busy: Strings.text("err_busy", lang)
    case .folderOverlap: Strings.text("err_folderOverlap", lang)
    case .notAFolder: Strings.text("err_notAFolder", lang)
    case .notFound: Strings.text("err_notFound", lang)
    case .permission: Strings.text("err_permission", lang)
    case .diskFull: Strings.text("err_diskFull", lang)
    case .invalid: Strings.text("err_invalid", lang)
    case .server: Strings.text("err_server", lang)
    case .unknown: Strings.text("err_unknown", lang)
    }
}

/// Why the background service did not start (the app's own launcher, not the engine).
public enum EngineStartFailure: Error, Equatable, Sendable {
    /// The app does not know the project folder (moved after the build).
    case projectMissing
    /// Neither `.venv` nor `uv` was found.
    case pythonMissing
    /// The process could not be launched (the system's reason).
    case launch(String)
    /// It was launched but did not answer in time (or quit).
    case timeout

    /// Title, sentence and raw details for the start screen.
    public func human(_ lang: Lang) -> HumanError {
        switch self {
        case .projectMissing:
            HumanError(kind: .unknown, message: Strings.text("engineProjectMissing", lang),
                       details: "PCProjectPath / PC_PROJECT_PATH: photo_curator.py not found. scripts/build-mac-app.sh")
        case .pythonMissing:
            HumanError(kind: .unknown, message: Strings.text("enginePythonMissing", lang), details: "uv sync")
        case .launch(let why):
            HumanError(kind: .unknown, message: Strings.text("engineLaunchFailed", lang), details: why)
        case .timeout:
            HumanError(kind: .unreachable, message: Strings.text("engineTimeout", lang), details: "local-data/logs/server.log")
        }
    }
}

// MARK: menu order (#15)

/// The pages of the flow in the order the owner goes through them, with their menu shortcut digit (⌘0 …).
/// Decoupled from `GuideStep.number`: the three steps keep "Step 1 of 3", the menu follows the whole flow.
public enum FlowPage: String, CaseIterable, Sendable {
    case home, people, sorting, selection, story, export, settings

    /// ⌘ + this digit opens the page (nil: no shortcut; Settings has ⌘, already).
    public var menuDigit: Int? {
        switch self {
        case .home: 0
        case .people: 1
        case .sorting: 2
        case .selection: 3
        case .story: 4
        case .export: 5
        case .settings: nil
        }
    }

    /// The guide step behind this page, if it is one.
    public var guideStep: GuideStep? {
        switch self {
        case .selection: .selection
        case .story: .story
        case .export: .export
        default: nil
        }
    }
}

/// Menu digits of the library pages after the flow (All Photos, Left Out).
public let allPhotosMenuDigit = 6
public let leftOutMenuDigit = 7

// MARK: grid keys (#18)

/// What a plain key does in the photo grid. One family with the quick review (`ReviewKeymap`): the review's
/// → / ← are K / X here, because the grid's arrows move the cursor. Space is Quick Look in the grid,
/// Esc closes Quick Look or clears the selection, ⌘Z undoes.
public enum GridKeyAction: String, Sendable {
    case keep, leaveOut, favourite, wallpaper
}

/// The action for a typed character in the grid (no modifiers or Shift), or nil.
public func gridKeyAction(_ characters: String) -> GridKeyAction? {
    switch characters.lowercased() {
    case "k": .keep
    case "x": .leaveOut
    case "f": .favourite
    case "b": .wallpaper
    default: nil
    }
}

// MARK: grid badge for photos the app left out by itself (#21)

/// A badge on a grid tile for a photo the app left out (or flags) by itself, with the reason in words.
public struct AutoBadge: Equatable, Sendable {
    public enum Kind: String, Sendable { case screenshot, document, blurry }
    public let kind: Kind
    /// Short badge text ("Screenshot").
    public let label: String
    /// The reason, for the tooltip and VoiceOver.
    public let reason: String
    public init(kind: Kind, label: String, reason: String) { self.kind = kind; self.label = label; self.reason = reason }
}

/// The badge for a photo the app judged by itself; nil when the owner decided (left out, kept, favourite).
public func autoBadge(_ p: Photo, _ lang: Lang) -> AutoBadge? {
    if p.rejected || p.keep || p.favorite || p.isVideo { return nil }
    if p.screenshot {
        return AutoBadge(kind: .screenshot, label: Strings.text("badge_screenshot", lang), reason: Strings.text("badgeWhy_screenshot", lang))
    }
    if p.focus?.tier == "blurry" {
        let why = sortReasonText(p, lang) ?? Strings.text("tier_blurry", lang)
        return AutoBadge(kind: .blurry, label: Strings.text("tier_blurry", lang),
                         reason: why + " · " + Strings.text("badgeWhy_blurry", lang))
    }
    if p.quality?.utility == true {
        return AutoBadge(kind: .document, label: Strings.text("badge_document", lang), reason: Strings.text("badgeWhy_document", lang))
    }
    return nil
}

// MARK: Finish Album (#22)

/// The confirmation's title: what is removed, the unexported warning first when it applies.
public func finishAlbumTitle(_ name: String, exported: Bool, _ lang: Lang) -> String {
    let title = String(format: Strings.text("finishTitle", lang), name)
    return exported ? title : Strings.text("finishNotExportedShort", lang) + " " + title
}

/// The confirmation's text: the unexported consequence first, then what stays untouched.
public func finishAlbumText(exported: Bool, _ lang: Lang) -> String {
    exported ? Strings.text("finishText", lang) : Strings.text("finishNotExported", lang) + "\n\n" + Strings.text("finishText", lang)
}
