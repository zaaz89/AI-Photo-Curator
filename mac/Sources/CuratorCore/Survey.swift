import Foundation

// M14c: Survey, the default way to decide a moment (several near-identical frames). All frames side by side, the
// recommended one pre-selected, one or more keepers, Return confirms. Pure state and rules, so the view, the keys
// card and the tests agree. See notes/m14c-survey.md.

// MARK: moments

/// How sure the app is about its recommended frame, from the engine's margin (the best frame's lead over the
/// second, 0...1). The engine calls a moment clear at 0.12 (`CLEAR_MARGIN` in app/duplicates/groups.py).
public enum SurveyConfidence: String, CaseIterable, Sendable {
    case high, medium, low
    public static let clearMargin = 0.12
    /// Below this the two best frames are practically equal: "Close call", faces zoom to 100% by themselves.
    public static let closeCallMargin = 0.05

    /// nil without a margin (a moment built from photos only, or chosen by the owner).
    public init?(margin: Double?) {
        guard let m = margin else { return nil }
        self = m >= Self.clearMargin ? .high : (m >= Self.closeCallMargin ? .medium : .low)
    }

    /// "Confidence: high" and so on.
    public var textKey: String { "surveyConfidence_" + rawValue }
}

/// One moment of a survey: its frames in the moment's order and what the app recommends.
public struct SurveyMoment: Equatable, Identifiable, Sendable {
    /// The engine's duplicate group id.
    public let id: Int
    /// Photo ids, in the moment's order, without repeats.
    public let frames: [Int]
    /// The frame the app recommends (or the owner chose earlier); one of `frames`.
    public let recommended: Int?
    public let margin: Double?
    /// The engine's keeper reasons ("sharpest frame", ...), shown as the "Why" line (`why_` strings).
    public let reasons: [String]
    /// The owner chose the keeper earlier (Undo goes back to that choice, not to the recommendation).
    public let chosenByOwner: Bool

    public init(id: Int, frames: [Int], recommended: Int?, margin: Double? = nil, reasons: [String] = [],
                chosenByOwner: Bool = false) {
        var seen = Set<Int>()
        let unique = frames.filter { seen.insert($0).inserted }
        self.id = id
        self.frames = unique
        self.recommended = recommended.flatMap { unique.contains($0) ? $0 : nil } ?? unique.first
        self.margin = chosenByOwner ? nil : margin
        self.reasons = reasons.filter { !$0.hasPrefix("a recommendation") && $0 != "chosen by you" }
        self.chosenByOwner = chosenByOwner
    }

    /// From the engine's moment list (`GET …/duplicates`).
    public init(_ g: MomentGroup) {
        self.init(id: g.id, frames: g.members.map(\.id), recommended: g.keeperId, margin: g.reasons.margin,
                  reasons: g.reasons.keeper ?? [], chosenByOwner: g.chosenByOwner)
    }

    /// From the album's photos (C in the single review): no margin, so no confidence is shown.
    public static func from(photos: [Photo], group: Int) -> SurveyMoment? {
        let frames = photos.filter { $0.duplicate?.group == group && !$0.isVideo }
        guard frames.count > 1 else { return nil }
        return SurveyMoment(id: group, frames: frames.map(\.id), recommended: frames.first { $0.duplicate?.keeper == true }?.id)
    }

    public var confidence: SurveyConfidence? { SurveyConfidence(margin: margin) }
    public var isCloseCall: Bool { confidence == .low }

    /// Impact order (M14c): close calls first, then moments with more frames, then the lower margin, then time.
    /// The hardest, biggest decisions come while attention is fresh; easy ones at the end can be accepted with A.
    public static func byImpact(_ moments: [SurveyMoment]) -> [SurveyMoment] {
        moments.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if x.isCloseCall != y.isCloseCall { return x.isCloseCall }
            if x.frames.count != y.frames.count { return x.frames.count > y.frames.count }
            let mx = x.margin ?? 0, my = y.margin ?? 0
            if mx != my { return mx < my }
            return a.offset < b.offset
        }.map(\.element)
    }
}

