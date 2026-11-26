import Foundation

// MARK: M14a "one album, one path"

/// The four stations of an album, in order. The app derives where an album is from its data
/// (`AlbumJourney`); the owner never has to know the engine's phases.
public enum JourneyStation: Int, CaseIterable, Identifiable, Hashable, Comparable, Codable, Sendable {
    case photos = 1, analysis, decisions, album

    public var id: Int { rawValue }
    public var number: Int { rawValue }
    public static func < (a: JourneyStation, b: JourneyStation) -> Bool { a.rawValue < b.rawValue }

    public var symbol: String {
        switch self {
        case .photos: "photo.on.rectangle.angled"
        case .analysis: "sparkles"
        case .decisions: "questionmark.bubble"
        case .album: "book.closed"
        }
    }

    /// The station's short name for the rail and the menu ("Photos", "Sorting", "Questions", "Album").
    public func title(_ lang: Lang) -> String {
        switch self {
        case .photos: Strings.text("stationPhotos", lang)
        case .analysis: Strings.text("stationSorting", lang)
        case .decisions: Strings.text("stationQuestions", lang)
        case .album: Strings.text("stationAlbum", lang)
        }
    }

    /// ⌘ + this digit opens the station (⌘1 … ⌘4).
    public var menuDigit: Int { rawValue }
}

/// Everything the journey needs to know about one album, as plain values (no engine types), so it can be
/// unit-tested and cached per album for the sidebar.
public struct JourneyInput: Equatable, Codable, Sendable {
    /// Photo folders in the album.
    public var folders: Int
    /// Photos and videos read so far.
    public var photos: Int
    /// The owner pressed Start once (or the album was analysed before M14).
    public var started: Bool
    /// The analysis of this album runs now.
    public var analysing: Bool
    /// The last analysis of this album stopped with an error.
    public var analysisFailed: Bool
    /// The running analysis, 0…1.
    public var progress: Double
    /// Days of the album and how many of them are sorted with their current photos and times.
    public var daysTotal: Int
    public var daysSettled: Int
    /// Moments where the app could not pick the best frame by a clear margin.
    public var openMoments: Int
    /// Photos the app flags with "Have a look".
    public var haveALook: Int
    /// Camera clocks with a suggested shift nobody confirmed.
    public var unsureClocks: Int
    /// The owner went through the questions or accepted the rest.
    public var decisionsDone: Bool
    /// Photos the export would copy.
    public var inAlbum: Int
    /// An export of this album runs now, 0…1.
    public var exporting: Bool
    public var exportProgress: Double
    /// The album was exported and verified at least once.
    public var exported: Bool

    public init(folders: Int = 0, photos: Int = 0, started: Bool = false, analysing: Bool = false,
                analysisFailed: Bool = false, progress: Double = 0, daysTotal: Int = 0, daysSettled: Int = 0,
                openMoments: Int = 0, haveALook: Int = 0, unsureClocks: Int = 0, decisionsDone: Bool = false,
                inAlbum: Int = 0, exporting: Bool = false, exportProgress: Double = 0, exported: Bool = false) {
        self.folders = folders; self.photos = photos; self.started = started; self.analysing = analysing
        self.analysisFailed = analysisFailed; self.progress = progress; self.daysTotal = daysTotal
        self.daysSettled = daysSettled; self.openMoments = openMoments; self.haveALook = haveALook
        self.unsureClocks = unsureClocks; self.decisionsDone = decisionsDone; self.inAlbum = inAlbum
        self.exporting = exporting; self.exportProgress = exportProgress; self.exported = exported
    }
}

/// The one primary action of the album, with what it needs for its label.
public enum JourneyAction: Equatable, Sendable {
    /// No folder yet.
    case addFolders
    /// Folders are there; nothing analysed yet.
    case start
    /// The analysis runs: the button waits (disabled) and says why.
    case wait
    /// The analysis was stopped, or new photos wait to be sorted.
    case resume
    /// The analysis stopped with a problem.
    case retry
    /// N questions for the owner.
    case answer(Int)
    /// Export N photos.
    case export(Int)
    /// The export runs (disabled).
    case exporting
    /// Exported: open the folder.
    case openFolder

    public var isEnabled: Bool {
        switch self {
        case .wait, .exporting: false
        case .export(let n): n > 0
        default: true
        }
    }
}

