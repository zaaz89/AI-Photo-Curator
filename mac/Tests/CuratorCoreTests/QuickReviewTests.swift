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
    #expect(reviewQueue(all, filter: .decisions) == [2, 3, 4, 5])        // the fine single photo stays, no question
    let keeper = try photo(6, #""duplicate": {"group": 4, "category": "near", "keeper": true}"#)
    let scene = try photo(7, #""duplicate": {"group": 5, "category": "similar_scene"}"#)
    #expect(reviewQueue([keeper, scene, fine], filter: .decisions) == [6])   // every frame of a moment, not similar scenes
    let shades = try photo(8, #""quality": {"blur": "sharp", "reasons": ["eyes_unsure"], "utility": false}"#)
    #expect(reviewQueue([shades], filter: .decisions).isEmpty)              // sunglasses alone: no question
    #expect(reviewQueue(all, filter: .leftOut) == [2, 3])    // what the export would not take
}

private func box(_ x: Double, _ y: Double, _ w: Double = 0.1, state: String? = nil, main: Bool? = nil) throws -> Photo.Faces.Box {
    var parts = [#""x": \#(x), "y": \#(y), "w": \#(w), "h": \#(w)"#]
    if let state { parts.append(#""state": "\#(state)""#) }
    if let main { parts.append(#""main": \#(main)"#) }
    return try JSONDecoder().decode(Photo.Faces.Box.self, from: Data(("{" + parts.joined(separator: ", ") + "}").utf8))
}

@Test func sameFacesLineUpAcrossTheFramesOfAMoment() throws {
    // Frame 0: Ana left, Bor right, a tiny face far behind. Frame 1: both moved a little, Ana's eyes closed.
    // Frame 2: Bor turned away (no face found), Ana listed second.
    let f0 = [try box(0.2, 0.3), try box(0.6, 0.3), try box(0.45, 0.1, 0.02)]
    let f1 = [try box(0.62, 0.31), try box(0.21, 0.29, state: "closed")]
    let f2 = [try box(0.9, 0.9, 0.02), try box(0.19, 0.31)]
    let rows = matchFaces([f0, f1, f2], reference: 0)
    #expect(rows.count == 2)                                       // the tiny background face gets no row
    #expect(rows[0][1].map(eyeState) == "closed" && rows[0][2]?.x == 0.19)   // Ana in every frame
    #expect(rows[1][1]?.x == 0.62 && rows[1][2] == nil)            // Bor: turned away in frame 2
    #expect(mainFaces([try box(0.1, 0.1, main: false), try box(0.5, 0.5)]).count == 1)
}

@Test func keepTooAndExactCopies() throws {
    let extraKept = try photo(9, #""keep": true, "duplicate": {"group": 4, "category": "near", "keeper": false}"#)
    #expect(extraKept.goesToAlbumDespiteFocus && !extraKept.favorite)          // in the album without 5 stars
    let copy = try photo(10, #""duplicate": {"group": 7, "category": "exact", "keeper": false}"#)
    #expect(!isMomentFrame(copy) && reviewQueue([copy], filter: .decisions).isEmpty)   // no question about copies
}