// MARK: decisions and the session

/// What Return (or A) decided for one moment. Keepers stay in the album, the rest go to Left out.
/// The engine keeps one keeper per moment (`POST …/duplicates/<id>/keeper`): `primary` becomes that keeper, the
/// other keepers get the "keep" mark ("keep too"), so all of them are exported. See notes/m14c-survey.md.
public struct SurveyDecision: Equatable, Sendable {
    public let moment: Int
    /// In the moment's order.
    public let keepers: [Int]
    public let leftOut: [Int]
    /// A pressed: the recommendation as it was.
    public let accepted: Bool
    /// The engine's keeper: the recommended frame when it is kept, else the first keeper (nil: nothing kept).
    public let primary: Int?
    public var extras: [Int] { keepers.filter { $0 != primary } }

    public init(moment: SurveyMoment, keepers: [Int], accepted: Bool) {
        let kept = Set(keepers)
        let ordered = moment.frames.filter { kept.contains($0) }
        self.moment = moment.id
        self.keepers = ordered
        self.leftOut = moment.frames.filter { !kept.contains($0) }
        self.accepted = accepted
        self.primary = moment.recommended.flatMap { kept.contains($0) ? $0 : nil } ?? ordered.first
    }
}

/// One step of the survey's history, with what Back needs to restore exactly.
public struct SurveyEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case decided(SurveyDecision), skipped }
    /// The moment's place in the survey.
    public let index: Int
    public let kind: Kind
    /// Every frame's marks before the decision (`LibraryModel.marksOf`).
    public let previous: [Int: [String: MarkValue]]
    /// The owner's earlier keeper (nil: the engine's recommendation).
    public let previousKeeper: Int?
    public var decision: SurveyDecision? {
        switch kind {
        case .decided(let d): return d
        case .skipped: return nil
        }
    }
}

/// The survey's position, the keepers being chosen for the current moment, the focused frame, the face Tab is
/// on, and the history for Back. Pure state: the app writes the marks.
public struct SurveySession: Equatable, Sendable {
    public private(set) var moments: [SurveyMoment]
    public private(set) var index = 0
    /// The focused frame (index into the current moment's frames): ←/→, K, X, F act on it.
    public private(set) var focus = 0
    /// The current moment's keepers, in the moment's order.
    public private(set) var keepers: [Int] = []
    /// The person Tab is on (index into the face columns), for the zoom centre.
    public private(set) var face = 0
    public private(set) var history: [SurveyEntry] = []

    /// `ordered`: sort by impact (`SurveyMoment.byImpact`); false keeps the given order.
    public init(moments: [SurveyMoment], ordered: Bool = true) {
        self.moments = (ordered ? SurveyMoment.byImpact(moments) : moments).filter { $0.frames.count > 1 }
        load(0, keepers: nil)
    }

    public var current: SurveyMoment? { moments.indices.contains(index) ? moments[index] : nil }
    public var finished: Bool { index >= moments.count }
    public var canGoBack: Bool { !history.isEmpty }
    public var focusedId: Int? { current.flatMap { $0.frames.indices.contains(focus) ? $0.frames[focus] : nil } }
    /// "Moment 3 of 12": 1-based, never past the count.
    public var position: (number: Int, count: Int) { (min(index + 1, max(moments.count, 1)), moments.count) }
    /// 0...1 for the progress ring: moments done (decided or skipped).
    public var progress: Double { moments.isEmpty ? 1 : Double(min(index, moments.count)) / Double(moments.count) }
    public func isKeeper(_ id: Int) -> Bool { keepers.contains(id) }

