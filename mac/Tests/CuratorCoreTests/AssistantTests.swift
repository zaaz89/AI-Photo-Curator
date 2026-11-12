import Foundation
import Testing
@testable import CuratorCore

@Test func albumNameFromPlaceAndDates() {
    #expect(albumName(place: "Tuscany", start: "2026-10-23", end: "2026-10-28", lang: .en) == "Tuscany, 23–28 Oct 2026")
    #expect(albumName(place: "Toskana", start: "2026-10-23", end: "2026-10-28", lang: .sl) == "Toskana, 23.–28. okt. 2026")
    #expect(albumName(place: nil, start: "2026-10-30", end: "2026-11-02", lang: .en) == "30 Oct – 2 Nov 2026")
    #expect(albumName(place: "Bled", start: "2026-06-01", end: "2026-06-01", lang: .en) == "Bled, 1 Jun 2026")
    #expect(albumName(place: nil, start: nil, end: nil, lang: .en) == "")
}

@Test func blurryFilter() throws {
    let t = try JSONDecoder().decode(Timeline.self, from: fixture("timeline"))
    // Photo 1 is soft, not blurry: nothing in the fixture is blurry.
    #expect(sections(t.items, events: t.events, filter: .blurry, sort: .time).isEmpty)
    // The owner's own focus mark wins over the automatic one.
    var p = t.items[0]
    p.focus = try JSONDecoder().decode(Photo.Focus.self, from: Data(#"{"tier": "sharp", "auto_tier": "blurry", "override": "sharp"}"#.utf8))
    #expect(sections([p], events: [], filter: .blurry, sort: .time).isEmpty)
}

@Test func devicesAreRememberedOnlyWhenTheyClearlyBelongToOneFolder() {
    let r = devicesToRemember([
        (owner: "Me", devices: [("Apple iPhone 15", 30), ("SONY ILCE-7M4", 2)]),
        (owner: "Partner", devices: [("Apple iPhone 16 Pro", 25), ("Apple iPhone 15", 3)]),
        (owner: "Ana", devices: [("Pixel 8", 10), ("Pixel 9", 10)]),
    ])
    // iPhone 15 is in two folders; the Sony is a few AirDropped photos; Pixel 8 is exactly half: kept.
    #expect(r == ["Apple iPhone 16 Pro": "Partner", "Pixel 8": "Ana", "Pixel 9": "Ana"])
}

@Test func decodesOverview() throws {
    let json = #"""
    {"analysing": false, "facts": {"photos": 3, "videos": 0, "people": 1, "days": 1, "places": ["Pienza"], "start": "2026-10-24", "end": "2026-10-24"},
      "clocks": {"devices": 2, "pending": 1, "applied": 0}, "moments": {"total": 4, "decided": 3, "chosen": 0, "need_you": 1},
      "blurry": {"total": 1, "left_out": 0, "kept_favourites": 0}, "events": {"events": 2, "days": 1},
      "descriptions": {"done": 0, "photos": 3, "minutes_left": 1}, "export": {"done": false, "photos": 3}}
    """#
    let o = try JSONDecoder().decode(Overview.self, from: Data(json.utf8))
    #expect(o.moments.needYou == 1 && o.clocks.pending == 1 && o.facts.places == ["Pienza"] && !o.export.done)
}
