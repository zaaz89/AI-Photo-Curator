import CoreGraphics
import Foundation
import Testing
@testable import CuratorCore

private func photo(_ id: Int, _ extra: String = "") throws -> Photo {
    let sep = extra.isEmpty ? "" : ", "
    return try JSONDecoder().decode(Photo.self, from: Data(#"{"id": \#(id), "filename": "p\#(id).jpg", "path": "/x/p\#(id).jpg", "kind": "image"\#(sep)\#(extra)}"#.utf8))
}

private let sharp = #""focus": {"tier": "sharp", "auto_tier": "sharp"}"#
private let blurry = #""focus": {"tier": "blurry", "auto_tier": "blurry"}"#

@Test func verdictsFollowTheExportRule() throws {
    #expect(sortVerdict(try photo(1, sharp)) == .album)
    #expect(sortVerdict(try photo(2, blurry)) == .removed)
    #expect(sortVerdict(try photo(3, sharp + #", "rejected": true"#)) == .removed)
    let extra = #", "duplicate": {"group": 4, "category": "near", "keeper": false}"#
    #expect(sortVerdict(try photo(4, sharp + extra)) == .stacked)
    #expect(sortVerdict(try photo(5, blurry + extra)) == .removed)            // blurry wins over "another frame"
    #expect(sortVerdict(try photo(6, sharp + extra + #", "keep": true"#)) == .album)   // keep too: back in the album
    #expect(sortVerdict(try photo(7, blurry + #", "favorite": true"#)) == .album)
    // A blurry photo the owner kept (focus mark "soft") is in the album.
    #expect(sortVerdict(try photo(8, #""focus": {"tier": "soft", "auto_tier": "blurry", "override": "soft"}"#)) == .album)
    let screenshot = sharp + #", "quality": {"utility": true, "reasons": ["utility_image"]}"#
    #expect(sortVerdict(try photo(9, screenshot)) == .check)
    #expect(sortReason(try photo(9, screenshot)) == "utility_image")
    #expect(sortVerdict(try photo(10, screenshot + #", "favorite": true"#)) == .album)
    let unsure = sharp + #", "quality": {"reasons": ["eyes_unsure"]}"#
    #expect(sortVerdict(try photo(11, unsure)) == .album)                    // "can't tell" is no reason to ask
}

@Test func reasonsForRemovedPhotos() throws {
    #expect(sortReason(try photo(1, sharp + #", "rejected": true"#)) == "leftOut")
    #expect(sortReason(try photo(2, blurry + #", "quality": {"blur": "blurry", "blur_reason": "movement", "reasons": ["movement_blur"]}"#)) == "movement_blur")
    #expect(sortReason(try photo(3, blurry)) == "whole_blurry")
    #expect(sortReason(try photo(4, sharp)) == nil)
    let none = try photo(5), scored = try photo(6, sharp)
    #expect(!hasResults(none))
    #expect(hasResults(scored))
}

@Test func flowFitsAndKeepsDaysInOrder() {
    let items = (0..<40).map { StageItem(id: $0, day: $0 < 25 ? "2026-10-23" : ($0 < 32 ? "2026-10-24" : "2026-10-28"),
                                         aspect: $0 % 3 == 0 ? 0.75 : 1.5) }
    let rect = CGRect(x: 100, y: 50, width: 900, height: 420)
    let f = stageFlow(items, in: rect, maxHeight: 200)
    #expect(f.slots.count == 40)
    #expect(f.height <= rect.height + 0.5 && f.tileHeight < 200)
    for s in f.slots.values { #expect(s.minX >= rect.minX - 0.01 && s.maxX <= rect.maxX + 0.01 && s.minY >= rect.minY) }
    let rects = Array(f.slots.values)
    for i in rects.indices { for j in rects.indices where j > i { #expect(!rects[i].insetBy(dx: 0.5, dy: 0.5).intersects(rects[j])) } }
    #expect(f.days.map(\.day) == ["2026-10-23", "2026-10-24", "2026-10-28"])
    // A day starts where its label is.
    #expect(abs(f.days[1].origin.x - f.slots[25]!.minX) < 0.01)
}

@Test func flowUsesTheLargestHeightAndGrowsWhenFew() {
    let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let few = stageFlow([StageItem(id: 1, day: "d", aspect: 1.5)], in: rect, maxHeight: 220)
    #expect(few.tileHeight == 220)
    let many = stageFlow((0..<300).map { StageItem(id: $0, day: "d\($0 / 40)", aspect: 1.33) }, in: rect, maxHeight: 220)
    #expect(many.tileHeight < 60 && many.tileHeight >= 28)
    // Even a panorama never sticks out of the stage.
    let wide = stageFlow([StageItem(id: 1, day: "d", aspect: 9)], in: CGRect(x: 0, y: 0, width: 300, height: 600), maxHeight: 220)
    #expect(wide.slots[1]!.width <= 300)
    #expect(stageFlow([], in: rect, maxHeight: 200).slots.isEmpty)
}

@Test func staggerKeepsAnActNearItsLength() {
    #expect(stagger(10, total: 3) == 0.12)
    #expect(abs(stagger(300, total: 3) - 0.012) < 0.0001)
    #expect(abs(stagger(50, total: 3) - 0.06) < 0.0001)
    #expect(stagger(0, total: 3) == 0)
}

@Test func putBackBringsEveryRemovedOrStackedPhotoIntoTheAlbum() throws {
    let extra = #", "duplicate": {"group": 4, "category": "near", "keeper": false}"#
    let cases = [try photo(1, blurry), try photo(2, sharp + extra), try photo(3, blurry + extra),
                 try photo(4, sharp + #", "rejected": true"#), try photo(5, blurry + extra + #", "rejected": true"#)]
    for var p in cases {
        #expect(!p.goesToAlbumDespiteFocus)
        for (k, v) in putBackMarks(p) {
            switch (k, v) {
            case ("rejected", .bool(let b)): p.rejected = b
            case ("keep", .bool(let b)): p.keep = b
            case ("focus", .string(let t)): p.focus = p.focus?.overridden(t)
            default: Issue.record("unexpected mark \(k)")
            }
        }
        #expect(p.goesToAlbumDespiteFocus, "photo \(p.id) is still out")
        #expect(sortVerdict(p) == .album || sortVerdict(p) == .check)
    }
    // A blurry extra frame needs both marks (the tray's "Put back" used to set only "keep too").
    #expect(putBackMarks(try photo(6, blurry + extra)) == ["rejected": .bool(false), "keep": .bool(true), "focus": .string("soft")])
}
