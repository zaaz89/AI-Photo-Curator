import Foundation
import Testing
@testable import CuratorCore

// M14a: the album's path is derived from its data only. One test per row of the table in `AlbumJourney`, then
// the edges (zero counts, stale days, done marks), the words, and the completion moments.

/// An album that is sorted, has no questions and is not exported: the "ready to export" baseline.
private func sorted(_ change: (inout JourneyInput) -> Void = { _ in }) -> AlbumJourney {
    var i = JourneyInput(folders: 2, photos: 236, started: true, daysTotal: 7, daysSettled: 7, inAlbum: 187)
    change(&i)
    return AlbumJourney(i)
}

@Test func noFolderAsksForFolders() {
    let j = AlbumJourney(JourneyInput())
    #expect(j.current == .photos && j.action == .addFolders && j.action.isEnabled)
    #expect(j.questions == 0 && !j.isDone)
    #expect(j.canOpen(.photos) && !j.canOpen(.analysis))
}

@Test func foldersButNotStartedAsksToStart() {
    let j = AlbumJourney(JourneyInput(folders: 3))
    #expect(j.current == .photos && j.action == .start)
    #expect(j.actionTitle(.en) == "Start")
}

@Test func runningAnalysisWaitsWithAReason() {
    let j = sorted { $0.analysing = true; $0.daysSettled = 2; $0.progress = 0.4 }
    #expect(j.current == .analysis && j.action == .wait && !j.action.isEnabled)
    #expect(j.waitReason(.en) != nil && j.waitReason(.sl) != nil)
    #expect(j.status(.en) == "Analysing · day 3 of 7")
    #expect(j.workingDay == 3)
    #expect(j.ringProgress == 0.4)
    #expect(j.questions == 0)                                // nothing is asked while photos are sorted
    // Before the first day is known the status falls back to a percentage.
    let early = AlbumJourney(JourneyInput(folders: 1, started: true, analysing: true, progress: 0.12))
    #expect(early.status(.en) == "Analysing · 12 %")
    #expect(early.ringProgress == 0.12)
}

@Test func ringNeverGoesBackWhenADaySettles() {
    // Settled days count even when the job's percent lags behind.
    let j = sorted { $0.analysing = true; $0.daysSettled = 4; $0.progress = 0.1 }
    #expect(j.ringProgress == 4.0 / 7.0)
    let last = sorted { $0.analysing = true; $0.daysSettled = 9; $0.progress = 0.99 }
    #expect(last.workingDay == 7 && last.ringProgress == 1)
}

@Test func failedAnalysisOffersTryAgain() {
    let j = sorted { $0.analysisFailed = true; $0.daysSettled = 3 }
    #expect(j.current == .analysis && j.action == .retry && j.action.isEnabled)
    #expect(j.actionTitle(.en) == "Try Again")
}

@Test func unsortedDaysOfferToContinue() {
    let j = sorted { $0.daysSettled = 5 }
    #expect(j.current == .analysis && j.action == .resume)
    #expect(j.status(.en) == "Paused · 5 of 7 days sorted")
    #expect(sorted { $0.daysSettled = 0 }.status(.en) == "Paused")
    // An album with nothing to sort (no days) is not stuck at Sorting.
    let empty = AlbumJourney(JourneyInput(folders: 1, started: true))
    #expect(empty.analysisSettled && empty.current == .album)
    #expect(empty.action == .export(0) && !empty.action.isEnabled && empty.waitReason(.en) != nil)
}

@Test func questionsAddUpMomentsLooksAndClocks() {
    let j = sorted { $0.openMoments = 3; $0.haveALook = 2; $0.unsureClocks = 1 }
    #expect(j.questions == 6)
    #expect(j.current == .decisions && j.action == .answer(6))
    #expect(j.actionTitle(.en) == "Answer 6 questions")
    #expect(j.actionTitle(.sl) == "Odgovori na 6 vprašanj")
    #expect(j.status(.en) == "6 questions" && j.status(.sl) == "6 vprašanj")
    #expect(sorted { $0.haveALook = 1 }.actionTitle(.en) == "Answer 1 question")
    #expect(sorted { $0.haveALook = 2 }.actionTitle(.sl) == "Odgovori na 2 vprašanji")
    // Negative counts from a bad answer never make questions.
    #expect(sorted { $0.openMoments = -2 }.questions == 0)
}

