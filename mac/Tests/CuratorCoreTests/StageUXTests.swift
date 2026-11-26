import Foundation
import Testing
@testable import CuratorCore

private func photo(_ id: Int, _ extra: String = "") throws -> Photo {
    let sep = extra.isEmpty ? "" : ", "
    return try JSONDecoder().decode(Photo.self, from: Data(#"{"id": \#(id), "filename": "p\#(id).jpg", "path": "/x/p\#(id).jpg", "kind": "image", "owner": "Ana", "local_time": "2026-10-23T17:48:00"\#(sep)\#(extra)}"#.utf8))
}

private let sharp = #""focus": {"tier": "sharp", "auto_tier": "sharp"}"#
private let blurry = #""focus": {"tier": "blurry", "auto_tier": "blurry"}"#

@Test func choreographyLimitKeepsSmallAlbumsAnimated() {
    #expect(stageAnimatesEachPhoto(236))
    #expect(stageAnimatesEachPhoto(stageChoreographyLimit))
    #expect(!stageAnimatesEachPhoto(stageChoreographyLimit + 1))
    #expect(!stageAnimatesEachPhoto(5000))
}

@Test func stageStateRunningFailedStoppedDone() throws {
    let done = [try photo(1, sharp), try photo(2, blurry)]
    let half = [try photo(1, sharp), try photo(2)]
    let idle = JobStatus(running: false, status: "")
    #expect(stageState(job: JobStatus(running: true, collection: "t", status: "Faces (1/9)"), analysing: true, trip: "t", photos: half) == .running)
    #expect(stageState(job: idle, analysing: false, trip: "t", photos: []) == .waiting)
    #expect(stageState(job: idle, analysing: false, trip: "t", photos: done) == .done)
    // Stopped by the owner, or no job since the engine started: photos without results are still to analyse.
    #expect(stageState(job: JobStatus(running: false, collection: "t", status: "Cancelled"), analysing: false, trip: "t", photos: half) == .stopped(remaining: 1))
    #expect(stageState(job: idle, analysing: false, trip: "t", photos: half) == .stopped(remaining: 1))
    // A finished job: a photo without results is a file the engine could not read, not a stop.
    #expect(stageState(job: JobStatus(running: false, collection: "t", status: "Done in 12 s"), analysing: false, trip: "t", photos: half) == .done)
    // Another album's cancelled job says nothing about this one.
    #expect(stageState(job: JobStatus(running: false, collection: "other", status: "Cancelled"), analysing: false, trip: "t", photos: half) == .done)
    let failed = JobStatus(running: false, collection: "t", status: "Error: disk full", error: "disk full\nTraceback …")
    #expect(stageState(job: failed, analysing: false, trip: "t", photos: half) == .failed(reason: "disk full"))
    #expect(stageState(job: failed, analysing: false, trip: "other", photos: half) != .failed(reason: "disk full"))
    #expect(StageState.failed(reason: "").needsRestart && StageState.stopped(remaining: 2).needsRestart)
    #expect(!StageState.done.needsRestart && !StageState.running.needsRestart)
}

@Test func failureReasonDropsPrefixAndExtraLines() {
    #expect(failureReason(JobStatus(running: false, status: "Error: boom")) == "boom")
    #expect(failureReason(JobStatus(running: false, status: "x", error: "first line\nsecond")) == "first line")
}

@Test func stageStateTextsInBothLanguages() {
    let en = stageStateTexts(.stopped(remaining: 3), .en)
    #expect(en?.title == "Sorting stopped")
    #expect(en?.subtitle == "Not analysed yet: 3 photos. Resume to finish sorting.")
    #expect(stageStateTexts(.stopped(remaining: 2), .sl)?.subtitle.contains("2 fotografiji") == true)
    let failed = stageStateTexts(.failed(reason: "disk full"), .en)
    #expect(failed?.title == "Sorting stopped because of an error")
    #expect(failed?.subtitle.hasPrefix("disk full · ") == true)
    #expect(stageStateTexts(.done, .en) == nil && stageStateTexts(.running, .sl) == nil)
}

@Test func stageTileLabelSaysVerdictReasonAndStack() throws {
    let moved = try photo(1, blurry + #", "quality": {"blur": "blurry", "blur_reason": "movement", "reasons": ["movement_blur"]}"#)
    #expect(stageTileAccessibilityLabel(moved, verdict: .removed, stacked: 0, .en) == "p1.jpg, Left out, Blurred by movement")
    #expect(stageTileAccessibilityLabel(moved, verdict: .removed, stacked: 0, .sl) == "p1.jpg, Izpuščeno, Zamegljeno zaradi premika")
    let kept = try photo(2, sharp)
    #expect(stageTileAccessibilityLabel(kept, verdict: .album, stacked: 2, .en) == "p2.jpg, In album, Stacked behind it: 2 photos")
    #expect(stageTileAccessibilityLabel(kept, verdict: nil, stacked: 0, .en) == "p2.jpg, Not sorted yet")
    let out = try photo(3, sharp + #", "rejected": true"#)
    #expect(stageTileAccessibilityLabel(out, verdict: .removed, stacked: 0, .en) == "p3.jpg, Left out, You left it out")
}

@Test func gridTileLabelNamesEveryBadge() throws {
    let p = try photo(4, blurry + #", "faces": {"faces": 2, "eyes_closed": 1, "looking_away": 0}, "duplicate": {"group": 1, "category": "near", "keeper": false}"#)
    let label = gridTileAccessibilityLabel(p, .en)
    #expect(label.hasPrefix("p4.jpg, 17:48, Ana"))
    #expect(label.contains("Not in album") && label.contains("Blurry"))
    #expect(label.contains("Eyes may be closed") && label.contains("Another frame of this moment is kept"))
    #expect(gridTileAccessibilityLabel(try photo(5, sharp), .en) == "p5.jpg, 17:48, Ana")
    #expect(gridTileAccessibilityLabel(try photo(6, sharp + #", "rejected": true"#), .sl).contains("Izpuščene"))
}

@Test func undoToastTexts() {
    #expect(undoToastText(.putBack, count: 3, .en) == "Put back 3 photos")
    #expect(undoToastText(.putBack, count: 1, .sl) == "Vrnjeno v album: 1 fotografija")
    #expect(undoToastText(.leaveOut, count: 1, .en) == "Left out 1 photo")
    #expect(undoToastText(.keptInAlbum, count: 2, .sl) == "Ostane v albumu: 2 fotografiji")
}
