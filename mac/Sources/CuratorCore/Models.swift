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
        public init(tier: String, autoTier: String?, override: String?) {
            self.tier = tier; self.autoTier = autoTier; self.override = override
        }
        /// The same photo with the owner's focus mark set (nil: back to the automatic tier).
        public func overridden(_ mark: String?) -> Focus {
            Focus(tier: mark ?? autoTier ?? tier, autoTier: autoTier, override: mark)
        }
    }
    public struct Faces: Decodable, Hashable, Sendable {
        /// One face, normalised to the image, origin top-left (M9).
        public struct Box: Decodable, Hashable, Sendable {
            public let x: Double, y: Double, w: Double, h: Double
            public let eyesClosed: Bool?
            public let lookingAway: Bool?
            /// M10: "open" | "closed" | "unsure", and whether this is one of the photo's main faces.
            public let state: String?
            public let main: Bool?
            enum CodingKeys: String, CodingKey { case x, y, w, h, state, main, eyesClosed = "eyes_closed", lookingAway = "looking_away" }
        }
        public let faces: Int
        public let eyesClosed: Int
        public let lookingAway: Int
        public let score: Double?
        public let boxes: [Box]?
        enum CodingKeys: String, CodingKey { case faces, score, boxes, eyesClosed = "eyes_closed", lookingAway = "looking_away" }
    }
    public struct Duplicate: Decodable, Hashable, Sendable {
        public let group: Int
        public let category: String
        public let keeper: Bool?
    }
    /// M10 quality check: blur judged on the subject (bokeh is not a fault), Apple's aesthetics score,
    /// utility images (screenshots, receipts, documents) and stable reason codes.
    public struct Quality: Decodable, Hashable, Sendable {
        public let blur: String?
        public let blurReason: String?
        public let aesthetic: Double?
        public let utility: Bool?
        public let reasons: [String]?
        enum CodingKeys: String, CodingKey { case blur, aesthetic, utility, reasons, blurReason = "blur_reason" }
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
    /// Kept as well as the moment's best frame ("keep too", M10), without being a favourite.
    public var keep: Bool
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
    public let quality: Quality?
    public let notes: [String]?

    enum CodingKeys: String, CodingKey {
        case id, filename, path, kind, owner, device, confidence, favorite, keep, rejected, wallpaper, width, height, duration,
             poster, place, focus, faces, duplicate, ai, quality, notes
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
        keep = try c.decodeIfPresent(Bool.self, forKey: .keep) ?? false
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
        quality = try c.decodeIfPresent(Quality.self, forKey: .quality)
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
    /// The app found it blurry (whatever the owner decided since).
    public var foundBlurry: Bool { focus?.autoTier == "blurry" || focus?.tier == "blurry" }
    /// Another frame of a moment whose best frame was chosen (the export skips it unless it is a favourite).
    public var isExtraFrame: Bool {
        guard let d = duplicate, ["exact", "near"].contains(d.category) else { return false }
        return d.keeper == false
    }
    /// The Google Photos export takes it (same rule as the engine's export plan): not left out, and, unless it
    /// is a favourite, neither blurry (by the owner's focus mark when there is one) nor an extra frame.
    public var goesToAlbumDespiteFocus: Bool {
        !rejected && (favorite || ((focus?.tier != "blurry") && (!isExtraFrame || keep)))
    }
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
    /// lenient | normal | strict (M11): how strictly photos count as blurry and eyes as closed.
    public var qualityStrictness: String
    public init(uiLanguage: String, aiGpuShare: Int, aiPauseOnBattery: Bool, keeperWeights: [String: Int],
                qualityStrictness: String = "normal") {
        self.uiLanguage = uiLanguage; self.aiGpuShare = aiGpuShare
        self.aiPauseOnBattery = aiPauseOnBattery; self.keeperWeights = keeperWeights
        self.qualityStrictness = qualityStrictness
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uiLanguage = try c.decode(String.self, forKey: .uiLanguage)
        aiGpuShare = try c.decode(Int.self, forKey: .aiGpuShare)
        aiPauseOnBattery = try c.decode(Bool.self, forKey: .aiPauseOnBattery)
        keeperWeights = try c.decode([String: Int].self, forKey: .keeperWeights)
        qualityStrictness = try c.decodeIfPresent(String.self, forKey: .qualityStrictness) ?? "normal"
    }
    enum CodingKeys: String, CodingKey {
        case uiLanguage = "ui_language", aiGpuShare = "ai_gpu_share", aiPauseOnBattery = "ai_pause_on_battery",
             keeperWeights = "keeper_weights", qualityStrictness = "quality_strictness"
    }
    public static let strictnessLevels = ["lenient", "normal", "strict"]
    public static let gpuShareRange = 10...100
}

/// The measured speed of this Mac (engine `speed.json`, M11): seconds per photo of a first analysis.
public struct EngineSpeed: Codable, Hashable, Sendable {
    /// Work the owner's share slows down (focus, faces, subject sharpness).
    public let throttledPerPhoto: Double
    /// The rest (reading files, times, places).
    public let otherPerPhoto: Double
    public let photos: Int
    public init(throttledPerPhoto: Double, otherPerPhoto: Double, photos: Int) {
        self.throttledPerPhoto = throttledPerPhoto; self.otherPerPhoto = otherPerPhoto; self.photos = photos
    }
    enum CodingKeys: String, CodingKey {
        case throttledPerPhoto = "throttled_per_photo", otherPerPhoto = "other_per_photo", photos
    }
    /// Seconds for a first analysis of `photos` photos at `share` % (the engine's `estimate_seconds`).
    public func seconds(photos: Int, share: Int) -> Double? {
        guard photos > 0 else { return nil }
        let s = Double(min(100, max(1, share)))
        return Double(photos) * (otherPerPhoto + throttledPerPhoto * 100 / s)
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
    /// The first search of an album builds the search index in the background (M9); search again after it.
    public let preparing: Bool?
}
