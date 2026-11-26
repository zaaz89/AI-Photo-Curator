import Foundation

// MARK: M9 album summary

/// The funnel as segments of one bar, largest meaning first. Zero parts are dropped.
public struct FunnelPart: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case inAlbum, extraFrames, blurry, screenshots, leftOut }
    public let kind: Kind
    public let count: Int
    public var id: String { kind.rawValue }
}

public func funnelParts(_ f: Overview.Funnel) -> [FunnelPart] {
    [FunnelPart(kind: .inAlbum, count: f.inAlbum), FunnelPart(kind: .extraFrames, count: f.extraFrames),
     FunnelPart(kind: .blurry, count: f.blurry), FunnelPart(kind: .screenshots, count: f.screenshots),
     FunnelPart(kind: .leftOut, count: f.leftOut)].filter { $0.count > 0 }
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
