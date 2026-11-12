import AppKit
import Foundation
import Testing
@testable import CuratorCore
@testable import PhotoCurator

/// A fake engine: answers the timeline from the fixture and records every write in order.
final class FakeEngine: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var writes: [String] = []        // in the order the engine finished them
    nonisolated(unsafe) static var arrived = 0
    nonisolated(unsafe) static var delayMarks = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        var body = Data()
        if let s = request.httpBodyStream {
            s.open(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; body.append(buf, count: n) }
        }
        let answer: Data
        if path.hasSuffix("/timeline") {
            answer = try! Data(contentsOf: Bundle.module.url(forResource: "timeline", withExtension: "json", subdirectory: "Fixtures")!)
        } else if path.hasSuffix("/sources") {
            answer = Data(#"{"sources": []}"#.utf8)
        } else {
            answer = Data(#"{"ok": true}"#.utf8)
        }
        let isWrite = request.httpMethod == "POST"
        if isWrite { Self.arrived += 1 }
        let order = Self.arrived
        let finish = {
            if isWrite { FakeEngine.writes.append(path + " " + (String(data: body, encoding: .utf8) ?? "")) }
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                                     cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: answer)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        // The first mark answers late, so a second mark could overtake it without a write queue.
        if Self.delayMarks && path.hasSuffix("/marks/batch") && order == 1 {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3, execute: finish)
        } else { finish() }
    }
    override func stopLoading() {}
}

@MainActor func model() async -> LibraryModel {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [FakeEngine.self]
    let m = LibraryModel(api: APIClient(base: URL(string: "http://127.0.0.1:5014")!, session: URLSession(configuration: cfg)))
    m.trips = [Trip(id: "a", name: "A", assets: 3), Trip(id: "b", name: "B", assets: 3)]
    m.tripId = "a"
    await m.reload()
    FakeEngine.writes = []
    FakeEngine.arrived = 0
    return m
}

@MainActor func waitUntil(_ cond: () -> Bool) async {
    for _ in 0..<100 where !cond() { try? await Task.sleep(for: .milliseconds(20)) }
}

@Suite(.serialized) @MainActor struct LibraryModelTests {
    @Test func tripSwitchClearsPhotosAndRefusesMarks() async {
        let m = await model()
        #expect(m.flat.count == 2)
        m.click(m.flat[0], modifiers: [])
        m.tripId = "b"                                  // switched; B is still loading
        #expect(m.photos.isEmpty && m.flat.isEmpty)
        m.mark([m.flat.first].compactMap { $0 } + m.selectedPhotos, ["favorite": .bool(true)], name: "x")
        m.move(toEvent: 7)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(FakeEngine.writes.isEmpty)
    }

    @Test func leavingOutKeepsTargetsAndInspectorOnTheSamePhoto() async {
        let m = await model()
        let first = m.flat[0], second = m.flat[1]
        m.click(first, modifiers: [])
        m.toggleLeaveOut()                               // `first` disappears from All Photos
        #expect(!m.flat.contains { $0.id == first.id })
        #expect(m.single?.id == m.targets.first?.id)    // inspector and actions agree
        #expect(m.single?.id == second.id)              // the next photo is selected, visibly
    }

    @Test func undoIsRegisteredAtOnce() async {
        let m = await model()
        let um = UndoManager(); um.groupsByEvent = false
        m.undoManager = um
        m.click(m.flat[1], modifiers: [])
        um.beginUndoGrouping(); m.toggleFavourite(); um.endUndoGrouping()
        #expect(um.undoActionName == m.tr("favourite"))   // registered before the engine has answered
    }

    @Test func writesReachTheEngineInOrder() async {
        let m = await model()
        FakeEngine.delayMarks = true
        defer { FakeEngine.delayMarks = false }
        m.click(m.flat[1], modifiers: [])
        m.toggleFavourite()                              // on
        m.toggleFavourite()                              // off
        await waitUntil { FakeEngine.writes.count >= 2 }
        #expect(FakeEngine.writes.count == 2)
        #expect(FakeEngine.writes[0].contains("\"favorite\":true"))
        #expect(FakeEngine.writes[1].contains("\"favorite\":false"))
    }
}

@MainActor @Test func engineStartsOnlyOnce() async {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = []                              // nothing answers on this port in tests
    let api = APIClient(base: URL(string: "http://127.0.0.1:9")!, session: URLSession(configuration: cfg))
    var launches = 0
    let engine = EngineController(api: api) {
        launches += 1
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sleep"); p.arguments = ["5"]
        try p.run(); return p
    }
    engine.start()
    engine.start()                                        // second window, or a double click on Try Again
    await waitUntil { launches > 0 }
    try? await Task.sleep(for: .milliseconds(300))
    #expect(launches == 1)
    engine.stopIfOwned()
}