/// Where an album is on its path and what the one next thing is. Pure: derived from `JourneyInput` only.
///
/// | Condition (first match)                         | Station    | Action          |
/// |-------------------------------------------------|------------|-----------------|
/// | no folder                                       | photos     | addFolders      |
/// | folders, never started                          | photos     | start           |
/// | analysis runs                                   | analysis   | wait (disabled) |
/// | last analysis failed                            | analysis   | retry           |
/// | days not all sorted                             | analysis   | resume          |
/// | questions > 0, not answered, not exported       | decisions  | answer(n)       |
/// | export runs                                     | album      | exporting       |
/// | exported                                        | album      | openFolder      |
/// | otherwise                                       | album      | export(inAlbum) |
public struct AlbumJourney: Equatable, Sendable {
    public let input: JourneyInput

    public init(_ input: JourneyInput) { self.input = input }

    /// Every day is sorted with its current photos (nothing to sort counts as sorted).
    public var analysisSettled: Bool {
        input.started && !input.analysing && !input.analysisFailed
            && (input.daysTotal == 0 || input.daysSettled >= input.daysTotal)
    }

    /// Open questions: moments without a clear best frame, "Have a look" photos and unsure clocks; zero once the
    /// owner went through them or accepted the rest, once the album is exported, and while photos are not sorted.
    public var questions: Int {
        // An exported album counts as decided (albums exported before M14 may still have unanswered moments).
        guard analysisSettled, !input.decisionsDone, !input.exported else { return 0 }
        return max(0, input.openMoments) + max(0, input.haveALook) + max(0, input.unsureClocks)
    }

    public var current: JourneyStation { state.station }
    public var action: JourneyAction { state.action }

    private var state: (station: JourneyStation, action: JourneyAction) {
        if input.folders == 0 { return (.photos, .addFolders) }
        if !input.started { return (.photos, .start) }
        if input.analysing { return (.analysis, .wait) }
        if input.analysisFailed { return (.analysis, .retry) }
        if !analysisSettled { return (.analysis, .resume) }
        if questions > 0 { return (.decisions, .answer(questions)) }
        if input.exporting { return (.album, .exporting) }
        if input.exported { return (.album, .openFolder) }
        return (.album, .export(input.inAlbum))
    }

    /// The whole path is walked: exported.
    public var isDone: Bool { current == .album && input.exported && !input.exporting }

    /// A station before the current one, or the last one once exported.
    public func isComplete(_ s: JourneyStation) -> Bool { s < current || (s == .album && isDone) }

    /// The owner can open the current station and every one before it (never one ahead).
    public func canOpen(_ s: JourneyStation) -> Bool { s <= current }

    /// The station to show: the one the owner picked if it can be opened, else the current one.
    public func shown(_ picked: JourneyStation?) -> JourneyStation {
        guard let picked, canOpen(picked) else { return current }
        return picked
    }

    /// The day the analysis works on ("day 3 of 7"): the first unsorted day, never past the last.
    public var workingDay: Int { min(max(1, input.daysSettled + 1), max(1, input.daysTotal)) }

    /// Progress for the small ring in the sidebar and the rail, 0…1; nil when nothing runs.
    public var ringProgress: Double? {
        if input.analysing {
            if input.daysTotal > 0 {
                let days = Double(min(input.daysSettled, input.daysTotal)) / Double(input.daysTotal)
                return min(1, max(days, input.progress))
            }
            return min(1, max(0, input.progress))
        }
        if input.exporting { return min(1, max(0, input.exportProgress)) }
        return nil
    }

    /// How far along the whole path the album is, 0…1 (the rail's fill).
    public var pathProgress: Double {
        if isDone { return 1 }
        let base = Double(current.rawValue - 1) / Double(JourneyStation.allCases.count)
        return base
    }

    // MARK: words

