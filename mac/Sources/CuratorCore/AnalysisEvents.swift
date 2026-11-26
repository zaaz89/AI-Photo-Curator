import Foundation

// M13: the engine's live event stream (GET /api/collections/<id>/events?since=N). The analysis runs day by day;
// every photo gets an event when it is read and whenever its place changes, and every day a `settled_day` once its
// moments exist. The Sorting stage follows this instead of guessing from reloads. Pure, so it is unit-tested.

/// What happened to a photo (or a day). Unknown kinds from a newer engine decode as `.unknown` and are ignored.
public enum AnalysisEventKind: String, Sendable, Equatable {
    case read, scored, removed, stacked
    case settledDay = "settled_day"
    case unknown
}

public struct AnalysisEvent: Decodable, Sendable, Equatable {
    public let seq: Int
    public let assetId: Int?
    public let kind: AnalysisEventKind
    public let reason: String?
    public let keeperId: Int?
    public let day: String

    public init(seq: Int, assetId: Int?, kind: AnalysisEventKind, reason: String? = nil, keeperId: Int? = nil,
                day: String) {
        self.seq = seq
        self.assetId = assetId
        self.kind = kind
        self.reason = reason
        self.keeperId = keeperId
        self.day = day
    }

    enum CodingKeys: String, CodingKey {
        case seq, kind, reason, day
        case assetId = "asset_id"
        case keeperId = "keeper_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decode(Int.self, forKey: .seq)
        assetId = try c.decodeIfPresent(Int.self, forKey: .assetId)
        let raw = try c.decode(String.self, forKey: .kind)
        kind = AnalysisEventKind(rawValue: raw) ?? .unknown
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        keeperId = try c.decodeIfPresent(Int.self, forKey: .keeperId)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? Photo.undated
    }
}

/// One page of the stream. `next` is the cursor for the next request; `more`: another page is ready now;
/// `latest`: the newest event the engine has (lower than our cursor: the album was analysed from scratch).
public struct AnalysisEventPage: Decodable, Sendable, Equatable {
    public let events: [AnalysisEvent]
    public let next: Int
    public let more: Bool
    public let latest: Int

    public init(events: [AnalysisEvent], next: Int, more: Bool, latest: Int) {
        self.events = events
        self.next = next
        self.more = more
        self.latest = latest
    }
}

/// Where the stream says a photo is.
public enum LivePlace: Equatable, Sendable {
    case read
    case album
    case removed(reason: String?)
    case stacked(keeper: Int?)

    /// The analysis has judged the photo (not only read it).
    public var judged: Bool { self != .read }
}

/// What one merge changed, so the page can react without diffing everything.
public struct SortStreamChange: Equatable, Sendable {
    public var arrived: [Int] = []
    public var judged: [Int] = []
    public var settledDays: [String] = []
    public init(arrived: [Int] = [], judged: [Int] = [], settledDays: [String] = []) {
        self.arrived = arrived
        self.judged = judged
        self.settledDays = settledDays
    }
    public var isEmpty: Bool { arrived.isEmpty && judged.isEmpty && settledDays.isEmpty }
}

/// The stage's view of the stream: every photo's newest place, the settled days, and the cursor.
public struct SortStream: Equatable, Sendable {
    public private(set) var cursor = 0
    public private(set) var places: [Int: LivePlace] = [:]
    public private(set) var dayOf: [Int: String] = [:]
    public private(set) var settledDays: Set<String> = []
    /// Grows with every change (cheap for `onChange`).
    public private(set) var revision = 0

    public init() {}

    public var settledCount: Int { settledDays.count }

    /// Merges events in order. Events at or below the cursor were merged before and change nothing, so a page
    /// fetched twice is harmless. A `read` never overwrites a place the photo already has.
    @discardableResult
    public mutating func merge(_ events: [AnalysisEvent]) -> SortStreamChange {
        var change = SortStreamChange()
        for e in events.sorted(by: { $0.seq < $1.seq }) where e.seq > cursor {
            cursor = e.seq
            switch e.kind {
            case .settledDay:
                if settledDays.insert(e.day).inserted { change.settledDays.append(e.day) }
            case .read:
                guard let id = e.assetId else { continue }
                dayOf[id] = e.day
                if places[id] == nil { places[id] = .read; change.arrived.append(id) }
            case .scored, .removed, .stacked:
                guard let id = e.assetId else { continue }
                let place: LivePlace = switch e.kind {
                case .scored: .album
                case .removed: .removed(reason: e.reason)
                default: .stacked(keeper: e.keeperId)
                }
                if places[id] == nil { change.arrived.append(id) }
                if places[id] != place { places[id] = place; change.judged.append(id) }
                if dayOf[id] != e.day {
                    // A clock change moved the photo to another day: that day is not settled for it until it says so.
                    dayOf[id] = e.day
                }
            case .unknown:
                continue
            }
        }
        if !change.isEmpty { revision += 1 }
        return change
    }

    /// Merges a page; a page whose `latest` is below our cursor means the stream started again (new database):
    /// everything is forgotten first.
    @discardableResult
    public mutating func merge(page: AnalysisEventPage) -> SortStreamChange {
        if page.latest < cursor { reset() }
        return merge(page.events)
    }

    public mutating func reset() {
        let r = revision
        self = SortStream()
        revision = r + 1
    }

    /// The photo's day is settled: its final place (moments included) is known.
    public func isSettled(_ id: Int) -> Bool {
        guard let d = dayOf[id] else { return false }
        return settledDays.contains(d)
    }

    public func isJudged(_ id: Int) -> Bool { places[id]?.judged ?? false }

    /// The stage verdict the stream implies (`check` needs the photo's details, so it shows as album here).
    public func verdict(_ id: Int) -> SortVerdict? {
        switch places[id] {
        case .album?: return .album
        case .removed?: return .removed
        case .stacked?: return .stacked
        default: return nil
        }
    }
}

/// How long to wait before asking for events again: soon while the analysis runs (at once when the last page
/// was full), never when nothing runs (`nil`: stop polling).
public func eventPollInterval(running: Bool, morePending: Bool) -> Double? {
    guard running else { return nil }
    return morePending ? 0.05 : 0.7
}

/// The photos (their focus, moments, marks) are fetched again after a merge when a day settled, or when photos
/// were judged and the last reload is at least `minGap` seconds old. Keeps a 3,000-photo album from reloading
/// for every event.
public func shouldReloadPhotos(after change: SortStreamChange, secondsSinceReload: Double, minGap: Double = 2.0) -> Bool {
    if !change.settledDays.isEmpty { return true }
    if !change.arrived.isEmpty && secondsSinceReload >= minGap { return true }
    return !change.judged.isEmpty && secondsSinceReload >= minGap
}

/// "2 of 7 days sorted" while the analysis runs day by day (nil before the first photo is read).
public func stageDaysText(_ stream: SortStream, _ lang: Lang) -> String? {
    let days = Set(stream.dayOf.values).count
    guard days > 0 else { return nil }
    return String(format: Strings.text("stageDaysSorted", lang), min(stream.settledCount, days), days)
}