@Test func answeredQuestionsMoveOnToTheAlbum() {
    let j = sorted { $0.openMoments = 3; $0.haveALook = 2; $0.decisionsDone = true }
    #expect(j.questions == 0)
    #expect(j.current == .album && j.action == .export(187))
    #expect(j.isComplete(.decisions) && j.isComplete(.analysis) && j.isComplete(.photos) && !j.isComplete(.album))
}

@Test func exportLabelsUseTheRightForm() {
    #expect(sorted().actionTitle(.en) == "Export 187 photos")
    #expect(sorted().actionTitle(.sl) == "Izvozi 187 fotografij")
    #expect(sorted { $0.inAlbum = 1 }.actionTitle(.en) == "Export 1 photo")
    #expect(sorted { $0.inAlbum = 1 }.actionTitle(.sl) == "Izvozi 1 fotografijo")          // accusative
    #expect(sorted { $0.inAlbum = 3 }.actionTitle(.sl) == "Izvozi 3 fotografije")
    #expect(sorted().status(.en) == "Ready to export")
}

@Test func exportRunsThenDone() {
    let running = sorted { $0.exporting = true; $0.exportProgress = 0.5 }
    #expect(running.current == .album && running.action == .exporting && !running.action.isEnabled)
    #expect(running.status(.en) == "Exporting · 50 %" && running.ringProgress == 0.5)
    #expect(!running.isDone)
    let done = sorted { $0.exported = true }
    #expect(done.action == .openFolder && done.isDone && done.status(.en) == "Exported")
    #expect(JourneyStation.allCases.allSatisfy(done.isComplete))
    #expect(done.pathProgress == 1)
    // A second export of a finished album shows its progress again.
    #expect(sorted { $0.exported = true; $0.exporting = true }.action == .exporting)
}

@Test func addingPhotosAfterExportGoesBackToSorting() {
    // New folder after an export: the new day is not sorted yet, so the path is at Sorting again.
    let j = sorted { $0.exported = true; $0.daysTotal = 8 }
    #expect(j.current == .analysis && j.action == .resume && !j.isDone)
}

@Test func anExportedAlbumIsDoneEvenWithOldQuestions() {
    // Albums exported before M14 may still have moments nobody answered: they are done, not back at Questions.
    let j = sorted { $0.exported = true; $0.openMoments = 4 }
    #expect(j.questions == 0 && j.isDone && j.action == .openFolder)
}

@Test func onlyReachedStationsOpen() {
    let j = sorted { $0.openMoments = 2 }                        // at Questions
    #expect(j.canOpen(.photos) && j.canOpen(.analysis) && j.canOpen(.decisions) && !j.canOpen(.album))
    #expect(j.shown(nil) == .decisions)
    #expect(j.shown(.photos) == .photos)
    #expect(j.shown(.album) == .decisions)                       // a station ahead opens the current one
}

@Test func firstMatchingRuleWins() {
    // No folder beats everything else (all folders removed from an exported album).
    #expect(AlbumJourney(JourneyInput(folders: 0, started: true, analysing: true, exported: true)).action == .addFolders)
    // Running beats failed (a retry is under way).
    #expect(sorted { $0.analysing = true; $0.analysisFailed = true }.action == .wait)
    // Open questions come before a running export (photos added while an older export copies).
    #expect(sorted { $0.openMoments = 1; $0.exporting = true }.action == .answer(1))
}

