import Foundation
import Testing
@testable import CuratorCore

private func overview(analysing: Bool = false, pendingClocks: Int = 0, needYou: Int = 0, described: Int = 0, photos: Int = 10,
                      exported: Bool = false, funnel: String = "") throws -> Overview {
    let json = """
    {"analysing": \(analysing),
     "facts": {"photos": \(photos), "videos": 0, "people": 2, "days": 1, "places": [], "start": null, "end": null},
     "clocks": {"devices": 2, "pending": \(pendingClocks), "applied": 0},
     "moments": {"total": 5, "decided": \(5 - needYou), "chosen": 0, "need_you": \(needYou)},
     "blurry": {"total": 1, "left_out": 1, "kept_favourites": 0},
     "events": {"events": 2, "days": 1},
     "descriptions": {"done": \(described), "photos": \(photos), "minutes_left": 3},
     "export": {"done": \(exported), "photos": 7}\(funnel)}
    """
    return try JSONDecoder().decode(Overview.self, from: Data(json.utf8))
}

@Test func overviewDecodesSortedDays() throws {
    // M14a: the days of the album and how many are sorted; an older engine without the field still decodes.
    let o = try overview(funnel: #", "analysis": {"days": 7, "settled": 3}"#)
    #expect(o.analysis == Overview.Analysis(days: 7, settled: 3))
    #expect(try overview().analysis == nil)
}

@Test func funnelDecodesAndDropsEmptyParts() throws {
    let o = try overview(funnel: #", "funnel": {"taken": 10, "left_out": 0, "blurry": 1, "extra_frames": 2, "in_album": 7}, "cover_id": 3, "highlights": [3, 5], "people": [{"owner": "Me", "source_id": 1, "taken": 9, "in_album": 6}]"#)
    let f = try #require(o.funnel)
    #expect(f.taken == f.leftOut + f.blurry + f.extraFrames + f.inAlbum)
    #expect(funnelParts(f).map(\.kind) == [.inAlbum, .extraFrames, .blurry])
    #expect(o.coverId == 3 && o.highlights == [3, 5] && o.people?.first?.inAlbum == 6)
    // An engine without the M9 fields still decodes.
    #expect(try overview().funnel == nil)
    #expect(f.screenshots == 0)                                          // older engine: no screenshots part
}

@Test func funnelShowsScreenshots() throws {
    let o = try overview(funnel: #", "funnel": {"taken": 10, "left_out": 1, "screenshots": 2, "blurry": 1, "extra_frames": 2, "in_album": 4}"#)
    let f = try #require(o.funnel)
    #expect(f.taken == f.leftOut + f.screenshots + f.blurry + f.extraFrames + f.inAlbum)
    #expect(funnelParts(f).map(\.kind) == [.inAlbum, .extraFrames, .blurry, .screenshots, .leftOut])
}

@Test func chaptersGroupByDayUndatedLast() throws {
    let events = try JSONDecoder().decode([TripEvent].self, from: Data("""
    [{"id": 3, "day": "unknown", "name": "No date", "count": 1},
     {"id": 2, "day": "2026-10-24", "name": "Siena", "count": 4},
     {"id": 1, "day": "2026-10-23", "name": "Pienza", "count": 5},
     {"id": 4, "day": "2026-10-23", "name": "Dinner", "count": 2}]
    """.utf8))
    let days = chaptersByDay(events)
    #expect(days.map(\.day) == ["2026-10-23", "2026-10-24", "unknown"])
    #expect(days[0].chapters.map(\.id) == [1, 4])
}

@Test func timelinePositionsAndShifts() {
    let a = parseLocalTime("2026-10-23T10:00:00")!, b = parseLocalTime("2026-10-23T12:00:00")!
    #expect(timelinePosition("2026-10-23T11:00:00", start: a, end: b) == 0.5)
    #expect(timelinePosition("2026-10-23 09:00:00.120", start: a, end: b) == 0)
    #expect(timelinePosition(nil, start: a, end: b) == nil)
    #expect(shiftText(42) == "+42 s" && shiftText(-90) == "−1.5 min" && shiftText(7500) == "+2 h 05 min")
    #expect(initials("Ana Novak") == "AN" && initials("Žaž") == "Ž" && initials("") == "?")
}

@Test func exportChoicesMapToEngineOptions() {
    var c = ExportChoice()
    #expect(c.body["preset"] as? String == "google_photos")
    c.kind = .best; c.bestCount = 40
    #expect(c.body["selection"] as? String == "best" && c.body["topn"] as? Int == 40)
    c.kind = .archive; c.folders = "place"
    #expect(c.body["folders"] as? String == "place" && c.body["selection"] as? String == "no_blurry")
}

@Test func faceBoxesDecode() throws {
    let f = try JSONDecoder().decode(Photo.Faces.self, from: Data(#"""
    {"faces": 1, "eyes_closed": 1, "looking_away": 0, "score": 0.81,
     "boxes": [{"x": 0.2, "y": 0.2, "w": 0.2, "h": 0.3, "eyes_closed": true, "looking_away": false}]}
    """#.utf8))
    #expect(f.boxes?.first?.eyesClosed == true && f.boxes?.first?.h == 0.3)
}

@Test func blurryPhotoGoesToTheAlbumOnlyWhenTheOwnerKeepsIt() throws {
    func photo(_ extra: String) throws -> Photo {
        try JSONDecoder().decode(Photo.self, from: Data(#"{"id": 1, "filename": "a.jpg", "path": "/x/a.jpg", "kind": "image", \#(extra)}"#.utf8))
    }
    let blurry = try photo(#""focus": {"tier": "blurry", "auto_tier": "blurry"}"#)
    #expect(blurry.foundBlurry && !blurry.goesToAlbumDespiteFocus)          // not rejected, still not exported
    let kept = try photo(#""focus": {"tier": "soft", "auto_tier": "blurry", "override": "soft"}"#)
    #expect(kept.foundBlurry && kept.goesToAlbumDespiteFocus)
    #expect(try photo(#""favorite": true, "focus": {"tier": "blurry", "auto_tier": "blurry"}"#).goesToAlbumDespiteFocus)
    #expect(!(try photo(#""rejected": true, "focus": {"tier": "soft", "auto_tier": "blurry", "override": "soft"}"#)).goesToAlbumDespiteFocus)
    #expect(blurry.focus?.overridden("soft").tier == "soft" && blurry.focus?.overridden(nil).tier == "blurry")
    // A sharp-enough extra frame of a moment stays out unless it is a favourite (keep too).
    let extra = try photo(#""focus": {"tier": "soft", "auto_tier": "blurry", "override": "soft"}, "duplicate": {"group": 3, "category": "near", "keeper": false}"#)
    #expect(extra.isExtraFrame && !extra.goesToAlbumDespiteFocus)
    #expect(try photo(#""favorite": true, "duplicate": {"group": 3, "category": "near", "keeper": false}"#).goesToAlbumDespiteFocus)
}

@Test func firstSearchAnswersPreparing() throws {
    let r = try JSONDecoder().decode(SearchResult.self, from: Data(#"{"preparing": true, "missing": 19, "query": "ring", "results": []}"#.utf8))
    #expect(r.preparing == true && r.results.isEmpty && r.query == "ring")
    let done = try JSONDecoder().decode(SearchResult.self, from: Data(#"{"query": "ring", "english": null, "results": [{"id": 3}], "note": null}"#.utf8))
    #expect(done.preparing == nil && done.results.map(\.id) == [3])
}