    /// Kept and left out over the decisions still standing (a moment decided twice counts once, the latest).
    public var counts: (kept: Int, leftOut: Int, skipped: Int) {
        var latest: [Int: SurveyEntry.Kind] = [:]
        for e in history { latest[e.index] = e.kind }
        var kept = 0, out = 0, skipped = 0
        for k in latest.values {
            switch k {
            case .decided(let d): kept += d.keepers.count; out += d.leftOut.count
            case .skipped: skipped += 1
            }
        }
        return (kept, out, skipped)
    }

    /// Moments skipped and not decided later.
    public var skippedMoments: [SurveyMoment] {
        var latest: [Int: SurveyEntry.Kind] = [:]
        for e in history { latest[e.index] = e.kind }
        return moments.indices.filter { latest[$0] == .skipped }.map { moments[$0] }
    }

    // Selection

    /// Click or 1–9: that frame (1-based number) is the only keeper, and focused. false for a number past the end.
    @discardableResult
    public mutating func pick(_ number: Int) -> Bool {
        guard let m = current, m.frames.indices.contains(number - 1) else { return false }
        keepers = [m.frames[number - 1]]
        focus = number - 1
        return true
    }

    /// ⇧+click or ⇧+1–9: add the frame as another keeper, or take it out again.
    @discardableResult
    public mutating func toggleKeeper(_ number: Int) -> Bool {
        guard let m = current, m.frames.indices.contains(number - 1) else { return false }
        let id = m.frames[number - 1]
        setKeeper(id, !keepers.contains(id))
        focus = number - 1
        return true
    }

    /// K: the focused frame is kept too (the others stay as they are).
    public mutating func keepFocused() { if let id = focusedId { setKeeper(id, true) } }
    /// X: the focused frame goes to Left out (the others stay as they are; it may leave no keeper at all).
    public mutating func leaveOutFocused() { if let id = focusedId { setKeeper(id, false) } }

    /// ←/→: the focus moves, stopping at the ends.
    public mutating func moveFocus(_ delta: Int) {
        guard let m = current, !m.frames.isEmpty else { return }
        focus = max(0, min(m.frames.count - 1, focus + delta))
    }

    /// Tab: the next person of `people` face columns, wrapping.
    public mutating func nextFace(people: Int) { face = people > 0 ? (face + 1) % people : 0 }

    /// The decision Return would make now (nil when the survey is finished).
    public func pending(accepted: Bool = false) -> SurveyDecision? {
        guard let m = current else { return nil }
        return SurveyDecision(moment: m, keepers: accepted ? m.recommended.map { [$0] } ?? [] : keepers, accepted: accepted)
    }

    // Moving on

    /// Return: records the current keepers and moves to the next moment. `previous`: every frame's marks before.
    @discardableResult
    public mutating func confirm(previous: [Int: [String: MarkValue]], previousKeeper: Int?) -> SurveyDecision? {
        record(pending(), previous: previous, previousKeeper: previousKeeper)
    }

    /// A: the recommendation as it is, then the next moment.
    @discardableResult
    public mutating func accept(previous: [Int: [String: MarkValue]], previousKeeper: Int?) -> SurveyDecision? {
        record(pending(accepted: true), previous: previous, previousKeeper: previousKeeper)
    }

    /// S: the next moment without a decision (nothing is written).
    public mutating func skip() {
        guard current != nil else { return }
        history.append(SurveyEntry(index: index, kind: .skipped, previous: [:], previousKeeper: nil))
        load(index + 1, keepers: nil)
    }

    /// ⌫ / ⌘Z: the last step is taken off and its moment shown again with the keepers that were chosen.
    /// Returns it, so the app can restore the frames' marks and the keeper.
    public mutating func back() -> SurveyEntry? {
        guard let last = history.popLast() else { return nil }
        load(last.index, keepers: last.decision?.keepers)
        return last
    }

    // Internals

    private mutating func record(_ d: SurveyDecision?, previous: [Int: [String: MarkValue]], previousKeeper: Int?) -> SurveyDecision? {
        guard let d else { return nil }
        history.append(SurveyEntry(index: index, kind: .decided(d), previous: previous, previousKeeper: previousKeeper))
        load(index + 1, keepers: nil)
        return d
    }

