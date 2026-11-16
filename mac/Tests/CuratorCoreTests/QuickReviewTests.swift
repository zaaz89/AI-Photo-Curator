import Foundation
import Testing
@testable import CuratorCore

private func photo(_ id: Int, _ extra: String = "") throws -> Photo {
    let sep = extra.isEmpty ? "" : ", "
    return try JSONDecoder().decode(Photo.self, from: Data(#"{"id": \#(id), "filename": "p\#(id).jpg", "path": "/x/p\#(id).jpg", "kind": "image"\#(sep)\#(extra)}"#.utf8))
}

@Test func backGoesToThePreviousPhotoAndHandsBackItsMarks() {
    var s = ReviewSession(queue: [1, 2, 3])
    #expect(s.current == 1 && !s.canGoBack)
    s.record(.keep, previous: ["rejected": .bool(true)])
    s.record(.leaveOut, previous: ["rejected": .bool(false)])
    #expect(s.current == 3 && s.counts.kept == 1 && s.counts.leftOut == 1)
    let e = s.back()
    #expect(e?.photoId == 2 && e?.previous == ["rejected": .bool(false)] && s.current == 2)
    #expect(s.counts.leftOut == 0)
    _ = s.back()                                       // back again, as many steps as needed
    #expect(s.current == 1 && !s.canGoBack)
    #expect(s.back() == nil && s.current == 1)
}

@Test func skippedAndFinished() {
    var s = ReviewSession(queue: [1, 2])
    s.record(.skip, previous: [:])
    s.record(.keep, previous: [:])
    #expect(s.finished && s.current == nil && s.skippedIds == [1] && s.counts == (1, 0, 1))
    let again = ReviewSession(queue: [1, 2, 3], startAt: 2)      // resumes where the last review stopped
    #expect(again.current == 2)
    #expect(ReviewSession(queue: [1, 2], startAt: 9).current == 1)
}

@Test func reasonsAndFilters() throws {
    let fine = try photo(1, #""focus": {"tier": "sharp"}"#)
    let blurry = try photo(2, #""focus": {"tier": "blurry", "auto_tier": "blurry"}"#)
    let extra = try photo(3, #""duplicate": {"group": 4, "category": "near", "keeper": false}"#)
    let v2 = try photo(4, #""quality": {"blur": "sharp", "reasons": ["eyes_closed"], "utility": false}"#)
    let shot = try photo(5, #""quality": {"blur": "sharp", "reasons": [], "utility": true}"#)
    #expect(reviewReasons(fine).isEmpty)
    #expect(reviewReasons(blurry) == ["whole_blurry"])
    #expect(reviewReasons(extra) == ["extra_frame"])
    #expect(reviewReasons(v2) == ["eyes_closed"])            // the engine's own codes win
    #expect(reviewReasons(shot) == ["utility_image"])
    let all = [fine, blurry, extra, v2, shot]
    #expect(reviewQueue(all, filter: .all) == [1, 2, 3, 4, 5])
    #expect(reviewQueue(all, filter: .unsure) == [2, 3, 4, 5])
    #expect(reviewQueue(all, filter: .leftOut) == [2, 3])    // what the export would not take
}
