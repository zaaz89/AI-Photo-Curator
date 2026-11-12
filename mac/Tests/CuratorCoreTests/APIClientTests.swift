import Foundation
import Testing
@testable import CuratorCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func decodesTimeline() throws {
    let t = try JSONDecoder().decode(Timeline.self, from: fixture("timeline"))
    #expect(t.items.count == 3)
    #expect(t.events.first?.name == "Evening")
    let photo = t.items[0]
    #expect(photo.clock == "17:48")
    #expect(photo.day == "2026-10-23")
    #expect(photo.favorite && !photo.rejected)
    #expect(photo.place?.label == "Florence")
    #expect(photo.faces?.eyesClosed == 1)
    #expect(photo.focus?.tier == "soft")
    #expect(photo.duplicate?.keeper == false)
    #expect(photo.fileURL.path == "/tmp/demo/me/IMG_0001.JPG")
    let video = t.items[1]
    #expect(video.isVideo && video.duration == 12.4 && !video.poster)
    #expect(video.day == "2026-10-23")
    #expect(t.items[2].day == Photo.undated)
}

/// Captures requests instead of sending them.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var response = Data(#"{"ok": true, "count": 2}"#.utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open(); var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            Self.lastBody = d
        } else { Self.lastBody = request.httpBody }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func stubClient() -> APIClient {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubProtocol.self]
    return APIClient(base: URL(string: "http://127.0.0.1:5014")!, session: URLSession(configuration: cfg))
}

@Suite(.serialized) struct StubbedAPI {
@Test func marksBody() async throws {
    try await stubClient().setMarks(trip: "demo", ids: [1, 2], ["favorite": .bool(true), "focus": .null])
    let req = try #require(StubProtocol.lastRequest)
    #expect(req.httpMethod == "POST")
    #expect(req.url?.path == "/api/collections/demo/marks/batch")
    let raw = try #require(StubProtocol.lastBody)
    let body = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
    #expect(body["asset_ids"] as? [Int] == [1, 2])
    #expect(body["favorite"] as? Bool == true)
    #expect(body["focus"] is NSNull)
}

@Test func engineErrorIsThrown() async throws {
    StubProtocol.response = Data(#"{"error": "unknown photo"}"#.utf8)
    defer { StubProtocol.response = Data(#"{"ok": true, "count": 2}"#.utf8) }
    await #expect(throws: APIError.engine("unknown photo")) {
        try await stubClient().setMark(trip: "demo", id: 9, ["favorite": .bool(true)])
    }
}
}