    /// One line for the sidebar: where the album is, in the owner's words.
    public func status(_ lang: Lang) -> String {
        switch action {
        case .addFolders: return Strings.text("journeyNoPhotos", lang)
        case .start: return Strings.text("journeyReady", lang)
        case .wait:
            if input.daysTotal > 0 {
                return String(format: Strings.text("journeyAnalysingDay", lang), workingDay, input.daysTotal)
            }
            return String(format: Strings.text("journeyAnalysingPercent", lang), Int((input.progress * 100).rounded()))
        case .resume:
            if input.daysTotal > 0 && input.daysSettled > 0 {
                return String(format: Strings.text("journeyPausedDays", lang), min(input.daysSettled, input.daysTotal), input.daysTotal)
            }
            return Strings.text("journeyPaused", lang)
        case .retry: return Strings.text("journeyProblem", lang)
        case .answer(let n): return Strings.count(n, .question, lang)
        case .export(let n): return n > 0 ? Strings.text("journeyReadyToExport", lang) : Strings.text("journeyEmptyAlbum", lang)
        case .exporting:
            return String(format: Strings.text("journeyExporting", lang), Int((input.exportProgress * 100).rounded()))
        case .openFolder: return Strings.text("journeyExported", lang)
        }
    }

    /// The primary button's label ("Answer 6 questions", "Export 187 photos").
    public func actionTitle(_ lang: Lang) -> String {
        switch action {
        case .addFolders: return Strings.text("journeyAddFolders", lang)
        case .start: return Strings.text("journeyStart", lang)
        case .wait: return Strings.text("journeyContinue", lang)
        case .resume: return Strings.text("journeyResume", lang)
        case .retry: return Strings.text("journeyRetry", lang)
        case .answer(let n): return String(format: Strings.text("journeyAnswer", lang), Strings.count(n, .question, lang))
        case .export(let n): return String(format: Strings.text("journeyExport", lang), Strings.count(n, .photoObject, lang))
        case .exporting: return Strings.text("journeyExportingButton", lang)
        case .openFolder: return Strings.text("journeyOpenFolder", lang)
        }
    }

    /// Why the primary button waits (shown next to it and read by VoiceOver); nil when it does not.
    public func waitReason(_ lang: Lang) -> String? {
        switch action {
        case .wait: return Strings.text("journeyWaitReason", lang)
        case .exporting: return Strings.text("journeyExportWaitReason", lang)
        case .export(let n) where n == 0: return Strings.text("journeyEmptyAlbumReason", lang)
        default: return nil
        }
    }

    /// The symbol of the primary button.
    public var actionSymbol: String {
        switch action {
        case .addFolders: "folder.badge.plus"
        case .start, .resume: "play.fill"
        case .wait: "hourglass"
        case .retry: "arrow.clockwise"
        case .answer: "questionmark.bubble"
        case .export, .exporting: "square.and.arrow.up"
        case .openFolder: "folder"
        }
    }
}

/// About how long the questions take: a moment or a clock ~20 s, a "Have a look" photo ~6 s
/// ("6 questions · about 2 min").
public func questionsEstimate(moments: Int, look: Int, clocks: Int) -> Double {
    Double(max(0, moments)) * 20 + Double(max(0, look)) * 6 + Double(max(0, clocks)) * 20
}

/// The stations whose completion moment should play when the album moves from `old` to `new`: each station
/// passed on the way (a jump from Sorting straight to Album also completes Questions). Nothing when going back.
public func completedStations(from old: JourneyStation, to new: JourneyStation) -> [JourneyStation] {
    guard new > old else { return [] }
    return JourneyStation.allCases.filter { $0 >= old && $0 < new }
}

/// The confirmation for removing an album (title, text, button), plain about what goes and what stays.
public func removeAlbumConfirm(_ name: String, exported: Bool, _ lang: Lang) -> (title: String, message: String, button: String) {
    let title = String(format: Strings.text("removeAlbumTitle", lang), name)
    var message = Strings.text("removeAlbumText", lang)
    if !exported { message = Strings.text("removeAlbumNotExported", lang) + " " + message }
    return (title, message, Strings.text("removeAlbumButton", lang))
}

/// The confirmation for taking one folder out of an album.
public func removeFolderConfirm(_ label: String, photos: Int, _ lang: Lang) -> (title: String, message: String, button: String) {
    (String(format: Strings.text("removeFolderTitle", lang), label),
     String(format: Strings.text("removeFolderText", lang), Strings.count(photos, .photo, lang)),
     Strings.text("removeFolderButton", lang))
}

/// A folder chip's label: the person, and the camera or phone when the folder has one ("Ana · iPhone 15").
public func folderChipLabel(owner: String, devices: [String]) -> String {
    let d = devices.filter { !$0.isEmpty }
    guard let first = d.first else { return owner }
    return d.count == 1 ? "\(owner) · \(first)" : "\(owner) · \(first) +\(d.count - 1)"
}
