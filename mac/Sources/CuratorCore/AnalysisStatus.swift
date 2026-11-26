import Foundation

// M14c: one status for the analysis. The engine reports its phase plan (`stage` in the job status, from
// `app/analysis_progress.py`); the stage header, the toolbar pill, the sidebar and the journey bar all read it
// through these functions, so they never disagree ("Aligning clocks 100%" next to "Working" was two readings of
// one status text). Pure, so it is unit-tested.

/// The engine's phase plan state (job status `stage`).
public struct EngineStage: Decodable, Equatable, Sendable {
    public let phase: String
    public let step: String?
    public let day: Int
    public let days: Int
    public let source: Int
    public let sources: Int
    public let sourceId: Int?
    public let done: Int
    public let total: Int
    /// 0-100, over the whole plan; never goes back.
    public let progress: Int

    public init(phase: String, step: String? = nil, day: Int = 0, days: Int = 0, source: Int = 0, sources: Int = 0,
                sourceId: Int? = nil, done: Int = 0, total: Int = 0, progress: Int = 0) {
        self.phase = phase; self.step = step; self.day = day; self.days = days; self.source = source
        self.sources = sources; self.sourceId = sourceId; self.done = done; self.total = total; self.progress = progress
    }

    enum CodingKeys: String, CodingKey {
        case phase, step, day, days, source, sources, done, total, progress
        case sourceId = "source_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decode(String.self, forKey: .phase)
        step = try c.decodeIfPresent(String.self, forKey: .step)
        day = try c.decodeIfPresent(Int.self, forKey: .day) ?? 0
        days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 0
        source = try c.decodeIfPresent(Int.self, forKey: .source) ?? 0
        sources = try c.decodeIfPresent(Int.self, forKey: .sources) ?? 0
        sourceId = try c.decodeIfPresent(Int.self, forKey: .sourceId)
        done = try c.decodeIfPresent(Int.self, forKey: .done) ?? 0
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
    }
}

/// The analysis's phases, in order.
public enum AnalysisPhase: String, CaseIterable, Sendable, Comparable {
    case reading, clocks, places, days, finishing

    public static func < (a: AnalysisPhase, b: AnalysisPhase) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// What the analysis is doing now, from the engine's phase plan (or, from an older engine, its status text).
public struct AnalysisStatus: Equatable, Sendable {
    public var phase: AnalysisPhase
    /// Inside a day: similar | focus | faces | videos | moments.
    public var step: String?
    public var day: Int
    public var days: Int
    public var done: Int
    public var total: Int
    /// 0-1 over the whole plan.
    public var fraction: Double
    /// The engine rests to keep the Mac cool (throttle).
    public var paused: Bool

