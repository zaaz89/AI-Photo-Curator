import Foundation

/// Which photos a library view shows.
public enum LibraryFilter: Hashable, Sendable {
    case all                 // everything kept (left-out photos hidden)
    case everything          // kept and left out
    case favourites
    case leftOut
    case videos
    case blurry              // out of focus, kept or left out, so the owner can decide
    case day(String)
    case ids([Int])          // search results, in the given order

    func includes(_ p: Photo) -> Bool {
        switch self {
        case .all: return !p.rejected
        case .everything, .ids: return true
        case .favourites: return p.favorite
        case .leftOut: return p.rejected
        case .videos: return p.isVideo && !p.rejected
        case .blurry: return p.focus?.tier == "blurry"          // the owner's own mark wins
        case .day(let d): return p.day == d && !p.rejected
        }
    }
}

public enum PhotoSort: String, CaseIterable, Hashable, Sendable { case time, person, place, quality }

/// A titled group of photos in the grid (an event of a day, a person, a place…).
public struct PhotoSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String          // for time order the day ("2026-10-23"); the view formats it
    public let day: String
    public let eventName: String?
    public let eventId: Int?
    public var photos: [Photo]
}

/// Groups photos for the grid. Time order: one section per event in time order, undated last.
public func sections(_ photos: [Photo], events: [TripEvent], filter: LibraryFilter, sort: PhotoSort) -> [PhotoSection] {
    var list = photos.filter(filter.includes)
    if case .ids(let ids) = filter {
        let byId = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        list = ids.compactMap { byId[$0] }
        return list.isEmpty ? [] : [PhotoSection(id: "results", title: "", day: "", eventName: nil, eventId: nil, photos: list)]
    }
    switch sort {
    case .time:
        let names = Dictionary(events.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var out: [PhotoSection] = []
        for p in list.filter({ $0.day != Photo.undated }) + list.filter({ $0.day == Photo.undated }) {
            if let last = out.last, last.day == p.day, last.eventId == p.eventId {
                out[out.count - 1].photos.append(p)
            } else {
                out.append(PhotoSection(id: "\(p.day)#\(p.eventId.map(String.init) ?? "-")#\(out.count)", title: p.day, day: p.day,
                                        eventName: p.eventId.flatMap { names[$0] }, eventId: p.eventId, photos: [p]))
            }
        }
        return out
    case .person:
        return grouped(list) { $0.owner }
    case .place:
        return grouped(list) { $0.place?.label ?? "" }
    case .quality:
        let order = ["sharp": 0, "soft": 1, "blurry": 2]
        return grouped(list.sorted { (order[$0.focus?.tier ?? ""] ?? 3) < (order[$1.focus?.tier ?? ""] ?? 3) }) { $0.focus?.tier ?? "" }
    }
}

private func grouped(_ list: [Photo], key: (Photo) -> String) -> [PhotoSection] {
    var order: [String] = [], groups: [String: [Photo]] = [:]
    for p in list {
        let k = key(p)
        if groups[k] == nil { order.append(k) }
        groups[k, default: []].append(p)
    }
    // Empty key ("no place", "no focus data") goes last.
    order = order.filter { !$0.isEmpty } + order.filter(\.isEmpty)
    return order.map { PhotoSection(id: "g:\($0)", title: $0, day: "", eventName: nil, eventId: nil, photos: groups[$0]!) }
}

public enum Direction: Sendable { case left, right, up, down }

/// Moves the keyboard cursor over a grid of sections laid out in `columns` columns.
/// Up and down keep the column; at the end of a section they continue in the next one.
public func moveCursor(_ index: Int, _ dir: Direction, columns: Int, sectionSizes: [Int]) -> Int {
    let total = sectionSizes.reduce(0, +)
    guard total > 0 else { return -1 }
    guard index >= 0 else { return 0 }
    let cols = max(1, columns)
    var start = 0, s = 0
    while s < sectionSizes.count && index >= start + sectionSizes[s] { start += sectionSizes[s]; s += 1 }
    guard s < sectionSizes.count else { return total - 1 }
    let size = sectionSizes[s], p = index - start, row = p / cols, col = p % cols, lastRow = (size - 1) / cols
    switch dir {
    case .left: return max(0, index - 1)
    case .right: return min(total - 1, index + 1)
    case .down:
        if p + cols < size { return index + cols }
        if row < lastRow { return start + size - 1 }
        guard s + 1 < sectionSizes.count else { return index }
        return start + size + min(col, sectionSizes[s + 1] - 1)
    case .up:
        if p - cols >= 0 { return index - cols }
        guard s > 0 else { return index }
        let prevSize = sectionSizes[s - 1], prevStart = start - prevSize
        let lastRowStart = (prevSize - 1) / cols * cols
        return prevStart + lastRowStart + min(col, prevSize - 1 - lastRowStart)
    }
}

/// The ids between two grid positions, both ends included.
public func rangeSelect(from: Int, to: Int, in ids: [Int]) -> Set<Int> {
    guard !ids.isEmpty else { return [] }
    let a = max(0, min(from, to)), b = min(ids.count - 1, max(from, to))
    guard a <= b else { return [] }
    return Set(ids[a...b])
}
