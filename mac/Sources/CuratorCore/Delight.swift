import Foundation

// M12f (motion and delight): the pure logic behind the album home as a story (cover, dates, day cards), the first
// run, the export celebration, haptic feedback and staggered entrances. No SwiftUI here; the views live in
// PhotoCurator (AlbumStory.swift, FirstRun.swift, Celebration.swift). Tested in DelightTests.swift.

// MARK: album cover

/// The album's cover: the engine's cover if it is still in the album, else the first highlight in the album, else
/// the best photo in the album (`coverPhoto`: favourite, sharp, open eyes, the first one when nothing stands out),
/// else the best of everything. Never a video, never a photo the owner left out while album photos exist.
public func albumCover(_ photos: [Photo], coverId: Int?, highlights: [Int] = []) -> Photo? {
    let inAlbum = photos.filter { $0.goesToAlbumDespiteFocus && !$0.isVideo }
    if !inAlbum.isEmpty {
        let byId = Dictionary(inAlbum.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if let id = coverId, let p = byId[id] { return p }
        if let p = highlights.lazy.compactMap({ byId[$0] }).first { return p }
        return coverPhoto(inAlbum)
    }
    return coverPhoto(photos)
}

// MARK: dates

/// The album's first and last day ("yyyy-MM-dd") from the overview's start and end times; `last` is nil when the
/// album is a single day. nil when there is no usable date.
public func albumDaySpan(start: String?, end: String?) -> (first: String, last: String?)? {
    func day(_ s: String?) -> String? {
        guard let s, s.count >= 10 else { return nil }
        let d = String(s.prefix(10))
        return parseLocalTime(d + "T00:00:00") == nil ? nil : d
    }
    guard let first = day(start) ?? day(end) else { return nil }
    let last = day(end).flatMap { $0 == first ? nil : $0 }
    return (first, last)
}

// MARK: day cards

/// One day of the album on the home page: its best photo, how many photos, and the chapter names the engine
/// already gave that day.
public struct DayCard: Identifiable, Equatable, Sendable {
    public let day: String
    public let coverId: Int?
    public let taken: Int
    public let inAlbum: Int
    /// Chapter (event) names of the day, in timeline order, without blanks or repeats.
    public let chapters: [String]
    /// The first place label of the day's chapters, if any.
    public let place: String?
    public var id: String { day }

    public init(day: String, coverId: Int?, taken: Int, inAlbum: Int, chapters: [String], place: String?) {
        self.day = day; self.coverId = coverId; self.taken = taken; self.inAlbum = inAlbum
        self.chapters = chapters; self.place = place
    }
}

/// Days in order (undated last), each with a cover chosen like the album's (a highlight of that day first).
public func dayCards(photos: [Photo], events: [TripEvent], highlights: [Int] = []) -> [DayCard] {
    var order: [String] = []
    var byDay: [String: [Photo]] = [:]
    for p in photos {
        if byDay[p.day] == nil { order.append(p.day) }
        byDay[p.day, default: []].append(p)
    }
    let days = order.sorted { a, b in
        if a == Photo.undated { return false }
        if b == Photo.undated { return true }
        return a < b
    }
    return days.map { day in
        let dayPhotos = byDay[day] ?? []
        let dayEvents = events.filter { $0.day == day }
        var seen = Set<String>()
        let names = dayEvents.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let place = dayEvents.lazy.compactMap { $0.placeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return DayCard(day: day,
                       coverId: albumCover(dayPhotos, coverId: nil, highlights: highlights)?.id,
                       taken: dayPhotos.count,
                       inAlbum: dayPhotos.filter(\.goesToAlbumDespiteFocus).count,
                       chapters: names,
                       place: place)
    }
}

// MARK: first run

/// The three first-run screens: what the app does, the safety promise, start.
public enum FirstRunPage: Int, CaseIterable, Sendable {
    case what, safety, start

    public var next: FirstRunPage? { FirstRunPage(rawValue: rawValue + 1) }
    public var previous: FirstRunPage? { FirstRunPage(rawValue: rawValue - 1) }
    public var isLast: Bool { next == nil }
}

public enum FirstRun {
    /// User default set once the first run was finished or skipped (versioned, so a redesigned first run can show again).
    public static let seenKey = "firstRunSeen.v1"

    /// Shown once: until the owner finished or skipped it.
    public static func shouldShow(seen: Bool) -> Bool { !seen }

    /// The page for a key press: → / Return go on, ← goes back; nil means the key is not the first run's.
    /// Return on the last page is handled by its button (it closes the first run).
    public static func page(after key: String, on page: FirstRunPage) -> FirstRunPage? {
        switch key {
        case "right": page.next
        case "left": page.previous
        default: nil
        }
    }
}

// MARK: export celebration

/// The completion moment plays once per verified export (by destination folder), never for a failed one.
public func shouldCelebrateExport(ok: Bool, folder: String, celebrated: Set<String>) -> Bool {
    ok && !folder.isEmpty && !celebrated.contains(folder)
}

// MARK: haptics

/// What a decision feels like on a Force Touch trackpad (mapped to `SensoryFeedback` in the app).
public enum DecisionFeedback: Sendable, Equatable {
    case keep, leaveOut, pick
}

/// A decision event; `tick` changes on every decision, so the same kind twice still triggers.
public struct DecisionPulse: Equatable, Sendable {
    public let kind: DecisionFeedback
    public let tick: Int
    public init(kind: DecisionFeedback, tick: Int) { self.kind = kind; self.tick = tick }
    public static let none = DecisionPulse(kind: .keep, tick: 0)
    public func next(_ kind: DecisionFeedback) -> DecisionPulse { DecisionPulse(kind: kind, tick: tick + 1) }
}

// MARK: choreography budget

/// The longest any one choreographed entrance may take, delays included (seconds). Input is never blocked.
public let motionBudget = 0.6

/// Delay before the `index`-th of `count` items starts its entrance: a short, even stagger whose total stays
/// within `total` (and within `motionBudget`), so long lists never wait. Items beyond the visible few start together.
public func staggerDelay(_ index: Int, of count: Int, total: Double = 0.24, step: Double = 0.05, cap: Int = 8) -> Double {
    guard index > 0, count > 1 else { return 0 }
    let limit = min(total, motionBudget)
    let i = Double(min(index, cap))
    return min(limit, i * min(step, limit / Double(max(1, min(count, cap + 1) - 1))))
}
