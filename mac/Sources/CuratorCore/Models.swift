import Foundation

/// A trip (a "collection" in the engine).
public struct Trip: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let assets: Int
}

/// One photo or video of a trip, as the engine's timeline returns it.
public struct Photo: Decodable, Identifiable, Hashable, Sendable {
    public static let undated = "unknown"

    public struct Place: Decodable, Hashable, Sendable {
        public let label: String
        public let precision: String?
        public let distanceKm: Double?
        public let region: String?
        public let country: String?
        enum CodingKeys: String, CodingKey { case label, precision, region, country, distanceKm = "distance_km" }
    }
    public struct Focus: Decodable, Hashable, Sendable {
        public let tier: String
        public let autoTier: String?
        public let override: String?
        enum CodingKeys: String, CodingKey { case tier, override, autoTier = "auto_tier" }
    }
    public struct Faces: Decodable, Hashable, Sendable {
        public let faces: Int
        public let eyesClosed: Int
        public let lookingAway: Int
        public let score: Double?
        enum CodingKeys: String, CodingKey { case faces, score, eyesClosed = "eyes_closed", lookingAway = "looking_away" }
    }
    public struct Duplicate: Decodable, Hashable, Sendable {
        public let group: Int
        public let category: String
        public let keeper: Bool?
    }
    public struct AI: Decodable, Hashable, Sendable {
        public let description: String?
        public let tags: [String]?
        public let textVisible: String?
        enum CodingKeys: String, CodingKey { case description, tags, textVisible = "text_visible" }
    }

    public let id: Int
    public let filename: String
    public let path: String
    public let kind: String
    public let owner: String
    public let sourceId: Int
    public let device: String?
    public let localTime: String?
    public let correctedLocalTime: String?
    public let utcTime: String?
    public let offsetMinutes: Int?
    public let confidence: String?
    public let eventId: Int?
    public var favorite: Bool
    public var rejected: Bool
    public var wallpaper: Bool
    public let width: Int?
    public let height: Int?
    public let duration: Double?
    public let poster: Bool
    public let place: Place?
    public var focus: Focus?
    public let faces: Faces?
    public let duplicate: Duplicate?
    public let ai: AI?
    public let notes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, filename, path, kind, owner, device, confidence, favorite, rejected, wallpaper, width, height, duration,
             poster, place, focus, faces, duplicate, ai, notes
        case sourceId = "source_id", localTime = "local_time", correctedLocalTime = "corrected_local_time",
             utcTime = "utc_time", offsetMinutes = "offset_minutes", eventId = "event_id"
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        path = try c.decode(String.self, forKey: .path)
        kind = try c.decode(String.self, forKey: .kind)
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? ""
        sourceId = try c.decodeIfPresent(Int.self, forKey: .sourceId) ?? 0
        device = try c.decodeIfPresent(String.self, forKey: .device)
        localTime = try c.decodeIfPresent(String.self, forKey: .localTime)
        correctedLocalTime = try c.decodeIfPresent(String.self, forKey: .correctedLocalTime)
        utcTime = try c.decodeIfPresent(String.self, forKey: .utcTime)
        offsetMinutes = try c.decodeIfPresent(Int.self, forKey: .offsetMinutes)
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence)
        eventId = try c.decodeIfPresent(Int.self, forKey: .eventId)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        rejected = try c.decodeIfPresent(Bool.self, forKey: .rejected) ?? false
        wallpaper = try c.decodeIfPresent(Bool.self, forKey: .wallpaper) ?? false
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        poster = try c.decodeIfPresent(Bool.self, forKey: .poster) ?? false
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        focus = try c.decodeIfPresent(Focus.self, forKey: .focus)
        faces = try c.decodeIfPresent(Faces.self, forKey: .faces)
        duplicate = try c.decodeIfPresent(Duplicate.self, forKey: .duplicate)
        ai = try c.decodeIfPresent(AI.self, forKey: .ai)
        notes = try c.decodeIfPresent([String].self, forKey: .notes)
    }

    /// Local capture time as the app shows it (clock correction applied when there is one).
    public var time: String? {
        if let t = correctedLocalTime ?? localTime { return t }
        guard let u = utcTime else { return nil }
        return u.hasSuffix("Z") ? String(u.dropLast()) : u
    }
    /// "2026-10-23", or `Photo.undated`.
    public var day: String { time.map { String($0.prefix(10)) } ?? Self.undated }
    /// "17:48", or "" when undated.
    public var clock: String {
        guard let t = time, t.count >= 16 else { return "" }
        return String(t.dropFirst(11).prefix(5))
    }
    public var isVideo: Bool { kind == "video" }
    public var fileURL: URL { URL(fileURLWithPath: path) }
}

public struct TripEvent: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let day: String
    public let name: String
    public let count: Int
    public let locked: Bool?
    public let placeLabel: String?
    enum CodingKeys: String, CodingKey { case id, day, name, count, locked, placeLabel = "place_label" }
}

public struct Timeline: Decodable, Sendable {
    public let items: [Photo]
    public let events: [TripEvent]
    public init(items: [Photo], events: [TripEvent]) { self.items = items; self.events = events }
}

public struct SourceInfo: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let owner: String
    public let path: String
    public let assets: Int?
}

public struct EngineSettings: Codable, Hashable, Sendable {
    public var uiLanguage: String
    public var aiGpuShare: Int
    public var aiPauseOnBattery: Bool
    public var keeperWeights: [String: Int]
    public init(uiLanguage: String, aiGpuShare: Int, aiPauseOnBattery: Bool, keeperWeights: [String: Int]) {
        self.uiLanguage = uiLanguage; self.aiGpuShare = aiGpuShare
        self.aiPauseOnBattery = aiPauseOnBattery; self.keeperWeights = keeperWeights
    }
    enum CodingKeys: String, CodingKey {
        case uiLanguage = "ui_language", aiGpuShare = "ai_gpu_share", aiPauseOnBattery = "ai_pause_on_battery",
             keeperWeights = "keeper_weights"
    }
}

public struct SearchResult: Decodable, Sendable {
    public struct Hit: Decodable, Sendable {
        public let id: Int
        public let placeMatch: Bool?
        public let tagMatch: Bool?
        enum CodingKeys: String, CodingKey { case id, placeMatch = "place_match", tagMatch = "tag_match" }
    }
    public let query: String?
    public let english: String?
    public let results: [Hit]
    public let note: String?
}
