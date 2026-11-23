import Foundation

// MARK: M10 quick review: → keeps, ← leaves out, back undoes, one photo at a time

/// Which photos the quick review goes through. The default, `decisions`, is only where the owner has to
/// decide: every frame of a moment with several near-identical shots, and photos the app has doubts about.
/// Everything else simply stays in the album (owner's request 2026-11-16).
public enum ReviewFilter: String, CaseIterable, Identifiable, Sendable {
    case decisions, all, leftOut
    public var id: String { rawValue }
}

public enum ReviewAction: String, Sendable { case keep, leaveOut, skip }

/// One decision, with what the photo's marks were before it, so Back can restore them exactly.
public struct ReviewEntry: Equatable, Sendable {
    public let photoId: Int
    public let action: ReviewAction
    public let previous: [String: MarkValue]
    public init(photoId: Int, action: ReviewAction, previous: [String: MarkValue]) {
        self.photoId = photoId; self.action = action; self.previous = previous
    }
}

/// The quick review's position and history. Pure state: the app writes the marks.
public struct ReviewSession: Equatable, Sendable {
    public private(set) var queue: [Int]
    public private(set) var index: Int
    public private(set) var history: [ReviewEntry] = []

    public init(queue: [Int], startAt: Int? = nil) {
        self.queue = queue
        index = startAt.flatMap { queue.firstIndex(of: $0) } ?? 0
    }

    public var current: Int? { queue.indices.contains(index) ? queue[index] : nil }
    public var finished: Bool { index >= queue.count }
    public var canGoBack: Bool { !history.isEmpty }
    /// The photos around the current one (for preloading).
    public func upcoming(_ n: Int) -> [Int] { Array(queue.dropFirst(index + 1).prefix(n)) }

    /// Records a decision on the current photo and moves on.
    public mutating func record(_ action: ReviewAction, previous: [String: MarkValue]) {
        guard let id = current else { return }
        history.append(ReviewEntry(photoId: id, action: action, previous: previous))
        index += 1
    }

    /// Back: the last decision is taken off and its photo is shown again. Returns it, so the app can
    /// restore the photo's previous marks (nothing to restore for a skip).
    public mutating func back() -> ReviewEntry? {
        guard let last = history.popLast() else { return nil }
        index = queue.firstIndex(of: last.photoId) ?? max(0, index - 1)
        return last
    }

    /// Shows another photo of the queue (e.g. another frame of the same moment) without recording a decision.
    public mutating func jump(to id: Int) {
        if let i = queue.firstIndex(of: id) { index = i }
    }

    /// Kept / left out / skipped, counting each photo's latest decision only.
    public var counts: (kept: Int, leftOut: Int, skipped: Int) {
        var latest: [Int: ReviewAction] = [:]
        for e in history { latest[e.photoId] = e.action }
        return (latest.values.filter { $0 == .keep }.count, latest.values.filter { $0 == .leaveOut }.count,
                latest.values.filter { $0 == .skip }.count)
    }

    /// Photos that were skipped and not decided later: "Review skipped" starts a session with these.
    public var skippedIds: [Int] {
        var latest: [Int: ReviewAction] = [:]
        for e in history { latest[e.photoId] = e.action }
        return queue.filter { latest[$0] == .skip }
    }
}

/// Why the app suggests what it suggests for a photo, as stable codes (translated in the app).
/// Uses the engine's M10 quality codes when present, otherwise what the older analysis knows.
public func reviewReasons(_ p: Photo) -> [String] {
    var out: [String] = []
    if let r = p.quality?.reasons, !r.isEmpty {
        out = r
    } else {
        if p.focus?.tier == "blurry" { out.append("whole_blurry") }
        if let f = p.faces, f.eyesClosed > 0 { out.append("eyes_closed") }
        if p.isExtraFrame { out.append("extra_frame") }
    }
    if p.quality?.utility == true && !out.contains("utility_image") { out.append("utility_image") }
    var seen = Set<String>()
    return out.filter { seen.insert($0).inserted }
}

