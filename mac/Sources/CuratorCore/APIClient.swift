import Foundation

public enum APIError: Error, Equatable, Sendable {
    case engine(String)          // the engine answered with {"error": ...}
    case http(Int)
    case unreachable(String)
}

/// A value for a mark: favourite / rejected / wallpaper are booleans, focus is a tier or null.
public enum MarkValue: Sendable, Equatable {
    case bool(Bool), string(String), null
    var json: Any {
        switch self {
        case .bool(let b): return b
        case .string(let s): return s
        case .null: return NSNull()
        }
    }
}

/// The engine's local API (Python, 127.0.0.1 only). Every call is read-only on the
/// photo folders; marks and events live in the trip's database.
public final class APIClient: Sendable {
    public let base: URL
    let session: URLSession

    public init(base: URL = URL(string: "http://127.0.0.1:5014")!, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    // MARK: transport

    func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return c.url!
    }

    func get<T: Decodable>(_ path: String, _ query: [String: String] = [:], as: T.Type = T.self) async throws -> T {
        try await send(URLRequest(url: url(path, query)))
    }

    @discardableResult
    func post<T: Decodable>(_ path: String, _ body: [String: Any], as: T.Type = T.self) async throws -> T {
        var r = URLRequest(url: url(path))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(r)
    }

    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw APIError.unreachable(error.localizedDescription) }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let e = obj["error"] as? String {
            throw APIError.engine(e)
        }
        if let h = response as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw APIError.http(h.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    struct OK: Decodable { let ok: Bool? }

    // MARK: endpoints

    public func trips() async throws -> [Trip] {
        struct R: Decodable { let collections: [Trip] }
        return try await get("api/collections", as: R.self).collections
    }

    public func timeline(trip: String) async throws -> Timeline {
        try await get("api/collections/\(trip)/timeline")
    }

    public func sources(trip: String) async throws -> [SourceInfo] {
        struct R: Decodable { let sources: [SourceInfo] }
        return try await get("api/collections/\(trip)/sources", as: R.self).sources
    }

    /// Same marks on several photos (POST /marks/batch).
    public func setMarks(trip: String, ids: [Int], _ fields: [String: MarkValue]) async throws {
        var body: [String: Any] = ["asset_ids": ids]
        for (k, v) in fields { body[k] = v.json }
        try await post("api/collections/\(trip)/marks/batch", body, as: OK.self)
    }

    /// Marks of one photo (used by undo to restore each photo's own previous values).
    public func setMark(trip: String, id: Int, _ fields: [String: MarkValue]) async throws {
        var body: [String: Any] = ["asset_id": id]
        for (k, v) in fields { body[k] = v.json }
        try await post("api/collections/\(trip)/marks", body, as: OK.self)
    }

    /// Move photos into an event; `toEvent: nil` makes a new event named `newName`. Returns the event id.
    @discardableResult
    public func move(trip: String, ids: [Int], toEvent: Int?, newName: String? = nil) async throws -> Int {
        struct R: Decodable { let event_id: Int }
        var body: [String: Any] = ["asset_ids": ids, "event_id": toEvent.map { $0 as Any } ?? NSNull()]
        if let newName { body["name"] = newName }
        return try await post("api/collections/\(trip)/events/move", body, as: R.self).event_id
    }

    public func resetDay(trip: String, day: String) async throws {
        try await post("api/collections/\(trip)/events/reset", ["day": day], as: OK.self)
    }

    public func search(trip: String, query: String) async throws -> SearchResult {
        try await get("api/collections/\(trip)/search", ["q": query])
    }

    public func settings() async throws -> EngineSettings {
        struct R: Decodable { let settings: EngineSettings }
        return try await get("api/settings", as: R.self).settings
    }

    /// `json`: the changed settings as a JSON object, e.g. `{"ui_language": "sl"}`.
    @discardableResult
    public func saveSettings(json: Data) async throws -> EngineSettings {
        struct R: Decodable { let settings: EngineSettings }
        var r = URLRequest(url: url("api/settings"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = json
        let res: R = try await send(r)
        return res.settings
    }

    /// The album checklist: step name -> done (import, times, duplicates, blurry, events, descriptions, export).
    public func workflow(trip: String) async throws -> [String: Bool] {
        struct Step: Decodable { let step: String; let done: Bool }
        struct R: Decodable { let steps: [Step] }
        let r: R = try await get("api/collections/\(trip)/workflow")
        return Dictionary(r.steps.map { ($0.step, $0.done) }, uniquingKeysWith: { a, _ in a })
    }

    /// "Finish album": the engine deletes its working data for the album; photo folders are untouched.
    public func finishAlbum(trip: String) async throws -> (removedCacheFiles: Int, freedBytes: Int) {
        struct R: Decodable { let removed_cache_files: Int; let freed_bytes: Int }
        var r = URLRequest(url: url("api/collections/\(trip)"))
        r.httpMethod = "DELETE"
        let res: R = try await send(r)
        return (res.removed_cache_files, res.freed_bytes)
    }

    public func jobStatus(trip: String) async throws -> JobStatus {
        try await get("api/collections/\(trip)/index")
    }

    public func startAnalysis(trip: String) async throws {
        try await post("api/collections/\(trip)/index", [:], as: OK.self)
    }

    public func stopJob(trip: String) async throws {
        var r = URLRequest(url: url("api/collections/\(trip)/index"))
        r.httpMethod = "DELETE"
        let _: OK = try await send(r)
    }

    /// True when the engine answers (used while it starts).
    public func ping() async -> Bool {
        var r = URLRequest(url: url("api/settings"))
        r.timeoutInterval = 1
        return (try? await session.data(for: r)).map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
    }
}
