import Foundation
import Testing
@testable import CuratorCore

private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, main: Bool? = nil) throws -> Photo.Faces.Box {
    let m = main.map { #", "main": \#($0)"# } ?? ""
    return try JSONDecoder().decode(Photo.Faces.Box.self, from: Data(#"{"x": \#(x), "y": \#(y), "w": \#(w), "h": \#(h)\#(m)}"#.utf8))
}

private func near(_ a: ZoomPoint, _ x: Double, _ y: Double) -> Bool { abs(a.x - x) < 1e-9 && abs(a.y - y) < 1e-9 }

// MARK: keymap

@Test func reviewKeysInSingleMode() {
    func c(_ k: ReviewKey, _ m: ReviewKeyModifiers = []) -> ReviewCommand? { ReviewKeymap.command(for: k, modifiers: m, in: .single) }
    #expect(c(.right) == .keep && c(.left) == .leaveOut && c(.delete) == .back && c(.space) == .skip && c(.escape) == .close)
    #expect(c(.character("z")) == .zoom && c(.character("Z")) == .zoom && c(.character("f")) == .favourite)
    #expect(c(.character("e")) == .faces && c(.character("c")) == .compare)
    #expect(c(.character("?"), .shift) == .keys && c(.character("/")) == .keys)
}

@Test func keysThatAreNotTheReviewsPassThrough() {
    // Up and down, Return, digits outside compare, and anything with ⌘ ⌥ ⌃ (VoiceOver, menus, ⌘Z) are not handled.
    for k in [ReviewKey.up, .down, .returnKey, .character("1"), .character("x")] {
        #expect(ReviewKeymap.command(for: k, in: .single) == nil)
    }
    #expect(ReviewKeymap.command(for: .right, modifiers: [.control, .option], in: .single) == nil)
    #expect(ReviewKeymap.command(for: .character("z"), modifiers: .command, in: .single) == nil)
    #expect(ReviewKeymap.command(for: .left, modifiers: .option, in: .compare) == nil)
}

@Test func reviewKeysInCompareMode() {
    func c(_ k: ReviewKey) -> ReviewCommand? { ReviewKeymap.command(for: k, in: .compare) }
    #expect(c(.character("1")) == .pickFirst && c(.character("2")) == .pickSecond)
    #expect(c(.right) == .nextChallenger && c(.left) == .previousChallenger)
    #expect(c(.escape) == .close && c(.character("c")) == .close && c(.character("z")) == .zoom)
    // No decision on the whole photo by accident while comparing.
    #expect(c(.space) == nil && c(.delete) == nil && c(.character("3")) == nil)
}

@Test func keysCardListsEveryCommandOfItsContext() {
    for ctx in ReviewContext.allCases {
        let entries = ReviewKeymap.entries(ctx)
        #expect(Set(entries.map(\.command)).count == entries.count, "a command listed twice in \(ctx)")
        for e in entries {
            #expect(Strings.table[e.textKey] != nil, "missing string \(e.textKey)")
        }
    }
    let single = Set(ReviewKeymap.entries(.single).map(\.command))
    #expect(single == [.keep, .leaveOut, .back, .skip, .favourite, .zoom, .faces, .compare, .keys, .close])
    let compare = Set(ReviewKeymap.entries(.compare).map(\.command))
    #expect(compare == [.pickFirst, .pickSecond, .nextChallenger, .previousChallenger, .zoom, .keys, .close])
}

@Test func announcementsAndValue() {
    #expect(reviewAnnouncement(.keep, position: 12, total: 80, .en) == "Kept, 12 of 80")
    #expect(reviewAnnouncement(.leaveOut, position: 1, total: 2, .sl) == "Izpuščena, 1 od 2")
    #expect(reviewAccessibilityValue(zoomed: false, flash: nil, .en) == "Whole photo")
    #expect(reviewAccessibilityValue(zoomed: true, flash: .keep, .en) == "Zoomed to 100%, Kept")
}

// MARK: zoom

@Test func zoomTargetIsTheLargestMainFaceElseTheCentre() throws {
    #expect(ZoomMath.target(faces: nil) == .centre)
    #expect(ZoomMath.target(faces: []) == .centre)
    let small = try box(0.1, 0.1, 0.1, 0.1), large = try box(0.6, 0.2, 0.2, 0.2)
    #expect(near(ZoomMath.target(faces: [small, large]), 0.7, 0.3))
    // A face marked as not main is not the target while a main face exists.
    let background = try box(0.0, 0.0, 0.4, 0.4, main: false), main = try box(0.5, 0.5, 0.1, 0.1, main: true)
    #expect(near(ZoomMath.target(faces: [background, main]), 0.55, 0.55))
}

@Test func fitAndActualPixels() {
    let fit = ZoomMath.fit(ratio: 1.5, in: ZoomSize(width: 1200, height: 600))
    #expect(fit == ZoomSize(width: 900, height: 600))
    #expect(ZoomMath.fit(ratio: 1.5, in: ZoomSize(width: 600, height: 1200)) == ZoomSize(width: 600, height: 400))
    // 6000 px wide on a Retina screen: 3000 pt at 100%, the fitted photo is 900 pt.
    #expect(abs(ZoomMath.actualPixelsFactor(pixelWidth: 6000, fittedWidth: 900, displayScale: 2) - 3000.0 / 900) < 1e-9)
    // A small photo is never zoomed below its fitted size.
    #expect(ZoomMath.actualPixelsFactor(pixelWidth: 800, fittedWidth: 900, displayScale: 2) == 1)
    #expect(ZoomMath.actualPixelsFactor(pixelWidth: 0, fittedWidth: 900, displayScale: 2) == 1)
}

@Test func zoomOffsetClampsAtTheEdges() {
    let view = ZoomSize(width: 1000, height: 500), content = ZoomSize(width: 4000, height: 2000)
    #expect(ZoomMath.offset(centre: .centre, content: content, view: view) == ZoomSize(width: 0, height: 0))
    // A face in the top-left corner: the photo's corner stays at the view's corner, no empty band.
    let o = ZoomMath.offset(centre: ZoomPoint(x: 0, y: 0), content: content, view: view)
    #expect(o == ZoomSize(width: 1500, height: 750))
    // An axis where the photo is not larger than the view stays centred.
    let narrow = ZoomMath.clamp(ZoomPoint(x: 0.9, y: 0.1), content: ZoomSize(width: 800, height: 2000), view: view)
    #expect(near(narrow, 0.5, 0.125))
}

@Test func dragMovesThePhotoWithThePointer() {
    let view = ZoomSize(width: 1000, height: 500), content = ZoomSize(width: 4000, height: 2000)
    // Dragging right by 400 pt shows what is left of the centre.
    let p = ZoomMath.pan(.centre, by: ZoomSize(width: 400, height: 0), content: content, view: view)
    #expect(near(p, 0.4, 0.5))
    // Far beyond the edge stops at the edge.
    let edge = ZoomMath.pan(.centre, by: ZoomSize(width: 99_999, height: -99_999), content: content, view: view)
    #expect(near(edge, 0.125, 0.875))
}

// MARK: compare

@Test func compareCyclesTheChallengerAndSkipsTheKeeper() {
    var s = CompareSession(frames: [1, 2, 3, 4], keeper: 2)
    #expect(s.keeper == 2 && s.challenger == 3 && s.others == [1, 3, 4] && s.position == (2, 3))
    s.next(); #expect(s.challenger == 4)
    s.next(); #expect(s.challenger == 1)       // wraps, never shows the keeper against itself
    s.previous(); #expect(s.challenger == 4)
    s.previous(); s.previous(); #expect(s.challenger == 1)
}

@Test func comparePickKeepsTheWinnerAndBringsTheNextFrame() {
    var s = CompareSession(frames: [1, 2, 3], keeper: 1, challenger: 2)
    #expect(s.pick(1) == 1 && s.keeper == 1 && s.challenger == 3)
    #expect(s.pick(2) == 3 && s.keeper == 3 && s.challenger == 1)
    #expect(s.pick(5) == nil && s.keeper == 3)
    var two = CompareSession(frames: [7, 8], keeper: 7)
    #expect(two.pick(2) == 8 && two.challenger == 7)
    #expect(two.pick(1) == 8 && two.challenger == 7)
}

@Test func compareStartsSafelyFromAnyInput() {
    let unknownKeeper = CompareSession(frames: [5, 6, 6], keeper: 9)
    #expect(unknownKeeper.frames == [5, 6] && unknownKeeper.keeper == 5 && unknownKeeper.challenger == 6)
    var single = CompareSession(frames: [5], keeper: 5)
    #expect(single.challenger == nil && single.pick(2) == nil && single.pick(1) == 5)
    let chosen = CompareSession(frames: [1, 2, 3], keeper: 1, challenger: 3)
    #expect(chosen.challenger == 3)
}
