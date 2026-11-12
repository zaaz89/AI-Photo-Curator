import Foundation

// MARK: New Album wizard

public struct FolderSuggestion: Decodable, Identifiable, Hashable, Sendable {
    public struct Device: Decodable, Hashable, Sendable { public let name: String; public let count: Int }
    public let path: String
    public let count: Int
    public let more: Bool?                   // the folder has more files than were counted
    public let owner: String
    public let ownerFrom: String?            // remembered | exif | folder | nil
    public let devices: [Device]
    public let start: String?
    public let end: String?
    public var id: String { path }
    enum CodingKeys: String, CodingKey { case path, count, more, owner, devices, start, end, ownerFrom = "owner_from" }
}

public struct Suggestion: Decodable, Sendable {
    public struct Rejected: Decodable, Hashable, Sendable { public let path: String; public let problem: String }
    public struct Album: Decodable, Sendable {
        public let place: String?
        public let region: String?
        public let country: String?
        public let start: String?
        public let end: String?
    }
    public let folders: [FolderSuggestion]
    public let rejected: [Rejected]
    public let album: Album
}

/// Which device → person pairs to remember for the next album: only a device that appears in
/// exactly one folder and makes up at least half of that folder's sample (not a few AirDropped photos,
/// not a phone model two people share).
public func devicesToRemember(_ folders: [(owner: String, devices: [(String, Int)])]) -> [String: String] {
    var seen: [String: Int] = [:]
    for f in folders { for (d, _) in f.devices { seen[d, default: 0] += 1 } }
    var out: [String: String] = [:]
    for f in folders where !f.owner.isEmpty {
        let total = f.devices.reduce(0) { $0 + $1.1 }
        for (d, n) in f.devices where seen[d] == 1 && total > 0 && n * 2 >= total { out[d] = f.owner }
    }
    return out
}

private let monthsEN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
private let monthsSL = ["jan.", "feb.", "mar.", "apr.", "maj", "jun.", "jul.", "avg.", "sep.", "okt.", "nov.", "dec."]

/// "Tuscany, 23–28 Oct 2026" / "Toskana, 23.–28. okt. 2026" from the suggested place and dates.
public func albumName(place: String?, start: String?, end: String?, lang: Lang) -> String {
    func parts(_ d: String?) -> (y: String, m: Int, d: Int)? {
        guard let d, d.count >= 10, let m = Int(d.dropFirst(5).prefix(2)), let day = Int(d.dropFirst(8).prefix(2)), (1...12).contains(m)
        else { return nil }
        return (String(d.prefix(4)), m, day)
    }
    var dates = ""
    if let a = parts(start) {
        let b = parts(end) ?? a
        let mon = lang == .sl ? monthsSL : monthsEN
        func one(_ x: (y: String, m: Int, d: Int), year: Bool) -> String {
            lang == .sl ? "\(x.d). \(mon[x.m - 1])" + (year ? " \(x.y)" : "") : "\(x.d) \(mon[x.m - 1])" + (year ? " \(x.y)" : "")
        }
        if a == b {
            dates = one(a, year: true)
        } else if a.y == b.y && a.m == b.m {
            dates = lang == .sl ? "\(a.d).–\(b.d). \(mon[a.m - 1]) \(a.y)" : "\(a.d)–\(b.d) \(mon[a.m - 1]) \(a.y)"
        } else {
            dates = one(a, year: a.y != b.y) + " – " + one(b, year: true)
        }
    }
    return [place, dates.isEmpty ? nil : dates].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
}

// MARK: Overview

public struct Overview: Decodable, Sendable {
    public struct Facts: Decodable, Sendable {
        public let photos: Int, videos: Int, people: Int, days: Int
        public let places: [String]
        public let start: String?, end: String?
    }
    public struct Clocks: Decodable, Sendable { public let devices: Int, pending: Int, applied: Int }
    public struct Moments: Decodable, Sendable {
        public let total: Int, decided: Int, chosen: Int, needYou: Int
        enum CodingKeys: String, CodingKey { case total, decided, chosen, needYou = "need_you" }
    }
    public struct Blurry: Decodable, Sendable {
        public let total: Int, leftOut: Int, keptFavourites: Int
        enum CodingKeys: String, CodingKey { case total, leftOut = "left_out", keptFavourites = "kept_favourites" }
    }
    public struct Events: Decodable, Sendable { public let events: Int, days: Int }
    public struct Descriptions: Decodable, Sendable {
        public let done: Int, photos: Int, minutesLeft: Int
        enum CodingKeys: String, CodingKey { case done, photos, minutesLeft = "minutes_left" }
    }
    public struct Export: Decodable, Sendable { public let done: Bool, photos: Int }
    public let analysing: Bool
    public let facts: Facts
    public let clocks: Clocks
    public let moments: Moments
    public let blurry: Blurry
    public let events: Events
    public let descriptions: Descriptions
    public let export: Export
}

// MARK: clocks, moments, export

public struct DeviceClock: Decodable, Identifiable, Hashable, Sendable {
    public struct Evidence: Decodable, Hashable, Sendable { public let note: String? }
    public let clockId: Int
    public let owner: String
    public let device: String
    public let photos: Int
    public let suggestedS: Double?
    public let appliedS: Double?
    public let status: String?
    public let evidence: Evidence?
    public var id: Int { clockId }
    enum CodingKeys: String, CodingKey {
        case owner, device, photos, status, evidence
        case clockId = "clock_id", suggestedS = "suggested_s", appliedS = "applied_s"
    }
    /// A suggestion the owner has not answered yet.
    public var pending: Bool { suggestedS != nil && !["accepted", "manual", "rejected", "reference"].contains(status ?? "") }
}

public struct MomentGroup: Decodable, Identifiable, Hashable, Sendable {
    public struct Member: Decodable, Hashable, Sendable {
        public let id: Int
        public let path: String
        public let owner: String?
        public let localTime: String?
        public let width: Int?
        public let height: Int?
        public let rejected: Bool?
        enum CodingKeys: String, CodingKey { case id, path, owner, width, height, rejected, localTime = "local_time" }
    }
    public struct Reasons: Decodable, Hashable, Sendable {
        public let keeper: [String]?
        public let margin: Double?
    }
    public let id: Int
    public let category: String
    public let keeperId: Int?
    public let reasons: Reasons
    public let members: [Member]
    enum CodingKeys: String, CodingKey { case id, category, reasons, members, keeperId = "keeper_id" }
    public var chosenByOwner: Bool { reasons.keeper?.first == "chosen by you" }
    public var clear: Bool { chosenByOwner || (reasons.margin ?? 0) >= 0.12 }
}

public struct ExportPreview: Decodable, Sendable {
    public let files: Int
    public let bytes: Int
    public let warnings: [String: Int]?
    public let writesMetadata: Bool?
    enum CodingKeys: String, CodingKey { case files, bytes, warnings, writesMetadata = "writes_metadata" }
}