@Test func everyStateHasWordsInBothLanguages() {
    let states: [AlbumJourney] = [
        AlbumJourney(JourneyInput()), AlbumJourney(JourneyInput(folders: 1)),
        sorted { $0.analysing = true }, sorted { $0.analysisFailed = true }, sorted { $0.daysSettled = 2 },
        sorted { $0.haveALook = 4 }, sorted(), sorted { $0.exporting = true }, sorted { $0.exported = true },
        AlbumJourney(JourneyInput(folders: 1, started: true)),
    ]
    for j in states {
        for l in Lang.allCases {
            #expect(!j.status(l).isEmpty && !j.actionTitle(l).isEmpty)
            #expect(!j.status(l).contains("%") || j.status(l).contains(" %"), "unformatted: \(j.status(l))")
            #expect(!j.actionTitle(l).contains("%@"))
        }
        #expect(!j.actionSymbol.isEmpty)
    }
    for s in JourneyStation.allCases {
        #expect(s.title(.en) != s.title(.sl) || s == .album)
        #expect(s.menuDigit == s.number)
    }
}

@Test func completionMomentsFollowTheWayForward() {
    #expect(completedStations(from: .photos, to: .analysis) == [.photos])
    #expect(completedStations(from: .analysis, to: .album) == [.analysis, .decisions])    // no questions: both
    #expect(completedStations(from: .album, to: .analysis).isEmpty)                       // going back: nothing
    #expect(completedStations(from: .decisions, to: .decisions).isEmpty)
}

@Test func questionsEstimateIsAboutTwoMinutesForSix() {
    let s = questionsEstimate(moments: 3, look: 2, clocks: 1)
    #expect(s == 92)
    #expect(Strings.duration(s, .en) == Strings.duration(120, .en))                      // "about 2 min"
    #expect(questionsEstimate(moments: -1, look: 0, clocks: 0) == 0)
}

@Test func inputSurvivesTheSidebarCache() throws {
    let i = JourneyInput(folders: 2, photos: 10, started: true, analysing: true, progress: 0.3, daysTotal: 3,
                         daysSettled: 1, openMoments: 1, haveALook: 2, unsureClocks: 0, inAlbum: 8, exported: false)
    let back = try JSONDecoder().decode(JourneyInput.self, from: JSONEncoder().encode(i))
    #expect(back == i && AlbumJourney(back) == AlbumJourney(i))
}

@Test func confirmationsSayWhatGoesAndWhatStays() {
    let exported = removeAlbumConfirm("Rome", exported: true, .en)
    #expect(exported.title.contains("Rome"))
    #expect(exported.message.contains("not touched") && exported.message.contains("can't be undone"))
    let notYet = removeAlbumConfirm("Rome", exported: false, .sl)
    #expect(notYet.message.hasPrefix(Strings.text("removeAlbumNotExported", .sl)))
    #expect(!notYet.button.isEmpty)
    let folder = removeFolderConfirm("Ana · iPhone 15", photos: 120, .en)
    #expect(folder.title.contains("Ana · iPhone 15") && folder.message.contains("120 photos"))
    #expect(folder.message.contains("not touched"))
}

@Test func chipLabelsNameThePersonAndTheCamera() {
    #expect(folderChipLabel(owner: "Ana", devices: []) == "Ana")
    #expect(folderChipLabel(owner: "Ana", devices: ["iPhone 15"]) == "Ana · iPhone 15")
    #expect(folderChipLabel(owner: "Žaž", devices: ["ILCE-7M4", "Pixel 8"]) == "Žaž · ILCE-7M4 +1")
    #expect(folderChipLabel(owner: "Ana", devices: ["", "Pixel 8"]) == "Ana · Pixel 8")
}

@Test func newPluralWords() {
    #expect(Strings.count(1, .question, .en) == "1 question" && Strings.count(5, .question, .en) == "5 questions")
    #expect(Strings.count(1, .question, .sl) == "1 vprašanje" && Strings.count(2, .question, .sl) == "2 vprašanji")
    #expect(Strings.count(4, .question, .sl) == "4 vprašanja" && Strings.count(5, .question, .sl) == "5 vprašanj")
    #expect(Strings.count(101, .photoObject, .sl) == "101 fotografijo")
}