    private mutating func setKeeper(_ id: Int, _ on: Bool) {
        guard let m = current else { return }
        var set = Set(keepers)
        if on { set.insert(id) } else { set.remove(id) }
        keepers = m.frames.filter { set.contains($0) }
    }

    /// Shows moment `i`: the given keepers (Back) or the recommendation, focus on the first keeper.
    private mutating func load(_ i: Int, keepers given: [Int]?) {
        index = min(max(0, i), moments.count)
        face = 0
        guard let m = current else { keepers = []; focus = 0; return }
        keepers = given ?? m.recommended.map { [$0] } ?? []
        focus = keepers.first.flatMap { m.frames.firstIndex(of: $0) } ?? 0
    }
}

// MARK: reason chips

/// A short reason under a frame, built from what the engine already measured. "Smiling" and "Horizon" are not
/// in the photo data the app receives (M14c), so they are not offered.
public enum SurveyChip: String, CaseIterable, Sendable {
    case eyesClosed, motionBlur, blurry, lookingAway, sharpFace, eyesOpen, sharp

    public var positive: Bool { [.sharpFace, .eyesOpen, .sharp].contains(self) }
    public var textKey: String { "surveyChip_" + rawValue }
    public var symbol: String {
        switch self {
        case .eyesClosed: "eye.slash"
        case .motionBlur: "figure.walk.motion"
        case .blurry: "camera.aperture"
        case .lookingAway: "arrow.turn.up.right"
        case .sharpFace: "person.crop.circle.badge.checkmark"
        case .eyesOpen: "eye"
        case .sharp: "scope"
        }
    }
}

/// One to three chips for a frame, problems first: Eyes closed, Motion blur, Blurry, Looking away, then Sharp face,
/// Eyes open (or Sharp for a photo without faces). Empty when the engine knows nothing about the photo.
public func surveyChips(_ p: Photo, limit: Int = 3) -> [SurveyChip] {
    let reasons = Set(p.quality?.reasons ?? [])
    let main = mainFaces(p.faces?.boxes ?? [])
    let movement = reasons.contains("movement_blur")
    let blurry = !movement && (reasons.contains("whole_blurry") || reasons.contains("subject_blurry")
        || p.focus?.tier == "blurry" || p.quality?.blur == "blurry")
    let closed = main.contains { eyeState($0) == "closed" } || reasons.contains("eyes_closed")
        || (main.isEmpty && (p.faces?.eyesClosed ?? 0) > 0)
    let away = main.contains { $0.lookingAway == true }
    let sharp = !movement && !blurry && (p.focus?.tier == "sharp" || p.quality?.blur == "sharp")
    var out: [SurveyChip] = []
    if closed { out.append(.eyesClosed) }
    if movement { out.append(.motionBlur) }
    if blurry { out.append(.blurry) }
    if away { out.append(.lookingAway) }
    if !main.isEmpty {
        if sharp { out.append(.sharpFace) }
        if !closed && main.allSatisfy({ eyeState($0) == "open" }) { out.append(.eyesOpen) }
    } else if sharp {
        out.append(.sharp)
    }
    return Array(out.prefix(max(0, limit)))
}

// MARK: face columns

/// The faces of a moment lined up per person: column `person` holds that person's face in every frame (nil where
/// the face was not found), in the same order under every frame. Built from the engine's face boxes by position
/// (`matchFaces`); the reference frame is the recommended one unless it shows no main face.
public struct SurveyFaces: Equatable, Sendable {
    /// [person][frame]
    public let columns: [[Photo.Faces.Box?]]
    public let reference: Int

    public init(frames: [[Photo.Faces.Box]], preferred: Int, limit: Int = 3) {
        reference = faceReference(frames, preferred: preferred)
        columns = matchFaces(frames, reference: reference, limit: limit)
    }

    public var people: Int { columns.count }

