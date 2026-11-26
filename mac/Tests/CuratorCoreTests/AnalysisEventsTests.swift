import Foundation
import Testing
@testable import CuratorCore

// M13: the live event stream and the byte-bounded thumbnail cache.

private let page = #"""
{"events": [
  {"seq": 1, "asset_id": 10, "kind": "read", "day": "2026-10-24"},
  {"seq": 2, "asset_id": 11, "kind": "read", "day": "2026-10-24"},
  {"seq": 3, "asset_id": 12, "kind": "read", "day": "2026-10-25"},
  {"seq": 4, "asset_id": 10, "kind": "scored", "day": "2026-10-24"},
  {"seq": 5, "asset_id": 11, "kind": "stacked", "keeper_id": 10, "day": "2026-10-24"},
  {"seq": 6, "asset_id": null, "kind": "settled_day", "day": "2026-10-24"},
  {"seq": 7, "asset_id": 12, "kind": "removed", "reason": "movement_blur", "day": "2026-10-25"},
  {"seq": 8, "asset_id": 12, "kind": "something_new", "day": "2026-10-25"}
], "next": 8, "more": false, "latest": 8}
"""#

@Test func decodesEventPage() throws {
    let p = try JSONDecoder().decode(AnalysisEventPage.self, from: Data(page.utf8))
    #expect(p.events.count == 8 && p.next == 8 && !p.more && p.latest == 8)
    #expect(p.events[4] == AnalysisEvent(seq: 5, assetId: 11, kind: .stacked, keeperId: 10, day: "2026-10-24"))
    #expect(p.events[5].assetId == nil && p.events[5].kind == .settledDay)
    #expect(p.events[6].reason == "movement_blur")
    #expect(p.events[7].kind == .unknown)                       // a newer engine's kind is ignored, not an error
}

@Test func eventsURL() {
    let url = APIClient().url("api/collections/demo/events", ["since": "42"])
    #expect(url.absoluteString == "http://127.0.0.1:5014/api/collections/demo/events?since=42")
}

@Test func mergeBuildsPlacesAndSettledDays() throws {
    let p = try JSONDecoder().decode(AnalysisEventPage.self, from: Data(page.utf8))
    var s = SortStream()
    let first = s.merge(Array(p.events.prefix(3)))
    #expect(first.arrived == [10, 11, 12] && first.judged.isEmpty && s.cursor == 3)
    #expect(s.places[10] == .read && !s.isJudged(10) && !s.isSettled(10))
    let rest = s.merge(page: p)                                  // the page again: the first three change nothing
    #expect(rest.arrived.isEmpty && rest.judged == [10, 11, 12] && rest.settledDays == ["2026-10-24"])
    #expect(s.verdict(10) == .album && s.verdict(11) == .stacked && s.verdict(12) == .removed)
    #expect(s.places[11] == .stacked(keeper: 10) && s.places[12] == .removed(reason: "movement_blur"))
    #expect(s.isSettled(10) && s.isSettled(11) && !s.isSettled(12))
    #expect(s.cursor == 8)
    let before = s.revision
    #expect(s.merge(p.events).isEmpty && s.revision == before)  // merging twice is harmless
}

@Test func laterEventsWinAndReadNeverOverwrites() {
    var s = SortStream()
    s.merge([AnalysisEvent(seq: 1, assetId: 1, kind: .read, day: "d1"),
             AnalysisEvent(seq: 2, assetId: 1, kind: .removed, reason: "subject_blurry", day: "d1"),
             AnalysisEvent(seq: 3, assetId: 1, kind: .scored, day: "d1")])          // the keeper refresh put it back
    #expect(s.verdict(1) == .album)
    // Out-of-order input is merged in seq order.
    var t = SortStream()
    t.merge([AnalysisEvent(seq: 3, assetId: 1, kind: .scored, day: "d1"),
             AnalysisEvent(seq: 1, assetId: 1, kind: .read, day: "d1")])
    #expect(t.verdict(1) == .album && t.cursor == 3)
}

@Test func newDatabaseResetsTheStream() {
    var s = SortStream()
    s.merge([AnalysisEvent(seq: 40, assetId: 1, kind: .scored, day: "d1"),
             AnalysisEvent(seq: 41, assetId: nil, kind: .settledDay, day: "d1")])
    let change = s.merge(page: AnalysisEventPage(events: [AnalysisEvent(seq: 1, assetId: 2, kind: .read, day: "d2")],
                                                 next: 1, more: false, latest: 1))
    #expect(change.arrived == [2] && s.cursor == 1 && s.places[1] == nil && s.settledDays.isEmpty)
}

@Test func pollingAndReloadPacing() {
    #expect(eventPollInterval(running: false, morePending: true) == nil)
    #expect(eventPollInterval(running: true, morePending: true)! < eventPollInterval(running: true, morePending: false)!)
    #expect(shouldReloadPhotos(after: SortStreamChange(settledDays: ["d"]), secondsSinceReload: 0))
    #expect(!shouldReloadPhotos(after: SortStreamChange(judged: [1]), secondsSinceReload: 0.5))
    #expect(shouldReloadPhotos(after: SortStreamChange(judged: [1]), secondsSinceReload: 3))
    #expect(!shouldReloadPhotos(after: SortStreamChange(), secondsSinceReload: 30))
}

// MARK: ByteLRU

@Test func lruEvictsLeastRecentlyUsedByBytes() {
    var c = ByteLRU<String, Int>(limit: 100)
    c.insert(1, for: "a", cost: 40)
    c.insert(2, for: "b", cost: 40)
    #expect(c.value(for: "a") == 1)                              // a is now the newest
    let evicted = c.insert(3, for: "c", cost: 40)
    #expect(evicted == ["b"] && c.totalCost == 80 && c.keysByRecency == ["c", "a"])
    c.insert(4, for: "a", cost: 10)                              // replacing updates the cost
    #expect(c.totalCost == 50 && c.peek("a") == 4 && c.keysByRecency == ["a", "c"])
    #expect(c.remove("c") == 3 && c.totalCost == 10 && c.count == 1)
    let big = c.insert(5, for: "huge", cost: 500)                // larger than the limit: kept alone
    #expect(big == ["a"] && c.count == 1 && c.contains("huge"))
    c.removeAll()
    #expect(c.count == 0 && c.totalCost == 0 && c.keysByRecency.isEmpty)
}

@Test func lruOrderStaysConsistent() {
    var c = ByteLRU<Int, Int>(limit: 1_000)
    for i in 0..<10 { c.insert(i, for: i, cost: 10) }
    _ = c.value(for: 0); _ = c.value(for: 5); _ = c.value(for: 9)
    #expect(c.keysByRecency == [9, 5, 0, 8, 7, 6, 4, 3, 2, 1])
    c.remove(5)
    #expect(c.keysByRecency == [9, 0, 8, 7, 6, 4, 3, 2, 1])
    let limited = ByteLRU<Int, Int>(limit: 25)
    var l = limited
    for i in 0..<5 { l.insert(i, for: i, cost: 10) }
    #expect(l.keysByRecency == [4, 3] && l.totalCost == 20)
}

@Test func thumbnailSizesAndCosts() {
    #expect(thumbnailBucket(96) == 160 && thumbnailBucket(150) == 160 && thumbnailBucket(161) == 260)
    #expect(thumbnailBucket(260) == 260 && thumbnailBucket(600) == 1024 && thumbnailBucket(5000) == 2048)
    #expect(thumbnailCost(pixelWidth: 320, pixelHeight: 240) == 307_200)
    // 3,000 grid thumbnails at 2x (320 px) would not fit the budget: the cache keeps the most recent ones.
    #expect(3_000 * thumbnailCost(pixelWidth: 320, pixelHeight: 320) > thumbnailCacheBudgetBytes)
    #expect(thumbnailCacheBudgetBytes < 1_024 * 1_024 * 1_024 / 2)
}

@Test func daysSortedText() {
    var s = SortStream()
    #expect(stageDaysText(s, .en) == nil)
    s.merge([AnalysisEvent(seq: 1, assetId: 1, kind: .read, day: "d1"),
             AnalysisEvent(seq: 2, assetId: 2, kind: .read, day: "d2"),
             AnalysisEvent(seq: 3, assetId: nil, kind: .settledDay, day: "d1")])
    #expect(stageDaysText(s, .en) == "1 of 2 days sorted")
    #expect(stageDaysText(s, .sl) == "Razvrščenih dni: 1 od 2")
}
