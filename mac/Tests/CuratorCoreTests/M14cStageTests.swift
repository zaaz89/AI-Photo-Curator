import CoreGraphics
import Foundation
import Testing
@testable import CuratorCore

// M14c: one analysis status, chips that tell folders apart, a flow that never runs over the trays.

private func job(_ json: String) throws -> JobStatus {
    try JSONDecoder().decode(JobStatus.self, from: Data(json.utf8))
}

@Test func jobStatusCarriesThePhasePlan() throws {
    let j = try job(#"{"running": true, "collection": "t", "kind": "analysis", "status": "Day 3 of 7: Focus and ranking scores (12/40)", "progress": 61, "stage": {"phase": "days", "step": "focus", "day": 3, "days": 7, "source": 3, "sources": 3, "source_id": null, "done": 12, "total": 40, "progress": 61}}"#)
    let s = try #require(analysisStatus(j))
    #expect(s.phase == .days && s.step == "focus" && s.day == 3 && s.days == 7 && s.done == 12 && s.total == 40)
    #expect(abs(s.fraction - 0.61) < 0.001)
    #expect(analysisTitle(s, .en) == "Sorting day 3 of 7")
    #expect(analysisTitle(s, .sl) == "Razvrščam 3. dan od 7")
    #expect(analysisDetail(s, .en) == "checking focus · 12 / 40")
    // The pill and the header read the same words and the same value.
    #expect(activityTitle(j, .en) == analysisTitle(s, .en))
    #expect(abs(activityFraction(j) - 0.61) < 0.001)
}

@Test func phaseTitlesInTheOwnersWords() {
    let t = { (p: AnalysisPhase, step: String?) in analysisTitle(AnalysisStatus(phase: p, step: step, day: 2, days: 7), .en) }
    #expect(t(.reading, nil) == "Reading photos")
    #expect(t(.clocks, nil) == "Aligning cameras")
    #expect(t(.places, nil) == "Finding places")
    #expect(t(.days, "moments") == "Comparing similar shots")
    #expect(analysisDetail(AnalysisStatus(phase: .days, step: "moments", day: 2, days: 7), .en) == "Day 2 of 7")
    #expect(analysisTitle(AnalysisStatus(phase: .clocks, paused: true), .en) == Strings.text("phase_paused", .en))
}

@Test func olderEngineStatusTextStillMaps() throws {
    let j = try job(#"{"running": true, "collection": "t", "status": "Day 2 of 5: Faces (Apple Vision) (8/20)", "progress": 40}"#)
    let s = try #require(analysisStatus(j))
    #expect(s.phase == .days && s.day == 2 && s.days == 5 && s.step == "faces" && s.done == 8)
    let clocks = try job(#"{"running": true, "collection": "t", "status": "Resolving capture times", "progress": 100}"#)
    #expect(analysisStatus(clocks)?.phase == .clocks)
    #expect(analysisStatus(JobStatus(running: false, status: "Done")) == nil)
    #expect(analysisStatus(JobStatus(running: true, status: "Copying and verifying", kind: "export")) == nil)
}

@Test func pillStepsAsideOnTheAnalysisStation() {
    #expect(!showsActivityPill(analysingShownAlbum: true, stageOnScreen: true))
    #expect(showsActivityPill(analysingShownAlbum: true, stageOnScreen: false))
    #expect(showsActivityPill(analysingShownAlbum: false, stageOnScreen: true))
}

@Test func photosReloadWhenTimesBecomeKnown() {
    #expect(reloadsPhotos(from: .reading, to: .clocks))
    #expect(reloadsPhotos(from: .clocks, to: .places))
    #expect(reloadsPhotos(from: .places, to: .days))
    #expect(reloadsPhotos(from: nil, to: .days))
    #expect(!reloadsPhotos(from: .days, to: .days))
    #expect(!reloadsPhotos(from: .reading, to: .reading))
    #expect(!reloadsPhotos(from: .days, to: .finishing))
    #expect(!reloadsPhotos(from: .days, to: nil))
}

@Test func theTileBeingAnalysed() {
    let days = analysisDayOrder(["2026-10-24", Photo.undated, "2026-10-22", "2026-10-24"])
    #expect(days == ["2026-10-22", "2026-10-24", Photo.undated])
    let s = AnalysisStatus(phase: .days, step: "focus", day: 2, days: 3, done: 5, total: 10)
    #expect(currentAnalysisDay(s, days: days) == "2026-10-24")
    #expect(analysedIndex(s, photosInDay: 30) == 15)
    #expect(analysedIndex(AnalysisStatus(phase: .days, step: "moments", day: 2, days: 3), photosInDay: 30) == nil)
    #expect(currentAnalysisDay(AnalysisStatus(phase: .places), days: days) == nil)
}

@Test func sourcesDecodeChipAndState() throws {
    let json = #"{"sources": [{"id": 1, "owner": "Jarek Pawlak", "path": "/t/Ceremony", "assets": 212, "devices": ["Sony A7 IV"], "chip": "Jarek Pawlak · Ceremony", "read_state": {"state": "read", "done": 212, "total": 212}}, {"id": 3, "owner": "Toskana 2026", "path": "/t/Toskana 2026", "assets": 0, "devices": [], "chip": "Toskana 2026", "read_state": {"state": "reading", "done": 12, "total": 80}}]}"#
    struct Wrap: Decodable { let sources: [SourceInfo] }
    let src = try JSONDecoder().decode(Wrap.self, from: Data(json.utf8)).sources
    #expect(sourceChipName(src[0], among: src) == "Jarek Pawlak · Ceremony")
    #expect(sourceChipDetail(src[1], arrived: 0, shown: 0, .en) == "Reading 12 of 80")
    #expect(sourceChipDetail(src[0], arrived: 100, shown: 212, .en) == "100/212")
}

@Test func chipStatesAreNeverABareEllipsis() {
    func s(_ state: String?, reason: String? = nil, assets: Int = 0) -> SourceInfo {
        SourceInfo(id: 1, owner: "Ana", path: "/x/Rome", assets: assets, devices: nil,
                   readState: state.map { SourceReadState(state: $0, reason: reason) })
    }
    #expect(sourceChipDetail(s("waiting"), arrived: 0, shown: 0, .en) == "Waiting")
    #expect(sourceChipDetail(s("empty"), arrived: 0, shown: 0, .en) == "No photos found")
    #expect(sourceChipDetail(s("failed", reason: "folder not found"), arrived: 0, shown: 0, .en) == "Couldn't read: folder not found")
    #expect(sourceChipDetail(s("failed", reason: "folder not found"), arrived: 0, shown: 0, .sl) == "Ni prebrano: mape ni")
    #expect(sourceChipDetail(s(nil), arrived: 0, shown: 0, .en) == "Waiting")
    for lang in [Lang.en, .sl] {
        for st in ["waiting", "reading", "read", "empty", "failed"] {
            #expect(!sourceChipDetail(s(st), arrived: 0, shown: 0, lang).contains("…") || st == "reading")
        }
    }
}

@Test func chipNamesFromAnOlderEngineAreStillDistinct() {
    let a = SourceInfo(id: 1, owner: "Jarek Pawlak", path: "/t/Ceremony", devices: ["ILCE-7M4"])
    let b = SourceInfo(id: 2, owner: "Jarek Pawlak", path: "/t/Portraits", devices: ["ILCE-7M4"])
    let c = SourceInfo(id: 3, owner: "Ana", path: "/t/Phone", devices: ["iPhone 15"])
    let names = [a, b, c].map { sourceChipName($0, among: [a, b, c]) }
    #expect(Set(names).count == 3)
    #expect(names[0] == "Jarek Pawlak · Ceremony" && names[2] == "Ana · iPhone 15")
}

@Test func flowSaysWhenItDoesNotFit() {
    let rect = CGRect(x: 250, y: 150, width: 884, height: 420)
    let many = stageFlow((0..<400).map { StageItem(id: $0, day: "d\($0 / 60)", aspect: 1.5) }, in: rect, maxHeight: 170)
    #expect(!many.fits && many.height > rect.height)
    let some = stageFlow((0..<120).map { StageItem(id: $0, day: "d\($0 / 20)", aspect: 1.5) }, in: rect, maxHeight: 170)
    #expect(some.fits && some.height <= rect.height + 0.5)
    for r in some.slots.values { #expect(r.maxY <= rect.maxY + 0.5 && r.minY >= rect.minY - 0.01) }
}

@Test func onlyRowsWhereADayBeginsCarryALabel() {
    // One day over three rows: the label band is paid once, so the second row starts right under the first.
    let rect = CGRect(x: 0, y: 0, width: 300, height: 2000)
    let f = stageFlow((0..<9).map { StageItem(id: $0, day: "d", aspect: 1) }, in: rect, maxHeight: 90)
    #expect(f.fits && f.tileHeight == 90 && f.days.count == 1)
    let first = f.slots[0]!, below = f.slots.values.filter { $0.minY > first.minY }.map(\.minY).min()!
    #expect(first.minY == 24)
    #expect(below - first.maxY <= 12 + 0.01)
}