    /// The faces under one frame, one per person (nil: not found in this frame).
    public func strip(frame: Int) -> [Photo.Faces.Box?] {
        columns.map { $0.indices.contains(frame) ? $0[frame] : nil }
    }

    /// Where the zoom centres for Tab's person: that face in the focused frame, else in the reference frame,
    /// else the largest main face of the focused frame, else the photo's centre.
    public func zoomTarget(person: Int, frame: Int, fallback: [Photo.Faces.Box]? = nil) -> ZoomPoint {
        if columns.indices.contains(person) {
            let col = columns[person]
            if let b = (col.indices.contains(frame) ? col[frame] : nil) ?? (col.indices.contains(reference) ? col[reference] : nil) {
                return ZoomMath.clampUnit(ZoomPoint(x: b.x + b.w / 2, y: b.y + b.h / 2))
            }
        }
        return ZoomMath.target(faces: fallback)
    }
}

/// The frame the face columns are built from: `preferred` (the recommended frame) unless it shows no main face;
/// then the frame with the most main faces (the first of equals).
public func faceReference(_ frames: [[Photo.Faces.Box]], preferred: Int) -> Int {
    guard !frames.isEmpty else { return 0 }
    let p = frames.indices.contains(preferred) ? preferred : 0
    if !mainFaces(frames[p]).isEmpty { return p }
    var best = p, most = 0
    for (i, f) in frames.enumerated() {
        let n = mainFaces(f).count
        if n > most { most = n; best = i }
    }
    return best
}

// MARK: layout

/// How the frames of a moment sit on screen. Up to `surveyMaxSideBySide` frames: one row, equal height, as large as
/// the space allows. More: a filmstrip that scrolls sideways, the focused frame larger than the others.
public struct SurveyLayout: Equatable, Sendable {
    /// Photo height of a frame that is not focused.
    public let height: Double
    /// Photo height of the focused frame (equal to `height` side by side).
    public let focusedHeight: Double
    public let filmstrip: Bool
}

public let surveyMaxSideBySide = 6

/// `ratios`: width / height per frame; `below`: points under each photo (chips, faces).
public func surveyLayout(ratios: [Double], width: Double, height: Double, below: Double, spacing: Double = 12,
                         minHeight: Double = 120) -> SurveyLayout {
    let rs = ratios.map { max(0.2, $0) }
    let room = max(0, height - below)
    guard !rs.isEmpty, width > 0 else { return SurveyLayout(height: 0, focusedHeight: 0, filmstrip: false) }
    if rs.count <= surveyMaxSideBySide {
        let byWidth = (width - spacing * Double(rs.count - 1)) / rs.reduce(0, +)
        let h = max(0, min(room, byWidth))
        if h >= minHeight || rs.count <= 2 { return SurveyLayout(height: h, focusedHeight: h, filmstrip: false) }
    }
    // Filmstrip: the focused frame takes at most 55% of the width; the others are 60% of its height.
    let widest = rs.max() ?? 1.5
    let focused = max(0, min(room, width * 0.55 / widest))
    return SurveyLayout(height: max(min(minHeight, focused), focused * 0.6), focusedHeight: focused, filmstrip: true)
}

// MARK: first-time coach

public enum SurveyCoach {
    /// UserDefaults key: the coach overlay was shown once.
    public static let seenKey = "surveyCoachSeen.v1"
    public static func shouldShow(seen: Bool) -> Bool { !seen }
}

/// What opens a Survey: the moments, and whether it was opened on its own (closing it closes the review too)
/// or as the first part of the question review (the single review of the other photos follows).
public struct SurveyRequest: Equatable, Sendable {
    public let moments: [SurveyMoment]
    public let standalone: Bool
    /// Sort by impact (question review); false keeps the given order (the Moments page, from the chosen moment on).
    public let ordered: Bool
    public init(moments: [SurveyMoment], standalone: Bool, ordered: Bool = true) {
        self.moments = moments; self.standalone = standalone; self.ordered = ordered
    }
}