    public init(phase: AnalysisPhase, step: String? = nil, day: Int = 0, days: Int = 0, done: Int = 0, total: Int = 0,
                fraction: Double = 0, paused: Bool = false) {
        self.phase = phase; self.step = step; self.day = day; self.days = days; self.done = done; self.total = total
        self.fraction = fraction; self.paused = paused
    }
}

/// The analysis status of a running analysis job (nil when no analysis runs).
public func analysisStatus(_ job: JobStatus) -> AnalysisStatus? {
    guard job.running, (job.kind ?? "analysis") == "analysis" else { return nil }
    let paused = job.phase == .paused
    if let s = job.stage, let phase = AnalysisPhase(rawValue: s.phase) {
        return AnalysisStatus(phase: phase, step: s.step, day: s.day, days: s.days, done: s.done, total: s.total,
                              fraction: Double(min(100, max(0, s.progress))) / 100, paused: paused)
    }
    // An engine before M14c: the phase from the status text ("Day 3 of 7: Focus and ranking scores (4/30)").
    var out = AnalysisStatus(phase: .reading, fraction: min(1, max(0, job.progress / 100)), paused: paused)
    if let c = job.counter { out.done = c.done; out.total = c.total }
    if let (d, n) = dayOfDays(job.status) {
        out.phase = .days; out.day = d; out.days = n
        out.step = dayStep(job.status)
        return out
    }
    switch job.phase {
    case .clocks: out.phase = .clocks
    case .reading, .paused: out.phase = .reading
    default: out.phase = .places
    }
    return out
}

/// (3, 7) from "Day 3 of 7: …".
func dayOfDays(_ status: String) -> (Int, Int)? {
    guard status.hasPrefix("Day "), let colon = status.firstIndex(of: ":") else { return nil }
    let parts = status[status.index(status.startIndex, offsetBy: 4)..<colon].split(separator: " ")
    guard parts.count == 3, parts[1] == "of", let d = Int(parts[0]), let n = Int(parts[2]) else { return nil }
    return (d, n)
}

func dayStep(_ status: String) -> String? {
    let s = status.lowercased()
    let rules: [(String, String)] = [("visual signatures", "similar"), ("focus and ranking", "focus"),
                                     ("subject sharpness", "faces"), ("faces", "faces"), ("videos", "videos"),
                                     ("near duplicates", "moments"), ("moments", "moments")]
    return rules.first { s.contains($0.0) }?.1
}

/// The header title in the owner's words: "Reading photos", "Aligning cameras", "Finding places",
/// "Sorting day 3 of 7", "Comparing similar shots", "Finishing the album".
public func analysisTitle(_ s: AnalysisStatus, _ lang: Lang) -> String {
    if s.paused { return Strings.text("phase_paused", lang) }
    switch s.phase {
    case .reading: return Strings.text("m14c_reading", lang)
    case .clocks: return Strings.text("m14c_clocks", lang)
    case .places: return Strings.text("m14c_places", lang)
    case .finishing: return Strings.text("m14c_finishing", lang)
    case .days:
        if s.step == "moments" || s.step == "similar" { return Strings.text("m14c_similar", lang) }
        guard s.days > 0 else { return Strings.text("m14c_sorting", lang) }
        return String(format: Strings.text("m14c_sortingDay", lang), s.day, s.days)
    }
}

/// The detail under the title: the day and what is done in it, with the step's counter
/// ("Day 3 of 7 · checking focus · 12 / 40", "Ceremony folder · 120 / 212").
public func analysisDetail(_ s: AnalysisStatus, _ lang: Lang) -> String {
    var parts: [String] = []
    if s.phase == .days {
        if s.step == "moments" || s.step == "similar", s.days > 0 {
            parts.append(String(format: Strings.text("m14c_dayOf", lang), s.day, s.days))
        }
        if let step = s.step, step != "moments", step != "similar" {
            parts.append(Strings.text("m14c_step_" + step, lang))
        }
    }
    if s.total > 0 { parts.append("\(min(s.done, s.total)) / \(s.total)") }
    return parts.joined(separator: " · ")
}

/// The toolbar pill is not shown while the Analysis station is on screen for the album being analysed: the stage
/// header says the same, bigger, from the same status. Elsewhere (another album, a grid, an export, idle) it shows.
public func showsActivityPill(analysingShownAlbum: Bool, stageOnScreen: Bool) -> Bool {
    !(analysingShownAlbum && stageOnScreen)
}

/// The pill's words: the analysis status when an analysis runs, the job's phase otherwise.
public func activityTitle(_ job: JobStatus, _ lang: Lang) -> String {
    if let s = analysisStatus(job) { return analysisTitle(s, lang) }
    return Strings.text("phase_" + job.phase.rawValue, lang)
}

/// The pill's and bars' value (0-1): the plan's progress for an analysis, the job's share otherwise.
public func activityFraction(_ job: JobStatus) -> Double {
    analysisStatus(job)?.fraction ?? min(1, max(0, job.progress / 100))
}

/// The photos are fetched again when the analysis moves into a phase where their capture times (clocks) or
/// corrected times (places, days) are new, so the stage groups them by their real day before any event arrives.
public func reloadsPhotos(from old: AnalysisPhase?, to new: AnalysisPhase?) -> Bool {
    guard let new, new != old, [.clocks, .places, .days].contains(new) else { return false }
    guard let old else { return true }
    return old < new
}

// MARK: folder chips on the stage (M14c)

/// How far the engine is with one folder (`/sources` `read_state`).
public struct SourceReadState: Decodable, Hashable, Sendable {
    /// waiting | reading | read | empty | failed
    public let state: String
    public let done: Int
    public let total: Int
    public let reason: String?
    public init(state: String, done: Int = 0, total: Int = 0, reason: String? = nil) {
        self.state = state; self.done = done; self.total = total; self.reason = reason
    }
    enum CodingKeys: String, CodingKey { case state, done, total, reason }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(String.self, forKey: .state)
        done = try c.decodeIfPresent(Int.self, forKey: .done) ?? 0
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// The chip's name: the engine's (unique per album) or, from an older engine, person · camera with the folder
/// name added when two chips would read the same.
public func sourceChipName(_ s: SourceInfo, among all: [SourceInfo]) -> String {
    if let c = s.chip, !c.isEmpty { return c }
    let label = { (x: SourceInfo) in folderChipLabel(owner: x.owner, devices: x.devices ?? []) }
    let mine = label(s)
    let twins = all.filter { $0.id != s.id && label($0).lowercased() == mine.lowercased() }
    guard !twins.isEmpty else { return mine }
    let folder = URL(fileURLWithPath: s.path).lastPathComponent
    return folder.isEmpty || folder == mine ? "\(mine) (\(s.id))" : "\(s.owner) · \(folder)"
}

/// The chip's second line: "Waiting", "Reading 12 of 80", "120/212", "No photos found", "Couldn't read: …".
/// `arrived`/`shown` are the stage's own counts for this folder.
public func sourceChipDetail(_ s: SourceInfo, arrived: Int, shown: Int, _ lang: Lang) -> String {
    switch s.readState?.state {
    case "waiting": return Strings.text("m14c_chipWaiting", lang)
    case "reading":
        let r = s.readState!
        return r.total > 0 ? String(format: Strings.text("m14c_chipReading", lang), r.done, r.total)
            : Strings.text("m14c_chipReadingShort", lang)
    case "empty": return Strings.text("m14c_chipEmpty", lang)
    case "failed":
        let reason = s.readState?.reason ?? ""
        if reason.isEmpty { return Strings.text("m14c_chipFailed", lang) }
        let words = reason == "folder not found" ? Strings.text("m14c_reasonFolderNotFound", lang) : reason
        return String(format: Strings.text("m14c_chipFailedReason", lang), words)
    default:
        if shown > 0 { return "\(arrived)/\(shown)" }
        if let n = s.assets, n > 0 { return Strings.count(n, .photo, lang) }
        return s.readState == nil ? Strings.text("m14c_chipWaiting", lang) : Strings.text("m14c_chipEmpty", lang)
    }
}

// MARK: the tile being analysed and the day being sorted (M14c)

/// The album's days in the engine's order: dated days chronologically, "no date" last.
public func analysisDayOrder(_ days: [String]) -> [String] {
    let unique = Array(Set(days))
    return unique.filter { $0 != Photo.undated }.sorted() + (unique.contains(Photo.undated) ? [Photo.undated] : [])
}

/// The day the analysis is sorting now (from the plan's "day 3 of 7"), nil outside the per-day loop.
public func currentAnalysisDay(_ s: AnalysisStatus, days: [String]) -> String? {
    guard s.phase == .days, s.day >= 1, s.day <= days.count else { return nil }
    return days[s.day - 1]
}

/// Which of the current day's photos (in time order) the step is at, nil when the step has no counter (moments).
public func analysedIndex(_ s: AnalysisStatus, photosInDay n: Int) -> Int? {
    guard s.phase == .days, n > 0, s.total > 0, let step = s.step, step != "moments" else { return nil }
    return min(n - 1, max(0, s.done * n / s.total))
}
