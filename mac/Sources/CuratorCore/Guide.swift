import Foundation

// MARK: M9 album guide: four steps, what is next, the funnel

/// The three steps of the album guide, in order (M9: people and clocks moved out of the steps; they come
/// up on their own only when a camera clock needs a decision).
public enum GuideStep: String, CaseIterable, Identifiable, Hashable, Sendable {
    case selection, story, export
    public var id: String { rawValue }
    public var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
    public var next: GuideStep? { Self.allCases.dropFirst(number).first }
    public var previous: GuideStep? { number > 1 ? Self.allCases[number - 2] : nil }
    public var symbol: String {
        switch self {
        case .selection: "square.stack.3d.up"
        case .story: "book.pages"
        case .export: "square.and.arrow.up"
        }
    }
    /// The engine's checklist steps this guide step covers (marked done together).
    public var workflowSteps: [String] {
        switch self {
        case .selection: ["duplicates", "blurry"]
        case .story: ["events"]
        case .export: ["export"]
        }
    }
}

/// What a step still needs from the owner.
public struct StepState: Equatable, Sendable {
    public var done: Bool
    /// How many decisions wait (0 when done or nothing to count).
    public var waiting: Int
    public init(done: Bool, waiting: Int) { self.done = done; self.waiting = waiting }
}

/// The state of each step from the overview and the owner's checklist. While the analysis runs,
/// nothing counts as done or waiting except what is already true (folders added, export done).
public func stepStates(_ o: Overview?, marked: [String: Bool], analysing: Bool) -> [GuideStep: StepState] {
    var out: [GuideStep: StepState] = [:]
    for s in GuideStep.allCases { out[s] = StepState(done: false, waiting: 0) }
    guard let o else { return out }
    let busy = analysing || o.analysing
    let moments = busy ? 0 : o.moments.needYou
    out[.selection] = StepState(done: !busy && (moments == 0 || marked["duplicates"] == true), waiting: moments)
    // The story is the owner's to judge: done once the owner moved on from it (Next marks "events").
    out[.story] = StepState(done: !busy && marked["events"] == true, waiting: 0)
    out[.export] = StepState(done: o.export.done, waiting: 0)
    return out
}

/// Camera clocks that wait for the owner (a suggested shift nobody answered), shown before the steps.
/// Zero while analysing, and once the owner looked at the clocks and moved on.
public func clocksWaiting(_ o: Overview?, marked: [String: Bool], analysing: Bool) -> Int {
    guard let o, !analysing, !o.analysing, marked["times"] != true else { return 0 }
    return o.clocks.pending
}

/// The one thing to do next: the first step that is not done, in order.
public func nextStep(_ states: [GuideStep: StepState]) -> GuideStep? {
    GuideStep.allCases.first { states[$0]?.done != true }
}

/// The funnel as segments of one bar, largest meaning first. Zero parts are dropped.
public struct FunnelPart: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case inAlbum, extraFrames, blurry, leftOut }
    public let kind: Kind
    public let count: Int
    public var id: String { kind.rawValue }
}

public func funnelParts(_ f: Overview.Funnel) -> [FunnelPart] {
    [FunnelPart(kind: .inAlbum, count: f.inAlbum), FunnelPart(kind: .extraFrames, count: f.extraFrames),
     FunnelPart(kind: .blurry, count: f.blurry), FunnelPart(kind: .leftOut, count: f.leftOut)].filter { $0.count > 0 }
}

// MARK: chapters (events grouped by day)

public struct DayChapters: Identifiable, Sendable {
    public let day: String
    public let chapters: [TripEvent]
    public var id: String { day }
}

/// Events grouped by day, days in order, chapters in their timeline order.
public func chaptersByDay(_ events: [TripEvent]) -> [DayChapters] {
    var order: [String] = []
    var byDay: [String: [TripEvent]] = [:]
    for e in events {
        if byDay[e.day] == nil { order.append(e.day) }
        byDay[e.day, default: []].append(e)
    }
    return order.sorted { a, b in
        // Undated last.
        if a == Photo.undated { return false }
        if b == Photo.undated { return true }
        return a < b
    }.map { DayChapters(day: $0, chapters: byDay[$0] ?? []) }
}

/// The photo that best represents a set: a favourite, then a sharp photo with open eyes, then any.
/// Left-out photos and videos only when nothing else is there.
public func coverPhoto(_ photos: [Photo]) -> Photo? {
    let kept = photos.filter { !$0.rejected && !$0.isVideo }
    func score(_ p: Photo) -> Double {
        var s = 0.0
        if p.favorite { s += 4 }
        if p.duplicate?.keeper == true { s += 1 }
        switch p.focus?.tier { case "sharp": s += 2; case "soft": s += 1; default: break }
        if let f = p.faces { s += (f.score ?? 0.5) + (f.eyesClosed == 0 ? 0.5 : 0) }
        return s
    }
    return kept.max { score($0) < score($1) } ?? photos.first
}

// MARK: clocks as lanes

/// A photo's position on the album's time line, 0…1. `nil` for undated photos.
public func timelinePosition(_ time: String?, start: Date, end: Date) -> Double? {
    guard let time, let d = parseLocalTime(time) else { return nil }
    let span = end.timeIntervalSince(start)
    guard span > 0 else { return 0.5 }
    return min(1, max(0, d.timeIntervalSince(start) / span))
}

/// "2026-10-23T17:48:02" (optionally with fractions or a zone suffix) as a date in UTC.
public func parseLocalTime(_ s: String) -> Date? {
    let core = String(s.prefix(19))
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let d = f.date(from: core) { return d }
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: core)
}

/// A short, signed duration: "+42 s", "−1.5 min", "+2 h 05 min".
public func shiftText(_ seconds: Double) -> String {
    let sign = seconds > 0 ? "+" : (seconds < 0 ? "−" : "")
    let a = abs(seconds)
    if a < 90 { return sign + String(format: "%.0f s", a) }
    if a < 3600 { return sign + String(format: "%.1f min", a / 60) }
    let h = Int(a / 3600), m = Int(a.truncatingRemainder(dividingBy: 3600) / 60)
    return sign + String(format: "%d h %02d min", h, m)
}

/// Initials for a person's badge: "Žaž" → "Ž", "Ana Novak" → "AN".
public func initials(_ name: String) -> String {
    let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
    let s = words.compactMap(\.first).map { String($0).uppercased() }.joined()
    return s.isEmpty ? "?" : s
}
