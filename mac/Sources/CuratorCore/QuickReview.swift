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

/// A photo the app is not sure about: any reason to look at it.
public func needsALook(_ p: Photo) -> Bool { !reviewReasons(p).isEmpty }

/// One of several near-identical shots of the same moment (the keeper as well as the other frames).
public func isMomentFrame(_ p: Photo) -> Bool { ["exact", "near"].contains(p.duplicate?.category ?? "") }

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
