import Foundation
import Testing
@testable import CuratorCore

// M14c: Survey (selection, multi-keep, confirm, accept, undo, focus, ordering), reason chips, face columns, layout.

private func photo(_ id: Int, _ extra: String = "") throws -> Photo {
    let sep = extra.isEmpty ? "" : ", "
    return try JSONDecoder().decode(Photo.self, from: Data(#"{"id": \#(id), "filename": "p\#(id).jpg", "path": "/x/p\#(id).jpg", "kind": "image"\#(sep)\#(extra)}"#.utf8))
}

private func box(_ x: Double, _ y: Double, _ w: Double = 0.1, state: String? = nil, away: Bool? = nil) throws -> Photo.Faces.Box {
    var parts = [#""x": \#(x), "y": \#(y), "w": \#(w), "h": \#(w)"#]
    if let state { parts.append(#""state": "\#(state)""#) }
    if let away { parts.append(#""looking_away": \#(away)"#) }
    return try JSONDecoder().decode(Photo.Faces.Box.self, from: Data(("{" + parts.joined(separator: ", ") + "}").utf8))
}

private func moment(_ id: Int, _ frames: [Int], best: Int? = nil, margin: Double? = 0.08) -> SurveyMoment {
    SurveyMoment(id: id, frames: frames, recommended: best, margin: margin)
}

// MARK: moments and ordering

@Test func momentFromTheEngineAndConfidence() throws {
    let json = #"{"id": 7, "category": "near", "keeper_id": 12, "reasons": {"keeper": ["sharpest frame", "a recommendation, not a rule"], "margin": 0.03},
                 "members": [{"id": 11, "path": "/a"}, {"id": 12, "path": "/b"}, {"id": 12, "path": "/b"}]}"#
    let m = SurveyMoment(try JSONDecoder().decode(MomentGroup.self, from: Data(json.utf8)))
    #expect(m.frames == [11, 12] && m.recommended == 12 && m.reasons == ["sharpest frame"])
    #expect(m.confidence == .low && m.isCloseCall)
    #expect(SurveyConfidence(margin: 0.12) == .high && SurveyConfidence(margin: 0.07) == .medium && SurveyConfidence(margin: nil) == nil)
    // Unknown recommendation: the first frame; chosen by the owner: no confidence shown.
    #expect(SurveyMoment(id: 1, frames: [4, 5], recommended: 9).recommended == 4)
    #expect(SurveyMoment(id: 1, frames: [4, 5], recommended: 5, margin: 0.01, chosenByOwner: true).confidence == nil)
}

@Test func momentFromPhotos() throws {
    let a = try photo(1, #""duplicate": {"group": 3, "category": "near", "keeper": false}"#)
    let b = try photo(2, #""duplicate": {"group": 3, "category": "near", "keeper": true}"#)
    let c = try photo(3, #""duplicate": {"group": 4, "category": "near", "keeper": true}"#)
    let m = SurveyMoment.from(photos: [a, b, c], group: 3)
    #expect(m?.frames == [1, 2] && m?.recommended == 2 && m?.confidence == nil)
    #expect(SurveyMoment.from(photos: [a, b, c], group: 4) == nil)        // one frame is no moment
}

@Test func impactOrderPutsCloseCallsAndBigMomentsFirst() {
    let easy = moment(1, [1, 2], margin: 0.1)
    let big = moment(2, [3, 4, 5, 6], margin: 0.1)
    let close = moment(3, [7, 8], margin: 0.01)
    let lower = moment(4, [9, 10], margin: 0.06)
    let tie = moment(5, [11, 12], margin: 0.1)
    #expect(SurveyMoment.byImpact([easy, big, close, lower, tie]).map(\.id) == [3, 2, 4, 1, 5])
    #expect(SurveySession(moments: [easy, big], ordered: false).current?.id == 1)
    #expect(SurveySession(moments: [easy, big]).current?.id == 2)
    #expect(SurveySession(moments: [moment(9, [1])]).finished)              // single frames are not asked
}

// MARK: selection

@Test func recommendationIsPreselectedAndNumbersPick() {
    var s = SurveySession(moments: [moment(1, [10, 11, 12], best: 11)])
    #expect(s.keepers == [11] && s.focusedId == 11 && s.position == (1, 1))
    #expect(s.pick(3) && s.keepers == [12] && s.focus == 2)
    #expect(!s.pick(4) && s.keepers == [12])                                // no frame 4: nothing changes
    #expect(s.toggleKeeper(1) && s.keepers == [10, 12])                     // ⇧1 adds, in the moment's order
    #expect(s.toggleKeeper(1) && s.keepers == [12])                         // ⇧1 again takes it out
    s.pick(2)
    #expect(s.keepers == [11])                                              // a plain number: the only keeper again
}

@Test func focusKeepAndLeaveOut() {
    var s = SurveySession(moments: [moment(1, [10, 11, 12], best: 10)])
    s.moveFocus(-1); #expect(s.focus == 0)                                  // stops at the ends
    s.moveFocus(1); s.keepFocused()
    #expect(s.keepers == [10, 11])
    s.moveFocus(5); #expect(s.focus == 2)
    s.moveFocus(-2); s.leaveOutFocused()
    #expect(s.keepers == [11])
    s.moveFocus(1); s.leaveOutFocused()
    #expect(s.keepers.isEmpty && s.pending()?.primary == nil && s.pending()?.leftOut == [10, 11, 12])
    s.nextFace(people: 2); s.nextFace(people: 2); #expect(s.face == 0)
    s.nextFace(people: 0); #expect(s.face == 0)
}

// MARK: decisions

@Test func confirmRecordsEveryKeeperAndMovesOn() {
    var s = SurveySession(moments: [moment(1, [10, 11, 12], best: 11), moment(2, [20, 21], best: 20)], ordered: false)
    s.toggleKeeper(3)
    let d = s.confirm(previous: [10: ["rejected": .bool(false)]], previousKeeper: nil)
    #expect(d?.keepers == [11, 12] && d?.leftOut == [10] && d?.primary == 11 && d?.extras == [12] && d?.accepted == false)
    #expect(s.current?.id == 2 && s.keepers == [20] && s.focusedId == 20 && s.face == 0)
    #expect(s.counts.kept == 2 && s.counts.leftOut == 1)
    #expect(s.progress == 0.5)
}

@Test func primaryIsTheRecommendationWhenKeptElseTheFirstKeeper() {
    let m = moment(1, [10, 11, 12], best: 12)
    #expect(SurveyDecision(moment: m, keepers: [11, 12], accepted: false).primary == 12)
    #expect(SurveyDecision(moment: m, keepers: [12, 10], accepted: false).keepers == [10, 12])
    #expect(SurveyDecision(moment: m, keepers: [11, 10], accepted: false).primary == 10)
}

@Test func acceptTakesTheRecommendationWhateverWasSelected() {
    var s = SurveySession(moments: [moment(1, [10, 11], best: 10)])
    s.pick(2)
    let d = s.accept(previous: [:], previousKeeper: nil)
    #expect(d?.keepers == [10] && d?.leftOut == [11] && d?.accepted == true && s.finished)
    #expect(s.confirm(previous: [:], previousKeeper: nil) == nil)           // nothing left to confirm
}

@Test func backUndoesStepByStepWithTheChosenKeepers() {
    var s = SurveySession(moments: [moment(1, [10, 11, 12], best: 10), moment(2, [20, 21], best: 21), moment(3, [30, 31])],
                          ordered: false)
    s.pick(2); s.toggleKeeper(3)
    s.confirm(previous: [10: ["keep": .bool(true)]], previousKeeper: 12)
    s.skip()
    #expect(s.current?.id == 3 && s.canGoBack && s.skippedMoments.map(\.id) == [2])
    let skipped = s.back()
    #expect(skipped?.kind == .skipped && s.current?.id == 2 && s.keepers == [21])
    let decided = s.back()
    #expect(decided?.decision?.keepers == [11, 12] && decided?.previousKeeper == 12)
    #expect(decided?.previous[10] == ["keep": .bool(true)])
    #expect(s.current?.id == 1 && s.keepers == [11, 12] && s.focusedId == 11)   // what was chosen, ready to change
    #expect(s.back() == nil && !s.canGoBack && s.counts.kept == 0)
}

@Test func finishedSessionIsSafe() {
    var s = SurveySession(moments: [moment(1, [10, 11])])
    s.skip()
    #expect(s.finished && s.current == nil && s.focusedId == nil && s.position == (1, 1) && s.progress == 1)
    #expect(!s.pick(1) && s.pending() == nil)
    s.skip(); s.moveFocus(1); s.keepFocused()
    #expect(s.history.count == 1)
    let empty = SurveySession(moments: [])
    #expect(empty.finished && empty.progress == 1 && empty.position == (1, 0))
}

// MARK: reason chips

@Test func chipsComeFromWhatTheEngineMeasured() throws {
    let good = try photo(1, #""focus": {"tier": "sharp"}, "faces": {"faces": 2, "eyes_closed": 0, "looking_away": 0, "boxes": [{"x": 0.2, "y": 0.2, "w": 0.1, "h": 0.1, "state": "open"}, {"x": 0.6, "y": 0.2, "w": 0.1, "h": 0.1, "state": "open"}]}"#)
    #expect(surveyChips(good) == [.sharpFace, .eyesOpen])
    let closed = try photo(2, #""focus": {"tier": "sharp"}, "faces": {"faces": 1, "eyes_closed": 1, "looking_away": 0, "boxes": [{"x": 0.2, "y": 0.2, "w": 0.1, "h": 0.1, "state": "closed"}]}"#)
    #expect(surveyChips(closed) == [.eyesClosed, .sharpFace])
    let moving = try photo(3, #""focus": {"tier": "soft"}, "quality": {"blur": "soft", "reasons": ["movement_blur"]}"#)
    #expect(surveyChips(moving) == [.motionBlur])
    let blurry = try photo(4, #""focus": {"tier": "blurry"}"#)
    #expect(surveyChips(blurry) == [.blurry])
    let landscape = try photo(5, #""quality": {"blur": "sharp", "reasons": []}"#)
    #expect(surveyChips(landscape) == [.sharp])
    let away = try photo(6, #""focus": {"tier": "sharp"}, "faces": {"faces": 1, "eyes_closed": 1, "looking_away": 1, "boxes": [{"x": 0.2, "y": 0.2, "w": 0.1, "h": 0.1, "state": "closed", "looking_away": true}]}"#)
    #expect(surveyChips(away) == [.eyesClosed, .lookingAway, .sharpFace])      // at most three, problems first
    #expect(surveyChips(away, limit: 1) == [.eyesClosed])
    #expect(surveyChips(try photo(7)).isEmpty)
    for c in SurveyChip.allCases { #expect(Strings.table[c.textKey] != nil, "missing \(c.textKey)") }
    for c in SurveyConfidence.allCases { #expect(Strings.table[c.textKey] != nil, "missing \(c.textKey)") }
}

// MARK: face columns

@Test func faceColumnsLineUpPerPersonAndFollowTab() throws {
    // Frame 0 (recommended) shows no face; frame 1 shows Ana and Bor; frame 2 only Ana, eyes closed.
    let f0: [Photo.Faces.Box] = []
    let f1 = [try box(0.2, 0.3, 0.12), try box(0.6, 0.3)]          // Ana a little larger: she is person 1
    let f2 = [try box(0.21, 0.31, state: "closed")]
    let faces = SurveyFaces(frames: [f0, f1, f2], preferred: 0)
    #expect(faces.reference == 1 && faces.people == 2)
    #expect(faces.strip(frame: 2).map { $0.map(eyeState) } == ["closed", nil])
    #expect(faces.strip(frame: 0).allSatisfy { $0 == nil })
    // Tab on Bor while frame 2 (where he is not found) is focused: his place in the reference frame.
    let t = faces.zoomTarget(person: 1, frame: 2)
    #expect(abs(t.x - 0.65) < 1e-9 && abs(t.y - 0.35) < 1e-9)
    let own = faces.zoomTarget(person: 0, frame: 2)                  // Ana's own face in frame 2
    #expect(abs(own.x - 0.26) < 1e-9 && abs(own.y - 0.36) < 1e-9)
    #expect(faces.zoomTarget(person: 5, frame: 0) == .centre)
    #expect(faceReference([], preferred: 3) == 0 && faceReference([f1, f2], preferred: 9) == 0)
}

// MARK: layout

@Test func layoutSideBySideThenFilmstrip() {
    // Three landscape frames in 1500 × 700 with 100 below: limited by width.
    let three = surveyLayout(ratios: [1.5, 1.5, 1.5], width: 1500, height: 700, below: 100, spacing: 12)
    #expect(!three.filmstrip && abs(three.height - (1500 - 24) / 4.5) < 1e-9 && three.height == three.focusedHeight)
    // Two frames in a tall space: limited by height.
    let two = surveyLayout(ratios: [1.5, 1.5], width: 3000, height: 700, below: 100)
    #expect(two.height == 600)
    // Seven frames: a filmstrip, the focused frame larger.
    let seven = surveyLayout(ratios: Array(repeating: 1.5, count: 7), width: 1500, height: 700, below: 100)
    #expect(seven.filmstrip && seven.focusedHeight > seven.height && seven.focusedHeight <= 600)
    // Six portrait-free frames in a narrow window that would be tiny: filmstrip too.
    #expect(surveyLayout(ratios: Array(repeating: 1.5, count: 6), width: 700, height: 700, below: 100).filmstrip)
    #expect(surveyLayout(ratios: [], width: 100, height: 100, below: 0).height == 0)
}

@Test func coachShowsOnce() {
    #expect(SurveyCoach.shouldShow(seen: false) && !SurveyCoach.shouldShow(seen: true))
}