/// A photo with a real problem to decide on. "Eyes: can't tell" (sunglasses, profile, looking down) is shown
/// as information but is no reason on its own to ask the owner.
/// "Another frame of the same moment" is no reason on its own either: frames of a moment are asked about as
/// moments (byte-identical copies not at all).
/// Screenshots are not asked about: they leave the album by themselves (owner, 2026-11-19) and can be put back.
public func needsALook(_ p: Photo) -> Bool {
    !p.screenshot && reviewReasons(p).contains { $0 != "eyes_unsure" && $0 != "extra_frame" }
}

/// One of several near-identical shots of the same moment (the keeper as well as the other frames).
/// Byte-identical copies (AirDrop, the same file twice) are not asked about: one copy is enough.
public func isMomentFrame(_ p: Photo) -> Bool { p.duplicate?.category == "near" }

/// A photo that needs the owner's yes or no.
public func needsDecision(_ p: Photo) -> Bool { isMomentFrame(p) || needsALook(p) }

/// The photos of a review, in the album's time order (videos included: they can be kept or left out too).
public func reviewQueue(_ photos: [Photo], filter: ReviewFilter) -> [Int] {
    switch filter {
    case .all: return photos.map(\.id)
    case .decisions: return photos.filter(needsDecision).map(\.id)
    case .leftOut: return photos.filter { !$0.goesToAlbumDespiteFocus }.map(\.id)
    }
}

// MARK: faces side by side across the frames of a moment

/// The photo's main faces, largest first: faces the engine marks as main (or all, before M10 data), at least a
/// quarter of the largest face's area, so people far in the background do not take a row.
public func mainFaces(_ boxes: [Photo.Faces.Box], limit: Int = 3) -> [Photo.Faces.Box] {
    let marked = boxes.filter { $0.main != false }
    let pool = (marked.isEmpty ? boxes : marked).sorted { $0.w * $0.h > $1.w * $1.h }
    guard let largest = pool.first else { return [] }
    return Array(pool.filter { $0.w * $0.h >= largest.w * largest.h * 0.25 }.prefix(limit))
}

/// One row per person of the reference frame, one column per frame: the same person's face in every frame of
/// the moment, matched by position (people barely move between near-identical shots). nil when a frame has
/// no face near that position (turned away, hidden, out of the frame).
public func matchFaces(_ frames: [[Photo.Faces.Box]], reference: Int, limit: Int = 3,
                       maxDistance: Double = 0.15) -> [[Photo.Faces.Box?]] {
    guard frames.indices.contains(reference) else { return [] }
    let refs = mainFaces(frames[reference], limit: limit)
    func centre(_ b: Photo.Faces.Box) -> (Double, Double) { (b.x + b.w / 2, b.y + b.h / 2) }
    var rows = refs.map { _ in [Photo.Faces.Box?](repeating: nil, count: frames.count) }
    for (f, boxes) in frames.enumerated() {
        var used = Set<Int>()
        for (r, ref) in refs.enumerated() {
            if f == reference { rows[r][f] = ref; continue }
            let (rx, ry) = centre(ref)
            let best = boxes.enumerated().filter { !used.contains($0.offset) }.map { i, b -> (Int, Double) in
                let (cx, cy) = centre(b)
                return (i, ((cx - rx) * (cx - rx) + (cy - ry) * (cy - ry)).squareRoot())
            }.min { $0.1 < $1.1 }
            if let (i, d) = best, d <= maxDistance { rows[r][f] = boxes[i]; used.insert(i) }
        }
    }
    return rows
}

/// What a face shows, for the comparison: "open", "closed", "unsure" (M10 state), else from the older flags.
public func eyeState(_ b: Photo.Faces.Box) -> String {
    if let s = b.state { return s }
    if b.eyesClosed == true { return "closed" }
    return "open"
}
