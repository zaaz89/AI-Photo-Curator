import Foundation

/// The engine's background job (analysis, describing, export), from GET /api/collections/<id>/index.
public struct JobStatus: Decodable, Equatable, Sendable {
    public let running: Bool
    public let collection: String?
    public let kind: String?                 // analysis | describe | export
    public let status: String
    public let progress: Double
    public let error: String?
    /// Where a finished export went (from the job result), for "Show in Finder".
    public let exportFolder: String?
    public let exportOK: Bool?

    public init(running: Bool, collection: String? = nil, status: String, progress: Double = 0, error: String? = nil) {
        self.running = running; self.collection = collection; self.status = status; self.progress = progress; self.error = error
        self.exportFolder = nil; self.exportOK = nil; self.kind = nil
    }
    enum CodingKeys: String, CodingKey { case running, collection, kind, status, progress, error, result }
    struct Result: Decodable { struct Export: Decodable { let ok: Bool?; let dest: String? }; let export: Export? }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        running = try c.decode(Bool.self, forKey: .running)
        collection = try c.decodeIfPresent(String.self, forKey: .collection)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        error = try c.decodeIfPresent(String.self, forKey: .error)
        let result = try? c.decodeIfPresent(Result.self, forKey: .result)
        exportFolder = result?.export?.dest
        exportOK = result?.export?.ok
    }

    /// The phase for the live activity view.
    public var phase: ActivityPhase {
        if error != nil || status.hasPrefix("Error") { return .failed }
        if !running { return .idle }
        return ActivityPhase(status: status)
    }
}

/// What the engine is doing, in the words and symbols the app shows.
public enum ActivityPhase: String, CaseIterable, Sendable {
    case idle, reading, clocks, duplicates, quality, faces, videos, searchIndex, describing, exporting, paused, working, failed

    /// Maps the engine's status text ("Faces (Apple Vision) (3/19)") to a phase.
    public init(status: String) {
        let s = status.lowercased()
        let rules: [(String, ActivityPhase)] = [
            ("paused", .paused), ("hashing", .reading), ("reading metadata", .reading), ("scanning", .reading),
            ("capture times", .clocks), ("matching scenes", .clocks), ("visual signatures", .duplicates),
            ("near duplicates", .duplicates), ("focus and ranking", .quality), ("faces", .faces),
            ("videos", .videos), ("search index", .searchIndex), ("describing", .describing),
            ("copying and verifying", .exporting), ("writing time", .exporting), ("wallpaper", .exporting),
        ]
        self = rules.first { s.contains($0.0) }?.1 ?? .working
    }

    /// Local AI runs in this phase (the window shows the AI glow).
    public var isAI: Bool { [.faces, .searchIndex, .describing].contains(self) }

    /// SF Symbol for the phase.
    public var symbol: String {
        switch self {
        case .idle: return "checkmark.circle"
        case .reading: return "doc.viewfinder"
        case .clocks: return "clock.arrow.2.circlepath"
        case .duplicates: return "square.stack.3d.up"
        case .quality: return "camera.aperture"
        case .faces: return "face.smiling"
        case .videos: return "film.stack"
        case .searchIndex: return "sparkle.magnifyingglass"
        case .describing: return "text.bubble"
        case .exporting: return "square.and.arrow.up"
        case .paused: return "pause.circle"
        case .working: return "gearshape.2"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

extension JobStatus {
    /// "3/19" from "Faces (Apple Vision) (3/19)", if the engine reported a count.
    public var counter: (done: Int, total: Int)? {
        guard let open = status.lastIndex(of: "("), status.hasSuffix(")") else { return nil }
        let parts = status[status.index(after: open)..<status.index(before: status.endIndex)].split(separator: "/")
        guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]), b > 0 else { return nil }
        return (a, b)
    }
}
