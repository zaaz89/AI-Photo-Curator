import Foundation
import Testing
@testable import CuratorCore

private func photo(_ id: Int, _ extra: String = "") throws -> Photo {
    let sep = extra.isEmpty ? "" : ", "
    return try JSONDecoder().decode(Photo.self, from: Data(#"{"id": \#(id), "filename": "p\#(id).jpg", "path": "/x/p\#(id).jpg", "kind": "image"\#(sep)\#(extra)}"#.utf8))
}

private let sharp = #""focus": {"tier": "sharp", "auto_tier": "sharp"}"#
private let blurry = #""focus": {"tier": "blurry", "auto_tier": "blurry"}"#

// MARK: errors (#8)

@Test func engineTextsMapToKinds() {
    #expect(errorKind(engineText: "overlaps with an existing source: /a") == .folderOverlap)
    #expect(errorKind(engineText: "a source folder cannot contain or be inside the app data folder") == .folderOverlap)
    #expect(errorKind(engineText: "a job for trip-1 is still running") == .busy)
    #expect(errorKind(engineText: "the album is still being worked on; stop or wait first") == .busy)
    #expect(errorKind(engineText: "not a folder: /x") == .notAFolder)
    #expect(errorKind(engineText: "collection x not found") == .notFound)
    #expect(errorKind(engineText: "unknown event") == .notFound)
    #expect(errorKind(engineText: "Not enough free space at /Volumes/X: need about 2 GB") == .diskFull)
    #expect(errorKind(engineText: "[Errno 1] Operation not permitted: '/x'") == .permission)
    #expect(errorKind(engineText: "name is required") == .invalid)
    #expect(errorKind(engineText: "something odd happened") == .unknown)
}

@Test func httpStatusesMapToKinds() {
    #expect(errorKind(httpStatus: 404) == .notFound)
    #expect(errorKind(httpStatus: 409) == .busy)
    #expect(errorKind(httpStatus: 400) == .invalid)
    #expect(errorKind(httpStatus: 503) == .unreachable)
    #expect(errorKind(httpStatus: 500) == .server)
    #expect(errorKind(httpStatus: 302) == .unknown)
}

@Test func humanErrorsKeepTheRawTextForDetails() {
    let e = humanError(APIError.engine("overlaps with an existing source: /a"), .en)
    #expect(e.kind == .folderOverlap && e.details.contains("overlaps"))
    #expect(e.message == Strings.text("err_folderOverlap", .en))
    #expect(!e.message.contains("overlaps with"))                    // the developer text stays in Details
    let h = humanError(APIError.http(500), .sl)
    #expect(h.kind == .server && h.details == "HTTP 500" && h.message == Strings.text("err_server", .sl))
    #expect(humanError(APIError.unreachable("refused"), .en).kind == .unreachable)
    #expect(humanError(URLError(.timedOut), .en).kind == .unreachable)
    let job = humanError(engineText: "Error: Not enough free space at /x", .en)
    #expect(job.kind == .diskFull && job.details == "Not enough free space at /x")
}

@Test func everyErrorKindHasBothLanguages() {
    for k in ErrorKind.allCases {
        for l in Lang.allCases {
            let m = errorMessage(k, l)
            #expect(!m.isEmpty && !m.hasPrefix("err_"), "missing text for \(k) \(l)")
        }
    }
    #expect(errorMessage(.busy, .en) != errorMessage(.busy, .sl))
}

@Test func engineStartFailuresAreLocalisedWithoutPaths() {
    let all: [EngineStartFailure] = [.projectMissing, .pythonMissing, .launch("boom"), .timeout]
    for f in all {
        for l in Lang.allCases {
            let h = f.human(l)
            #expect(!h.message.isEmpty && !h.message.hasPrefix("engine"))
            #expect(!h.message.contains("local-data"))                // the path is only in Details
        }
    }
    #expect(EngineStartFailure.launch("boom").human(.en).details == "boom")
    #expect(EngineStartFailure.timeout.human(.sl).message != EngineStartFailure.timeout.human(.en).message)
}

// MARK: menu order (#15)

@Test func menuFollowsTheFlow() {
    #expect(FlowPage.allCases == [.home, .people, .sorting, .selection, .story, .export, .settings])
    let digits = FlowPage.allCases.compactMap(\.menuDigit)
    #expect(digits == [0, 1, 2, 3, 4, 5])
    #expect(FlowPage.sorting.menuDigit != nil)                            // Sorting has a shortcut now
    #expect(!digits.contains(allPhotosMenuDigit) && !digits.contains(leftOutMenuDigit))
    #expect(allPhotosMenuDigit != leftOutMenuDigit)
    // The steps keep their own number (Step 1 of 3); only the menu digit changed.
    #expect(FlowPage.selection.guideStep == .selection && GuideStep.selection.number == 1)
    #expect(FlowPage.allCases.compactMap(\.guideStep) == GuideStep.allCases)
}

// MARK: grid keys (#18)

@Test func gridKeysMatchTheReviewFamily() {
    #expect(gridKeyAction("k") == .keep && gridKeyAction("K") == .keep)
    #expect(gridKeyAction("x") == .leaveOut)
    #expect(gridKeyAction("f") == .favourite && gridKeyAction("b") == .wallpaper)
    #expect(gridKeyAction(" ") == nil && gridKeyAction("1") == nil)
}

// MARK: grid badge (#21)

@Test func autoBadgesOnlyForTheAppsOwnDecisions() throws {
    let shot = try photo(1, sharp + #", "screenshot": true"#)
    #expect(autoBadge(shot, .en)?.kind == .screenshot)
    #expect(autoBadge(shot, .en)?.label == "Screenshot")
    #expect(autoBadge(try photo(2, sharp + #", "screenshot": true, "keep": true"#), .en) == nil)     // kept by the owner
    #expect(autoBadge(try photo(3, blurry + #", "rejected": true"#), .en) == nil)                   // owner's choice
    let blur = try #require(autoBadge(try photo(4, blurry + #", "quality": {"blur": "blurry", "blur_reason": "movement", "reasons": ["movement_blur"]}"#), .en))
    #expect(blur.kind == .blurry && blur.reason.hasPrefix(Strings.text("why2_movement_blur", .en)))
    let doc = try photo(5, sharp + #", "quality": {"utility": true, "reasons": ["utility_image"]}"#)
    #expect(autoBadge(doc, .sl)?.kind == .document && autoBadge(doc, .sl)?.label == "Dokument")
    #expect(autoBadge(try photo(6, sharp), .en) == nil)
    #expect(autoBadge(try photo(7, sharp + #", "screenshot": true, "favorite": true"#), .en) == nil)
}

// MARK: Finish Album (#22)

@Test func finishAlbumSaysItClearsDataAndWarnsFirst() {
    let t = finishAlbumTitle("Rome", exported: false, .en)
    #expect(t.hasPrefix(Strings.text("finishNotExportedShort", .en)))
    #expect(t.contains("Clear working data") && t.contains("Rome"))
    #expect(finishAlbumTitle("Rome", exported: true, .en) == "Clear working data for “Rome”?")
    #expect(finishAlbumText(exported: false, .sl).hasPrefix(Strings.text("finishNotExported", .sl)))
    #expect(finishAlbumText(exported: true, .en) == Strings.text("finishText", .en))
    #expect(Strings.text("finishConfirm", .en) == "Clear Data")
}
