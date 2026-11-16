import Foundation
import Testing
@testable import CuratorCore

func demo() throws -> Timeline { try JSONDecoder().decode(Timeline.self, from: fixture("timeline")) }

@Test func leftOutHiddenFromAllButShownInLeftOut() throws {
    let t = try demo()
    let all = sections(t.items, events: t.events, filter: .all, sort: .time).flatMap(\.photos).map(\.id)
    #expect(all == [1, 2])
    let left = sections(t.items, events: t.events, filter: .leftOut, sort: .time).flatMap(\.photos).map(\.id)
    #expect(left == [3])
    #expect(sections(t.items, events: t.events, filter: .favourites, sort: .time).flatMap(\.photos).map(\.id) == [1])
    #expect(sections(t.items, events: t.events, filter: .videos, sort: .time).flatMap(\.photos).map(\.id) == [2])
    #expect(sections(t.items, events: t.events, filter: .ids([2, 1]), sort: .time).flatMap(\.photos).map(\.id) == [2, 1])
}

@Test func sectionsByEventUndatedLast() throws {
    let t = try demo()
    let s = sections(t.items, events: t.events, filter: .everything, sort: .time)
    #expect(s.map(\.day) == ["2026-10-23", Photo.undated])
    #expect(s[0].eventName == "Evening" && s[0].photos.count == 2)
    #expect(s.last?.photos.map(\.id) == [3])
}

@Test func sortByPersonGroupsPerOwner() throws {
    let t = try demo()
    let s = sections(t.items, events: t.events, filter: .everything, sort: .person)
    #expect(s.map(\.title) == ["Me", "Partner"])
}

@Test func cursorStaysInBounds() {
    // Two sections: 5 photos and 2 photos, 3 columns.
    let sizes = [5, 2]
    #expect(moveCursor(0, .left, columns: 3, sectionSizes: sizes) == 0)
    #expect(moveCursor(6, .right, columns: 3, sectionSizes: sizes) == 6)
    #expect(moveCursor(1, .down, columns: 3, sectionSizes: sizes) == 4)        // into the short last row
    #expect(moveCursor(2, .down, columns: 3, sectionSizes: sizes) == 4)        // column 2 has no photo below: clamp
    #expect(moveCursor(4, .down, columns: 3, sectionSizes: sizes) == 6)        // next section, same column clamped
    #expect(moveCursor(5, .up, columns: 3, sectionSizes: sizes) == 3)          // previous section, last row, column 0
    #expect(moveCursor(6, .down, columns: 3, sectionSizes: sizes) == 6)
    #expect(moveCursor(0, .up, columns: 3, sectionSizes: sizes) == 0)
    #expect(moveCursor(-1, .right, columns: 3, sectionSizes: sizes) == 0)       // no cursor yet: first photo
}

@Test func rangeSelectInclusive() {
    let ids = [10, 11, 12, 13]
    #expect(rangeSelect(from: 1, to: 3, in: ids) == [11, 12, 13])
    #expect(rangeSelect(from: 3, to: 1, in: ids) == [11, 12, 13])
    #expect(rangeSelect(from: 2, to: 9, in: ids) == [12, 13])
}
