import Foundation
import Testing
@testable import CuratorCore

// M12f: album cover, day cards, dates, first run, celebration gate, haptics and stagger budget.

private func photo(_ id: Int, day: String? = "2026-10-23", _ extra: String = "") throws -> Photo {
    let time = day.map { #", "local_time": "\#($0)T12:00:00""# } ?? ""
    let more = extra.isEmpty ? "" : ", " + extra
    return try JSONDecoder().decode(Photo.self, from: Data(
        #"{"id": \#(id), "filename": "p\#(id).jpg", "path": "/x/p\#(id).jpg", "kind": "image"\#(time)\#(more)}"#.utf8))
}

@Test func albumCoverPrefersTheEnginesCoverWhileItIsInTheAlbum() throws {
    let photos = [try photo(1), try photo(2, #""favorite": true"#), try photo(3, #""rejected": true"#)]
    #expect(albumCover(photos, coverId: 1)?.id == 1)
    // A cover the owner left out is not shown; the favourite wins.
    #expect(albumCover(photos, coverId: 3)?.id == 2)
    // No engine cover: the first highlight that is in the album.
    #expect(albumCover(photos, coverId: nil, highlights: [3, 1])?.id == 1)
    // Nothing known: the best in the album (favourite).
    #expect(albumCover(photos, coverId: nil)?.id == 2)
}

@Test func albumCoverSkipsVideosAndFallsBackToFirstKept() throws {
    let photos = [try photo(1), try photo(2), try photo(3)]
    #expect(albumCover(photos, coverId: nil)?.id == 1)            // nothing stands out: the first kept
    let video = try JSONDecoder().decode(Photo.self, from: Data(
        #"{"id": 9, "filename": "v.mov", "path": "/x/v.mov", "kind": "video", "favorite": true}"#.utf8))
    #expect(albumCover([video, try photo(4)], coverId: 9)?.id == 4)
    #expect(albumCover([], coverId: nil) == nil)
    // Everything left out: still a cover (the album is not empty on screen).
    #expect(albumCover([try photo(5, #""rejected": true"#)], coverId: nil)?.id == 5)
}

@Test func daySpanReadsStartAndEnd() {
    let trip = albumDaySpan(start: "2026-10-23T08:01:00", end: "2026-10-26T21:40:00")
    #expect(trip?.first == "2026-10-23" && trip?.last == "2026-10-26")
    let oneDay = albumDaySpan(start: "2026-10-23T08:01:00", end: "2026-10-23T21:40:00")
    #expect(oneDay?.first == "2026-10-23" && oneDay?.last == nil)
    #expect(albumDaySpan(start: nil, end: "2026-10-24T10:00:00")?.first == "2026-10-24")
    #expect(albumDaySpan(start: nil, end: nil) == nil)
    #expect(albumDaySpan(start: "garbage", end: "x") == nil)
}

@Test func dayCardsGroupPhotosWithChapterNamesAndCovers() throws {
    let events = try JSONDecoder().decode([TripEvent].self, from: Data("""
    [{"id": 1, "day": "2026-10-23", "name": "Pienza", "count": 2, "place_label": "Pienza, Tuscany"},
     {"id": 2, "day": "2026-10-23", "name": " Pienza ", "count": 1},
     {"id": 3, "day": "2026-10-23", "name": "Dinner", "count": 1},
     {"id": 4, "day": "2026-10-24", "name": "", "count": 1}]
    """.utf8))
    let photos = [try photo(1, day: "2026-10-24"), try photo(2), try photo(3, #""favorite": true"#),
                  try photo(4, #""rejected": true"#), try photo(5, day: nil)]
    let cards = dayCards(photos: photos, events: events, highlights: [2])
    #expect(cards.map(\.day) == ["2026-10-23", "2026-10-24", Photo.undated])
    #expect(cards[0].taken == 3 && cards[0].inAlbum == 2)
    #expect(cards[0].chapters == ["Pienza", "Dinner"])                // trimmed, no repeats, no blanks
    #expect(cards[0].place == "Pienza, Tuscany")
    #expect(cards[0].coverId == 2)                                     // the highlight beats the favourite
    #expect(cards[1].chapters.isEmpty && cards[1].coverId == 1 && cards[1].place == nil)
    #expect(dayCards(photos: [], events: events).isEmpty)
}

@Test func firstRunShowsOnceAndPagesFollowTheKeys() {
    #expect(FirstRun.shouldShow(seen: false))
    #expect(!FirstRun.shouldShow(seen: true))
    #expect(FirstRunPage.allCases.count == 3)
    #expect(FirstRun.page(after: "right", on: .what) == .safety)
    #expect(FirstRun.page(after: "right", on: .start) == nil)          // the last page closes through its button
    #expect(FirstRun.page(after: "left", on: .what) == nil)
    #expect(FirstRun.page(after: "left", on: .start) == .safety)
    #expect(FirstRun.page(after: "x", on: .safety) == nil)
    #expect(FirstRunPage.start.isLast && !FirstRunPage.what.isLast)
}

@Test func exportCelebratesOncePerVerifiedFolder() {
    #expect(shouldCelebrateExport(ok: true, folder: "/out/a", celebrated: []))
    #expect(!shouldCelebrateExport(ok: true, folder: "/out/a", celebrated: ["/out/a"]))
    #expect(!shouldCelebrateExport(ok: false, folder: "/out/b", celebrated: []))
    #expect(!shouldCelebrateExport(ok: true, folder: "", celebrated: []))
}

@Test func decisionPulseChangesEveryTime() {
    let a = DecisionPulse.none.next(.keep)
    let b = a.next(.keep)
    #expect(a != b && b.tick == 2 && b.kind == .keep)
    #expect(b.next(.leaveOut).kind == .leaveOut)
}

@Test func staggerStaysWithinTheMotionBudget() {
    #expect(staggerDelay(0, of: 10) == 0)
    #expect(staggerDelay(3, of: 1) == 0)
    #expect(staggerDelay(1, of: 3) > 0)
    for count in [2, 3, 8, 50, 3000] {
        let delays = (0..<min(count, 60)).map { staggerDelay($0, of: count) }
        #expect(delays.allSatisfy { $0 <= 0.24 + 1e-9 && $0 <= motionBudget })
        #expect(zip(delays, delays.dropFirst()).allSatisfy { $0 <= $1 })   // never out of order
    }
    #expect(staggerDelay(5, of: 10, total: 5) <= motionBudget)
}
