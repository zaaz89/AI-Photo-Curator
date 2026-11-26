import AppKit
import CuratorCore
import Foundation
import os
import SwiftUI

/// Sidebar destinations.
/// What the detail area shows (M14a): the album's path, one of its secondary views (the toolbar's View menu) or a
/// photo grid. The path's stations are not destinations: `LibraryModel.station` picks one on the path.
enum Destination: Hashable {
    case journey, moments, chapters, people, all, favourites, leftOut, videos, blurry, day(String), search, settings
    /// A page (the path, a secondary view, settings), not a photo grid.
    var isPage: Bool {
        switch self { case .journey, .moments, .chapters, .people, .settings: true; default: false }
    }
}

/// The last known state of an album for the sidebar (M14a): its journey input and cover, cached per album so
/// albums that are not open still show a status line and a cover.
struct JourneySnapshot: Codable, Equatable {
    var input: JourneyInput
    var coverPath: String?
}

/// The Selection step's three views.
enum SelectionView: String, CaseIterable, Identifiable {
    case moments, blurry, leftOut
    var id: String { rawValue }
}

/// The app's state for one window: trips, the current trip's photos, selection, marks with undo,
/// search, and the engine's background job.
@MainActor final class LibraryModel: ObservableObject {
    let api: APIClient

    @Published var trips: [Trip] = []
    @Published var tripId: String? { didSet { if tripId != oldValue { tripChanged() } } }
    @Published private(set) var photos: [Photo] = [] {
        didSet {
            photoIndex = Dictionary(photos.indices.map { (photos[$0].id, $0) }, uniquingKeysWith: { a, _ in a })
            lookCount = photos.reduce(0) { $0 + (sortVerdict($1) == .check ? 1 : 0) }
            recompute()
        }
    }
    /// Photos flagged "Have a look" (counted once per change of the photos, not per view update).
    private(set) var lookCount = 0
    @Published private(set) var events: [TripEvent] = [] { didSet { recompute() } }
    /// The trip `photos` belong to. Marks and moves are refused while it differs from `tripId`:
    /// photo ids are per trip, so an old id would hit another photo in the new trip.
    @Published private(set) var loadedTripId: String?
    /// What the grid shows, rebuilt only when photos, events, the view or the order change.
    @Published private(set) var visibleSections: [PhotoSection] = []
    @Published private(set) var flat: [Photo] = []
    @Published private(set) var sources: [SourceInfo] = []
    /// The album checklist from the engine (import … export).
    @Published private(set) var steps: [String: Bool] = [:]
    /// What the album still needs (cards of the Overview).
    @Published private(set) var overview: Overview?
    /// Moments the owner went through in this session; a reopened sheet continues after them.
    var reviewedMoments: Set<Int> = []
    var exported: Bool { steps["export"] == true || overview?.export.done == true }
    @Published var selectionView: SelectionView = .moments
    @Published var destination: Destination = .journey { didSet { if destination != oldValue { clearSelection(); recompute() } } }
    /// The station the owner opened on the rail (M14a); nil follows the album to its current station.
    @Published var station: JourneyStation?
    @Published var sort: PhotoSort = .time { didSet { recompute() } }
    @Published var selection: Set<Int> = []
    @Published var cursor: Int = -1                     // flat index into `flat`
    @Published var tileSize: Double = 190
    @Published var searchText = ""
    @Published var searchFocusRequest = 0               // ⌘F: the window moves focus to the search field
    @Published private(set) var searchResult: SearchResult? { didSet { recompute() } }
    @Published private(set) var searching = false
    @Published var settings: EngineSettings? {
        // Remembered so the start screen speaks the owner's language before the engine answers (M12e).
        didSet { if let l = settings?.uiLanguage { UserDefaults.standard.set(l, forKey: "uiLanguage") } }
    }
    /// The measured speed of this Mac for the time estimate (nil before the first analysis).
    @Published var speed: EngineSpeed?
    /// The sorting stage should play again from the folders when it next shows (or now, when it shows already).
    @Published var pendingReplay = false
    /// Changes after an analysis of this album ended and its photos were read again (the stage's cue).
    @Published private(set) var analysisFinishedTick = 0
    /// M13: the engine's per-photo event stream for this album (tiles arrive, drop and stack as days settle).
    @Published private(set) var sortStream = SortStream()
    private var lastStreamReload = Date.distantPast
    private var streamTrip: String?
    @Published var message: String?                     // transient info for the user ("moved to …")
    /// The error on screen (M12e): a human sentence, Details and Try Again; stays until dismissed.
    @Published var errorBanner: ErrorBannerInfo?
    /// The last reversible action, confirmed with an Undo button (`UndoToast`, M12c).
    @Published var undoToast: UndoToastInfo?
    @Published private(set) var job = JobStatus(running: false, status: "")
    @Published private(set) var loading = false

    weak var undoManager: UndoManager?
    private var pollTask: Task<Void, Never>?
    /// Writes go to the engine one after another, in the order the owner made them.
    private var writeQueue: Task<Void, Never>?
    private var pendingWrites = 0
    private var writeGeneration = 0

    init(api: APIClient) {
        self.api = api
        snapshots = Self.loadSnapshots()
    }

    var lang: Lang { Lang(rawValue: settings?.uiLanguage ?? UserDefaults.standard.string(forKey: "uiLanguage") ?? "en") ?? .en }
    func tr(_ key: String) -> String { Strings.text(key, lang) }
    /// A text for a value from the engine; the engine's own words when there is no translation.
    func trOr(_ key: String, _ fallback: String) -> String { Strings.table[key] == nil ? fallback : Strings.text(key, lang) }
    /// A text for an engine code (`why2_…`, `warn_…`, `problem_…`): the translation, else a generic "Other …" text
    /// (never the raw code, M12g #28). The unknown code goes to the log so a missing translation can be found.
    func trCode(_ prefix: String, _ code: String, other: String) -> String {
        let r = Strings.codeText(prefix: prefix, code: code, otherKey: other, lang)
        if !r.known { Self.log.info("No translation for engine code \(prefix + code, privacy: .public)") }
        return r.text
    }
    private static let log = Logger(subsystem: "si.beehive.photocurator", category: "strings")

    // MARK: loading

    func start() async {
        settings = try? await api.settings()
        await loadTrips()
        startPolling()
    }

    func loadTrips() async {
        do {
            trips = try await api.trips()
            let saved = UserDefaults.standard.string(forKey: "trip")
            if tripId == nil || !trips.contains(where: { $0.id == tripId }) {
                tripId = trips.first(where: { $0.id == saved })?.id ?? trips.first?.id
            }
        } catch { report(error) { Task { await self.loadTrips() } } }
    }

    private func tripChanged() {
        undoManager?.removeAllActions()            // undo must never write into another trip
        undoToast = nil
        reviewedMoments = []
        photos = []                                // never show or act on the previous trip's photos
        steps = [:]
        overview = nil
        events = []
        loadedTripId = nil
        sortStream = SortStream()
        streamTrip = tripId
        clearSelection()
        searchResult = nil
        searchText = ""
        destination = .journey
        station = nil
        exportPreviewCount = nil
        if let tripId { UserDefaults.standard.set(tripId, forKey: "trip") }
        Task { await reload() }
    }

    func reload() async {
        guard let tripId else { photos = []; events = []; return }
        loading = true
        defer { loading = false }
        let generation = writeGeneration
        do {
            async let t = api.timeline(trip: tripId)
            async let s = api.sources(trip: tripId)
            async let w = api.workflow(trip: tripId)
            let (timeline, src) = try await (t, s)
            let wf = (try? await w) ?? [:]
            let ov = try? await api.overview(trip: tripId)
            guard tripId == self.tripId else { return }
            steps = wf
            overview = ov
            // A write made while this answer was on its way has already changed the photos locally; the engine's
            // answer predates it, so it must not overwrite them (the reload after that write brings them).
            if generation == writeGeneration && pendingWrites == 0 || loadedTripId != tripId {
                photos = timeline.items
                events = timeline.events
            }
            sources = src
            loadedTripId = tripId
            trimSelection()
            refreshSnapshot()
        } catch { report(error) { Task { await self.reload() } } }
    }

    // MARK: what the grid shows

    var filter: LibraryFilter {
        switch destination {
        case .all: return .all
        case .favourites: return .favourites
        case .leftOut: return .leftOut
        case .videos: return .videos
        case .blurry: return .blurry
        case .journey, .moments, .chapters, .people, .settings: return .all
        case .day(let d): return .day(d)
        case .search: return .ids(searchResult?.results.map(\.id) ?? [])
        }
    }
    private func recompute() {
        visibleSections = sections(photos, events: events, filter: filter, sort: destination == .search ? .time : sort)
        flat = visibleSections.flatMap(\.photos)
    }
    var days: [String] { Array(Set(photos.filter { !$0.rejected }.map(\.day))).sorted() }
    var selectedPhotos: [Photo] { flat.filter { selection.contains($0.id) } }
    var single: Photo? { selection.count == 1 ? flat.first { selection.contains($0.id) } : nil }
    var cursorId: Int? { flat.indices.contains(cursor) ? flat[cursor].id : nil }
    func count(_ d: Destination) -> Int {
        switch d {
        case .all: return photos.filter { !$0.rejected }.count
        case .favourites: return photos.filter(\.favorite).count
        case .leftOut: return photos.filter(\.rejected).count
        case .videos: return photos.filter { $0.isVideo && !$0.rejected }.count
        case .blurry: return photos.filter { $0.focus?.tier == "blurry" }.count
        case .journey, .moments, .chapters, .people, .settings: return 0
        case .day(let day): return photos.filter { $0.day == day && !$0.rejected }.count
        case .search: return searchResult?.results.count ?? 0
        }
    }
    /// Photos not analysed yet (no focus data) shimmer while a job runs.
    func isPending(_ p: Photo) -> Bool { job.running && !p.isVideo && p.focus == nil }

    // MARK: selection

    func clearSelection() { selection = []; cursor = -1 }

    /// After photos leave the view (left out, moved, reloaded): keep only visible ids in the
    /// selection; if nothing visible is left selected, select the photo that took the cursor's
    /// place, so the inspector and the next key press act on the same, highlighted photo.
    private func trimSelection() {
        let visible = Set(flat.map(\.id))
        let had = !selection.isEmpty
        selection.formIntersection(visible)
        if flat.isEmpty { cursor = -1; return }
        if cursor >= flat.count { cursor = flat.count - 1 }
        if had && selection.isEmpty && cursor >= 0 { selection = [flat[cursor].id] }
        if let c = cursorId, !selection.isEmpty, !selection.contains(c),
           let i = flat.firstIndex(where: { selection.contains($0.id) }) { cursor = i }
    }

    func click(_ photo: Photo, modifiers: NSEvent.ModifierFlags) {
        let list = flat
        guard let i = list.firstIndex(where: { $0.id == photo.id }) else { return }
        if modifiers.contains(.command) {
            if selection.contains(photo.id) { selection.remove(photo.id) } else { selection.insert(photo.id) }
        } else if modifiers.contains(.shift), cursor >= 0 {
            selection.formUnion(rangeSelect(from: cursor, to: i, in: list.map(\.id)))
        } else {
            selection = [photo.id]
        }
        cursor = i
    }

    func moveCursor(_ dir: Direction, columns: Int, extend: Bool) {
        let list = flat
        let next = CuratorCore.moveCursor(cursor, dir, columns: columns, sectionSizes: visibleSections.map(\.photos.count))
        guard next >= 0, next < list.count else { return }
        if extend { selection.formUnion(rangeSelect(from: max(cursor, 0), to: next, in: list.map(\.id))) } else { selection = [list[next].id] }
        cursor = next
    }

    // MARK: Quick Look (system panel on the original files)

    @Published var quickLookURL: URL? { didSet { quickLookMovedCursor() } }
    @Published private(set) var quickLookItems: [URL] = []

    func toggleQuickLook() {
        if quickLookURL != nil { quickLookURL = nil; return }
        guard !flat.isEmpty else { return }
        if cursor < 0 { cursor = 0; selection = [flat[0].id] }
        quickLookItems = flat.map(\.fileURL)
        quickLookURL = flat[cursor].fileURL
    }
    /// Arrow keys in the grid move the panel too.
    func quickLookFollowCursor() {
        guard quickLookURL != nil, flat.indices.contains(cursor) else { return }
        if quickLookItems != flat.map(\.fileURL) { quickLookItems = flat.map(\.fileURL) }
        if quickLookURL != flat[cursor].fileURL { quickLookURL = flat[cursor].fileURL }
    }
    /// Arrow keys in the panel move the grid's cursor and selection.
    private func quickLookMovedCursor() {
        guard let url = quickLookURL, let i = flat.firstIndex(where: { $0.fileURL == url }), i != cursor else { return }
        cursor = i
        selection = [flat[i].id]
    }

    func selectAll() { selection = Set(flat.map(\.id)); if cursor < 0 { cursor = 0 } }

    var targets: [Photo] {
        let sel = selectedPhotos
        if !sel.isEmpty { return sel }
        return cursor >= 0 && cursor < flat.count ? [flat[cursor]] : []
    }

    // MARK: marks with undo

    func toggleFavourite() { let t = targets; mark(t, ["favorite": .bool(!t.allSatisfy(\.favorite))], name: tr("favourite")) }
    func toggleLeaveOut() {
        let t = targets, out = !t.allSatisfy(\.rejected)
        mark(t, ["rejected": .bool(out)], name: tr("leaveOut"))
        if !t.isEmpty { pulse(out ? .leaveOut : .keep) }
    }
    func keep() { mark(targets, ["rejected": .bool(false)], name: tr("keep")) }
    func setFocus(_ tier: String?) { mark(targets, ["focus": tier.map { .string($0) } ?? .null], name: tr("focus")) }
    func toggleWallpaper() {
        let t = targets.filter { !$0.isVideo }
        mark(t, ["wallpaper": .bool(!t.allSatisfy(\.wallpaper))], name: tr("wallpaper"))
    }

    private func current(_ p: Photo, _ key: String) -> MarkValue {
        switch key {
        case "favorite": return .bool(p.favorite)
        case "keep": return .bool(p.keep)
        case "rejected": return .bool(p.rejected)
        case "wallpaper": return .bool(p.wallpaper)
        default: return p.focus?.override.map { .string($0) } ?? .null
        }
    }

    /// Applies marks to photos, registers undo with each photo's previous values.
    func mark(_ items: [Photo], _ fields: [String: MarkValue], name: String) {
        guard let tripId, tripId == loadedTripId, !items.isEmpty else { return }
        let previous = items.map { p in (p.id, Dictionary(uniqueKeysWithValues: fields.keys.map { ($0, current(p, $0)) })) }
        let ids = items.map(\.id)
        apply(ids: ids, fields)                                  // the grid reacts at once
        registerUndo(name: name, trip: tripId) { model in
            for (id, f) in previous { model.apply(ids: [id], f) }
            model.enqueue { api in for (id, f) in previous { try await api.setMark(trip: tripId, id: id, f) } }
        } redo: { model in
            model.apply(ids: ids, fields)
            model.enqueue { api in try await api.setMarks(trip: tripId, ids: ids, fields) }
        }
        enqueue { api in try await api.setMarks(trip: tripId, ids: ids, fields) }
    }

    /// Runs engine writes one at a time in order; reloads once when the queue is empty.
    private func enqueue(_ write: @escaping @Sendable (APIClient) async throws -> Void) {
        let previous = writeQueue, api = self.api
        pendingWrites += 1
        writeGeneration += 1
        writeQueue = Task { [weak self] in
            await previous?.value
            do { try await write(api) } catch { self?.report(error) }
            guard let self else { return }
            self.pendingWrites -= 1
            if self.pendingWrites == 0 { await self.reload() }
        }
    }

    private func registerUndo(name: String, trip: String,
                              undo: @escaping @MainActor (LibraryModel) -> Void,
                              redo: @escaping @MainActor (LibraryModel) -> Void) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.tripId == trip, model.loadedTripId == trip else { return }
                undo(model)
                model.registerUndo(name: name, trip: trip, undo: redo, redo: undo)
            }
        }
        um.setActionName(name)
    }

    /// Local, optimistic copy of the marks so the grid updates without waiting for the engine.
    private func apply(ids: [Int], _ fields: [String: MarkValue]) {
        let set = Set(ids)
        var copy = photos                                        // one change, one grid rebuild
        for i in copy.indices where set.contains(copy[i].id) {
            for (k, v) in fields {
                switch (k, v) {
                case ("favorite", .bool(let b)): copy[i].favorite = b
                case ("keep", .bool(let b)): copy[i].keep = b
                case ("rejected", .bool(let b)): copy[i].rejected = b
                case ("wallpaper", .bool(let b)): copy[i].wallpaper = b
                case ("focus", .string(let t)): copy[i].focus = copy[i].focus?.overridden(t)
                case ("focus", .null): copy[i].focus = copy[i].focus?.overridden(nil)
                default: break
                }
            }
        }
        photos = copy
        trimSelection()
    }

    // MARK: M9 editing

    func photo(_ id: Int) -> Photo? { photoIndex[id].map { photos[$0] } }
    private var photoIndex: [Int: Int] = [:]
    var albumName: String { trips.first { $0.id == tripId }?.name ?? "" }

    /// Runs one engine change for an album, then reloads. Ids of photos, chapters and people are per album,
    /// so a view passes the album it was showing (`trip`): an edit committed after the owner switched albums
    /// still goes to the album it belongs to, never to the one now open.
    func change(trip: String? = nil, _ work: @escaping @Sendable (APIClient, String) async throws -> Void) {
        guard let target = trip ?? (tripId == loadedTripId ? tripId : nil) else { return }
        enqueue { api in try await work(api, target) }
    }
    /// The album now shown, if its photos are loaded (views capture it when they appear).
    var shownTrip: String? { tripId == loadedTripId ? tripId : nil }
    /// True when `trip` is the album on screen (comparisons with the shown names only make sense then).
    private func isShown(_ trip: String?) -> Bool { trip == nil || trip == shownTrip }

    func renameAlbum(_ name: String, trip: String?) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trip, !n.isEmpty, n != trips.first(where: { $0.id == trip })?.name else { return }
        Task {
            do { try await api.renameAlbum(trip: trip, name: n); trips = (try? await api.trips()) ?? trips }
            catch { report(error) }
        }
    }

    func renamePerson(source: Int, to name: String, trip: String?) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !(isShown(trip) && sources.first(where: { $0.id == source })?.owner == n) else { return }
        change(trip: trip) { api, t in try await api.renamePerson(trip: t, source: source, owner: n) }
    }

    func renameEvent(_ event: Int, to name: String, trip: String?) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !(isShown(trip) && events.first(where: { $0.id == event })?.name == n) else { return }
        change(trip: trip) { api, t in try await api.renameEvent(trip: t, event: event, name: n) }
    }

    func mergeWithPrevious(_ event: Int) {
        change { api, trip in try await api.mergeWithPrevious(trip: trip, event: event) }
    }

    func newChapter(at photo: Int) {
        change { api, trip in try await api.splitEvent(trip: trip, at: photo) }
    }

    func resetChapters(day: String) {
        change { api, trip in try await api.resetDay(trip: trip, day: day) }
    }


    /// Favourite on a frame of a moment: it goes to the album too, next to the chosen one.
    func toggleKeepToo(_ id: Int) {
        guard let p = photo(id) else { return }
        mark([p], ["keep": .bool(!p.keep), "rejected": .bool(false)], name: tr("keepToo"))
    }

    func setLeftOut(_ ids: [Int], _ out: Bool) {
        let items = ids.compactMap(photo).filter { $0.rejected != out }
        mark(items, ["rejected": .bool(out)], name: tr(out ? "leaveOut" : "keep"))
    }

    /// Puts photos into the album or leaves them out, by the export's own rule: a kept blurry photo gets the
    /// owner's focus mark "soft", a kept extra frame of a moment becomes a favourite ("keep too").
    func setBlurryInAlbum(_ ids: [Int], _ inAlbum: Bool) { _ = setInAlbum(ids, inAlbum) }

    // MARK: quick review (M10)

    /// The quick review on screen, and what it goes through.
    @Published var reviewFilter: ReviewFilter?
    /// ⌘Z during the quick review means Back (the review restores the photo and shows it again).
    @Published var reviewUndoRequest = 0
    // MARK: background control (development and checks; off unless the "automation" default is true)

    /// The last key sent to the quick review through the background channel, and a counter that changes each time.
    private(set) var automationKey: String?
    @Published private(set) var automationKeyTick = 0

    func handleAutomation(_ url: URL) {
        guard UserDefaults.standard.bool(forKey: "automation"), let cmd = AutomationCommand(url: url) else { return }
        switch cmd {
        case .go(let page):
            reviewFilter = nil
            switch page {
            case "home", "journey": open(station: nil)
            case "photos": open(station: .photos)
            case "sorting", "analysis": open(station: .analysis)
            case "selection", "decisions", "questions": open(station: .decisions)
            case "export", "album": open(station: .album)
            case "moments": destination = .moments
            case "story", "chapters": destination = .chapters
            case "people": destination = .people
            case "all": destination = .all
            case "settings": destination = .settings
            default: destination = .leftOut
            }
        case .album(let id):
            // The album may have been made outside the app (engine, command line): read the list first.
            Task {
                if !trips.contains(where: { $0.id == id }) { trips = (try? await api.trips()) ?? trips }
                if trips.contains(where: { $0.id == id }) { tripId = id }
            }
        case .review(let f): startReview(f)
        case .closeReview: reviewFilter = nil
        case .key(let k): automationKey = k; automationKeyTick += 1
        case .window(let w, let h):
            // Resize in place without bringing the app to the front.
            if let win = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible })
                ?? NSApp.windows.first(where: { $0.isVisible && $0.frame.height > 300 && !$0.title.contains("Classic") }) {
                var f = win.frame; f.origin.y += f.height - h; f.size = NSSize(width: w, height: h)
                win.setFrame(f, display: true)
            }
        case .reload: Task { await reload() }
        case .replay: showSorting(replay: true)
        case .firstRun(let page): firstRunPage = page.flatMap(FirstRunPage.init(rawValue:))
        }
    }

    /// How many photos need a yes or no (the quick review's default).
    var decisionsCount: Int { photos.filter(needsDecision).count }
    func startReview(_ f: ReviewFilter = .decisions) {
        reviewSubset = nil                                  // a plain review goes through the filter's whole queue
        if loadedTripId != nil && !photos.isEmpty { reviewFilter = f }
    }

    /// The moments a Survey should open on (M14c), taken once by the quick review when it starts. `standalone`:
    /// the survey was opened on its own (Moments page) and closing it closes the review too.
    @Published var surveyRequest: SurveyRequest?
    func startSurvey(_ moments: [SurveyMoment], standalone: Bool = true, ordered: Bool = true) {
        guard loadedTripId != nil, !photos.isEmpty, !moments.isEmpty else { return }
        surveyRequest = SurveyRequest(moments: moments, standalone: standalone, ordered: ordered)
        if reviewFilter == nil {
            reviewSubset = []                          // nothing after the survey: it closes the review
            reviewFilter = .decisions
        }
    }

    /// Returns once every queued write reached the engine and the album was reloaded (M12d: Selection reloads
    /// its moments after keepers were picked in the compare view).
    func writesSettled() async { await writeQueue?.value }

    /// A photo's marks before a quick-review decision (Back restores them exactly).
    func marksOf(_ id: Int) -> [String: MarkValue] {
        guard let p = photo(id) else { return [:] }
        return ["favorite": .bool(p.favorite), "keep": .bool(p.keep), "rejected": .bool(p.rejected),
                "focus": p.focus?.override.map { .string($0) } ?? .null]
    }

    /// Back in the quick review: the photo gets its earlier marks again.
    func restore(_ id: Int, _ previous: [String: MarkValue]) {
        guard let p = photo(id), !previous.isEmpty else { return }
        mark([p], previous, name: tr("back"))
    }

    func toggleFavourite(_ id: Int) {
        guard let p = photo(id) else { return }
        mark([p], ["favorite": .bool(!p.favorite), "rejected": .bool(false)], name: tr("favourite"))
    }

    /// Where the last quick review of this album stopped (photo id), per filter.
    func reviewBookmark(_ f: ReviewFilter) -> Int? {
        guard let tripId else { return nil }
        let v = UserDefaults.standard.integer(forKey: "review.\(tripId).\(f.rawValue)")
        return v == 0 ? nil : v
    }
    func setReviewBookmark(_ f: ReviewFilter, _ id: Int?) {
        guard let tripId else { return }
        UserDefaults.standard.set(id ?? 0, forKey: "review.\(tripId).\(f.rawValue)")
    }

    /// Returns how many photos changed (0: nothing to undo).
    @discardableResult
    func setInAlbum(_ ids: [Int], _ inAlbum: Bool) -> Int {
        let items = ids.compactMap(photo).filter { $0.goesToAlbumDespiteFocus != inAlbum }
        if inAlbum {
            // An extra frame of a moment goes in as "keep too", a blurry one with the focus mark, one that is
            // both with both (putBackMarks); photos that need the same marks are written together.
            for (fields, group) in Dictionary(grouping: items, by: putBackMarks) {
                mark(group, fields, name: tr("keep"))
            }
        } else {
            mark(items, ["rejected": .bool(true)], name: tr("leaveOut"))
        }
        if !items.isEmpty { pulse(inAlbum ? .keep : .leaveOut) }
        return items.count
    }

    // MARK: delight (M12f)

    /// Changes on every keep / leave out / compare pick; MainWindow turns it into `.sensoryFeedback` (Force Touch
    /// trackpads only; nothing happens elsewhere).
    @Published private(set) var decisionPulse = DecisionPulse.none
    func pulse(_ kind: DecisionFeedback) { decisionPulse = decisionPulse.next(kind) }

    /// The first-run page on screen, nil when it is closed. Set once at launch while `FirstRun.seenKey` is unset,
    /// and by the automation channel (`photocurator://firstrun?page=0`) for checks.
    @Published var firstRunPage: FirstRunPage?

    // MARK: undo toast (M12c)

    /// Shows the undo toast for an action that just registered its undo (nothing when nothing changed, so
    /// Undo never reverts an older action).
    func offerUndo(_ action: UndoableAction, count: Int) {
        guard count > 0 else { return }
        offerUndo(undoToastText(action, count: count, lang))
    }

    func offerUndo(_ text: String) {
        guard undoManager?.canUndo == true else { return }
        undoToast = UndoToastInfo(text: text)
    }

    /// The toast's Undo: the window's undo manager, so it works from a popover too.
    func undoLast() {
        undoToast = nil
        guard let um = undoManager, um.canUndo else { return }
        um.undo()
    }

    /// "Accept the Rest" in the moments: these moments count as reviewed and the step as done; undoable.
    func acceptRest(_ moments: [Int]) {
        guard let tripId, tripId == loadedTripId else { return }
        let added = moments.filter { !reviewedMoments.contains($0) }
        let wasDone = steps["duplicates"] == true
        reviewedMoments.formUnion(added)
        markStep("duplicates")
        registerUndo(name: tr("acceptRest"), trip: tripId) { model in
            model.reviewedMoments.subtract(added)
            if !wasDone { model.markStep("duplicates", false) }
        } redo: { model in
            model.reviewedMoments.formUnion(added)
            model.markStep("duplicates")
        }
        offerUndo(tr("acceptedRest"))
    }

    /// Adds folders to an album (the open one unless `trip` names another). Every folder is tried; refusals are
    /// shown together. The app proposes each folder's owner (and remembers which camera is whose); a new album
    /// that still has its default name gets the name the folders suggest. Before the owner pressed Start nothing
    /// is analysed; afterwards the new photos are sorted at once and the questions open again.
    func addFolders(_ urls: [URL], trip: String? = nil) {
        guard let tripId = trip ?? shownTrip, !urls.isEmpty else { return }
        let isOpen = tripId == shownTrip
        let started = isOpen ? journeyInput.started : true
        let defaultName = isOpen && sources.isEmpty && albumName == tr("newAlbumName")
        Task {
            var problems: [String] = [], added = 0
            do {
                let s = try await api.suggest(paths: urls.map(\.path))
                problems += s.rejected.map { "\(URL(fileURLWithPath: $0.path).lastPathComponent): \(trCode("problem_", $0.problem, other: "problem_other"))" }
                for f in s.folders {
                    let name = URL(fileURLWithPath: f.path).lastPathComponent
                    do { try await api.addFolder(trip: tripId, path: f.path, owner: f.owner.isEmpty ? name : f.owner); added += 1 }
                    catch { problems.append("\(name): \(describe(error))") }
                }
                let learned = devicesToRemember(s.folders.map { (owner: $0.owner, devices: $0.devices.map { ($0.name, $0.count) }) })
                if !learned.isEmpty, let raw = try? await api.settingsRaw() {     // never overwrite the memory on a read error
                    var memory = raw["device_owners"] as? [String: String] ?? [:]
                    memory.merge(learned) { _, new in new }
                    save(["device_owners": memory])
                }
                if added > 0 && defaultName {
                    let suggested = CuratorCore.albumName(place: s.album.place, start: s.album.start, end: s.album.end, lang: lang)
                    if !suggested.isEmpty { renameAlbum(suggested, trip: tripId) }
                }
            } catch { problems.append(describe(error)) }
            if added > 0 {
                if started {
                    // New photos bring new questions and an export that no longer has them: both open again.
                    for w in ["duplicates", "times", "export"] { try? await api.setStep(trip: tripId, step: w, done: false) }
                    do { try await api.startAnalysis(trip: tripId) } catch { problems.append(describe(error)) }
                }
                if tripId == self.tripId {
                    station = nil
                    await reload()
                    await pollOnce()
                } else {
                    trips = (try? await api.trips()) ?? trips
                }
            }
            if !problems.isEmpty {
                errorBanner = ErrorBannerInfo(error: HumanError(kind: .invalid, message: problems.joined(separator: "\n"), details: ""))
            }
        }
    }

    // MARK: events

    func move(toEvent event: Int?, newName: String? = nil) {
        guard let tripId, tripId == loadedTripId else { return }
        let ids = targets.map(\.id)
        guard !ids.isEmpty else { return }
        Task {
            do {
                try await api.move(trip: tripId, ids: ids, toEvent: event, newName: newName)
                message = "\(ids.count) → \(newName ?? events.first { $0.id == event }?.name ?? "")"
                await reload()
            } catch { report(error) }
        }
    }

    // MARK: album assistant

    /// "+ New Album" (⌘N, M14a): makes an empty album and opens it on its first station, where folders are dropped
    /// or added and Start begins the sorting. It arrives in the sidebar at once.
    func newAlbum(with folders: [URL] = []) {
        reviewFilter = nil
        Task {
            do {
                let id = try await api.createAlbum(name: tr("newAlbumName"))
                let list = (try? await api.trips()) ?? trips
                withMotion(.arrive) { trips = list }
                tripId = id
                destination = .journey
                station = nil
                if !folders.isEmpty {
                    await reload()                       // the album is the open one before its folders arrive
                    addFolders(folders)
                }
            } catch { report(error) { [weak self] in self?.newAlbum(with: folders) } }
        }
    }

    /// Keep this frame of a moment; written in order with the other changes.
    func keep(group: Int, photo: Int?) {
        guard let tripId, tripId == loadedTripId else { return }
        reviewedMoments.insert(group)
        pulse(.pick)
        enqueue { api in try await api.keep(trip: tripId, group: group, photo: photo) }
    }

    /// M14c Survey: Return on a moment. The engine keeps one keeper per moment, so the first keeper (the
    /// recommended one when kept) becomes it; other keepers get the "keep" mark ("keep too"), so the export
    /// takes them as well; the rest are left out (`rejected`, reversible in Left Out). Only marks that change
    /// are written; every write is undoable through the menu as well.
    func applySurvey(_ d: SurveyDecision) {
        guard let tripId, tripId == loadedTripId else { return }
        if let primary = d.primary {
            keep(group: d.moment, photo: primary)
            if let p = photo(primary), p.rejected { mark([p], ["rejected": .bool(false)], name: tr("keep")) }
        } else {
            reviewedMoments.insert(d.moment)
        }
        let extras = d.extras.compactMap(photo).filter { !$0.keep || $0.rejected }
        mark(extras, ["keep": .bool(true), "rejected": .bool(false)], name: tr("keepToo"))
        let out = d.leftOut.compactMap(photo).filter { !$0.rejected || $0.keep }
        mark(out, ["rejected": .bool(true), "keep": .bool(false)], name: tr("leaveOut"))
        if d.primary == nil { pulse(.leaveOut) }
    }

    /// M14c Survey: Back over a confirmed moment. Every frame gets its earlier marks, the keeper goes back to the
    /// owner's earlier choice (or the recommendation).
    func undoSurvey(_ e: SurveyEntry) {
        guard let tripId, tripId == loadedTripId, let d = e.decision else { return }
        for (id, previous) in e.previous where marksOf(id) != previous { restore(id, previous) }
        if d.primary != nil {
            let keeper = e.previousKeeper
            enqueue { api in try await api.keep(trip: tripId, group: d.moment, photo: keeper) }
        }
    }

    func markStep(_ step: String, _ done: Bool = true) {
        guard let tripId else { return }
        steps[step] = done
        Task { try? await api.setStep(trip: tripId, step: step, done: done); await reload() }
    }


    func leaveOutAllBlurry() {
        let blurry = photos.filter { $0.focus?.tier == "blurry" && !$0.rejected && !$0.favorite }
        mark(blurry, ["rejected": .bool(true)], name: tr("leaveOutAllBlurry"))
    }

    /// The last finished export of this album (folder and success), for the Export sheet.
    @Published private(set) var lastExport: (folder: String, ok: Bool)?
    func clearLastExport() { lastExport = nil }
    private func jobFinished() {
        if let p = pendingSearch, p.trip == tripId, job.error == nil {
            pendingSearch = nil
            searchText = p.query
            runSearch()
        }
        if let f = job.exportFolder, job.collection == tripId {
            lastExport = (f, job.exportOK ?? false)
            if job.exportOK == true {
                markStep("export")
                if let tripId { UserDefaults.standard.set(f, forKey: "exportFolder.\(tripId)") }
            }
        }
    }

    // MARK: remove album (M14a)

    /// The album whose removal waits for the owner's confirmation (sidebar ⌫, context menu, ⌘⌫, Clear Working Data).
    @Published var removeAlbumRequest: String?

    /// Removes an album and the app's working data for it (after the owner confirmed). The photo folders and any
    /// exported folder are never touched. Opens the next album, or the empty state.
    func removeAlbum(_ id: String) async {
        guard !(job.running && job.collection == id) else {
            errorBanner = ErrorBannerInfo(error: HumanError(kind: .busy, message: tr("removeAlbumBusy"), details: ""))
            return
        }
        do {
            let r = try await api.finishAlbum(trip: id)
            let name = trips.first { $0.id == id }?.name ?? id
            withMotion(.settle) { trips.removeAll { $0.id == id } }
            snapshots[id] = nil
            saveSnapshots()
            for f in ReviewFilter.allCases { UserDefaults.standard.removeObject(forKey: "review.\(id).\(f.rawValue)") }
            UserDefaults.standard.removeObject(forKey: "exportFolder.\(id)")
            if tripId == id { tripId = trips.first?.id }
            let mb = max(1, Int((Double(r.freedBytes) / 1_048_576).rounded()))
            message = String(format: tr("albumRemoved"), name, mb)
        } catch { report(error) { [weak self] in Task { await self?.removeAlbum(id) } } }
    }

    /// Takes one folder out of the open album (after the owner confirmed). Only the app's data for it goes; the
    /// days that lost photos are sorted again by the engine at once.
    func removeFolder(_ source: SourceInfo) {
        guard let trip = shownTrip else { return }
        Task {
            do {
                _ = try await api.removeSource(trip: trip, source: source.id)
                guard trip == tripId else { return }
                sortStream = SortStream()
                undoManager?.removeAllActions()           // photo ids of the removed folder are gone
                undoToast = nil
                station = nil
                await reload()
                message = String(format: tr("folderRemoved"), source.owner)
            } catch { report(error) { [weak self] in self?.removeFolder(source) } }
        }
    }

    // MARK: search

    /// A search that waits for the search index (first search of the album); it runs again when the index is ready.
    private var pendingSearch: (trip: String, query: String)?

    func runSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard let tripId, !q.isEmpty else { return }
        searching = true
        Task {
            defer { searching = false }
            do {
                let r = try await api.search(trip: tripId, query: q)
                if r.preparing == true {
                    pendingSearch = (tripId, q)
                    message = tr("preparingSearch")
                    await pollOnce()
                    return
                }
                pendingSearch = nil
                searchResult = r
                destination = .search
            } catch { report(error) { [weak self] in self?.runSearch() } }
        }
    }

    // MARK: jobs

    /// The sorting stage (the path's second station); `replay` plays it again from the folders to the overview.
    func showSorting(replay: Bool = false) {
        reviewFilter = nil
        open(station: .analysis)
        if replay { pendingReplay = true }
    }

    func analyse() {
        guard let tripId else { return }
        Task { do { try await api.startAnalysis(trip: tripId); await pollOnce() } catch { report(error) { [weak self] in self?.analyse() } } }
    }
    /// Stops the running job (analysis or export); a failure to stop is shown, never swallowed (M12e).
    func stopJob() {
        guard let tripId else { return }
        Task {
            do { try await api.stopJob(trip: tripId); await pollOnce() }
            catch { report(error) { [weak self] in self?.stopJob() } }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()
                if self.analysing { await self.pollEvents() }
                if self.job.running, let id = self.tripId, self.job.collection == id, self.pollCount % 4 == 0 {
                    self.overview = (try? await self.api.overview(trip: id)) ?? self.overview
                    // New photos were read: show them while the rest of the analysis runs.
                    if let n = self.overview?.facts.photos, n != self.photos.count { await self.reload() }
                }
                self.pollCount += 1
                let wait = eventPollInterval(running: self.job.running, morePending: false) ?? 4.0
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
            }
        }
    }

    func pollNow() async { await pollOnce() }

    private var pollCount = 0
    private func pollOnce() async {
        guard let tripId, let s = try? await api.jobStatus(trip: tripId) else { return }
        let wasRunning = job.running
        if s.collection == nil || s.collection == tripId || s.running { if job != s { job = s } }
        // A job that ended between two polls is still noticed here (export result, reload).
        if wasRunning && !job.running {
            await pollEvents()                                   // the last events (final keepers) before the reload
            await reload(); analysisFinishedTick += 1; jobFinished()
            // The window was closed while sorting ("I keep working"): the work is done, so the app quits now.
            if !NSApp.windows.contains(where: { $0.identifier?.rawValue.hasPrefix("main") == true && ($0.isVisible || $0.isMiniaturized) }) {
                NSApp.terminate(nil)
            }
        }
        refreshSnapshot()
    }

    /// M13: reads the new events of the analysis (a few pages per poll at most) and fetches the photos again when
    /// a day settled or photos were judged, at most every 2 s, so a 3,000-photo album is not reloaded per event.
    /// Only called while this album's analysis runs and once when it ends: no polling when idle.
    func pollEvents() async {
        guard let trip = tripId else { return }
        if streamTrip != trip { sortStream = SortStream(); streamTrip = trip }
        var pages = 0
        var change = SortStreamChange()
        while pages < 4 {
            guard let page = try? await api.analysisEvents(trip: trip, since: sortStream.cursor) else { break }
            guard trip == tripId else { return }
            var stream = sortStream
            let c = stream.merge(page: page)
            // Publish only when something moved (every view of the library redraws on a publish).
            if stream.cursor != sortStream.cursor || stream.revision != sortStream.revision { sortStream = stream }
            change.arrived += c.arrived
            change.judged += c.judged
            change.settledDays += c.settledDays
            pages += 1
            if !page.more { break }
        }
        if shouldReloadPhotos(after: change, secondsSinceReload: Date().timeIntervalSince(lastStreamReload)) {
            lastStreamReload = Date()
            await reload()
        }
    }
    /// Analysis of this album runs (not descriptions or an export).
    var analysing: Bool { job.running && job.collection == tripId && (job.kind ?? "analysis") == "analysis" }

    // MARK: settings

    func save(_ changes: [String: Any], then: (() async -> Void)? = nil) {
        guard let json = try? JSONSerialization.data(withJSONObject: changes) else { return }
        Task {
            do { settings = try await api.saveSettings(json: json); await then?() } catch { report(error) }
        }
    }

    func loadSettings() async {
        if let s = try? await api.settings() { settings = s }
        speed = try? await api.speed()
    }

    /// The quality check's strictness changes the verdicts at once; the album is read again to show them.
    func setStrictness(_ level: String) {
        guard EngineSettings.strictnessLevels.contains(level), level != settings?.qualityStrictness else { return }
        settings?.qualityStrictness = level
        save(["quality_strictness": level]) { [weak self] in await self?.reload() }
    }

    /// The human sentence for an error (CuratorCore `humanError`); the raw text goes to the banner's Details.
    func describe(_ error: Error) -> String { humanError(error, lang).message }

    /// Shows an error in the sticky banner (M12e, #8), with Try Again when `retry` is given.
    func report(_ error: Error, retry: (@MainActor () -> Void)? = nil) {
        errorBanner = ErrorBannerInfo(error: humanError(error, lang), retry: retry)
    }

    // MARK: M12e flow helpers

    /// A tray of the sorting stage to open when the stage shows (the funnel's "screenshots" opens "Left out").
    @Published var pendingTray: SortVerdict?
    func openTray(_ tray: SortVerdict) {
        reviewFilter = nil
        pendingTray = tray
        open(station: .analysis)
    }

    /// Photos the next quick review goes through instead of the filter's queue (a tray's photos). The review
    /// takes them once with `takeReviewSubset()` when it starts.
    private(set) var reviewSubset: [Int]?
    func startReview(_ f: ReviewFilter, ids: [Int]) {
        guard !ids.isEmpty, loadedTripId != nil, !photos.isEmpty else { return }
        reviewSubset = ids
        reviewFilter = f
    }
    func takeReviewSubset() -> [Int]? {
        defer { reviewSubset = nil }
        return reviewSubset
    }

    /// Quick Look on photos that are not the grid's (the stage, a tray), starting at `id`.
    func quickLook(ids: [Int], at id: Int) {
        let urls = ids.compactMap(photo).map(\.fileURL)
        guard let url = photo(id)?.fileURL, !urls.isEmpty else { return }
        if quickLookURL == url { quickLookURL = nil; return }
        quickLookItems = urls
        quickLookURL = url
    }

    /// K in the grid: the targets go back into the album (same as Put back), confirmed with Undo.
    func keepTargets() { offerUndo(.putBack, count: setInAlbum(targets.map(\.id), true)) }
    /// X in the grid: the targets leave the album (no toggle: K brings them back), confirmed with Undo.
    func leaveOutTargets() { offerUndo(.leaveOut, count: setInAlbum(targets.map(\.id), false)) }

    // MARK: M14a the album's path

    /// What the path needs to know about the open album, from the model's data.
    var journeyInput: JourneyInput {
        let o = overview
        let mine = job.collection == tripId
        let analysisJob = (job.kind ?? "analysis") == "analysis"
        let streamDays = analysing ? Set(sortStream.dayOf.values).count : 0
        let total = max(o?.analysis?.days ?? 0, streamDays)
        let settled = max(o?.analysis?.settled ?? 0, analysing ? sortStream.settledCount : 0)
        let started = steps["import"] == true || (o?.analysis?.settled ?? 0) > 0 || photos.contains { $0.focus != nil }
        let albumCount: Int? = o?.funnel?.inAlbum ?? o?.export.photos
        let inAlbum: Int = exportPreviewCount ?? albumCount ?? photos.filter(\.goesToAlbumDespiteFocus).count
        return JourneyInput(
            folders: sources.count,
            photos: photos.count,
            started: started,
            analysing: analysing,
            analysisFailed: mine && !job.running && analysisJob && job.phase == .failed,
            progress: analysing ? job.progress / 100 : 0,
            daysTotal: total,
            daysSettled: min(settled, total),
            openMoments: o?.moments.needYou ?? 0,
            haveALook: lookCount,
            unsureClocks: o?.clocks.pending ?? 0,
            decisionsDone: steps["duplicates"] == true,
            inAlbum: inAlbum,
            exporting: mine && job.running && job.kind == "export",
            exportProgress: mine && job.kind == "export" ? job.progress / 100 : 0,
            exported: exported)
    }

    /// The open album's path: current station, the one primary action, the status line.
    var journey: AlbumJourney { AlbumJourney(journeyInput) }

    /// The station on screen: the one opened on the rail while it can be opened, else the current one.
    var shownStation: JourneyStation { journey.shown(station) }

    /// Opens the album's path on a station (nil: the current one). A station ahead of the album opens the current one.
    func open(station s: JourneyStation?) {
        reviewFilter = nil
        destination = .journey
        station = s.flatMap { journey.canOpen($0) ? $0 : nil }
    }

    /// The one primary button of the path.
    func performPrimary() {
        switch journey.action {
        case .addFolders: chooseFolders()
        case .start: startAlbum()
        case .resume, .retry: station = nil; analyse()
        case .wait, .exporting: break
        case .answer: answerQuestions()
        case .export: requestExport()
        case .openFolder: openExportFolder()
        }
    }

    /// Start: the owner is done adding folders; sorting begins (the path moves on to Sorting).
    func startAlbum() {
        guard let tripId = shownTrip else { return }
        steps["import"] = true
        station = nil
        Task {
            try? await api.setStep(trip: tripId, step: "import", done: true)
            do { try await api.startAnalysis(trip: tripId); await pollOnce() }
            catch { report(error) { [weak self] in self?.startAlbum() } }
        }
    }

    /// The system folder panel; the chosen folders go to `trip` (the open album when nil).
    func chooseFolders(trip: String? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = tr("addFolders")
        panel.message = tr("chooseFoldersMessage")
        guard panel.runModal() == .OK else { return }
        addFolders(panel.urls, trip: trip)
    }

    /// Changes on every Export press of the path; the album station's export panel opens its folder panel.
    @Published var exportRequest = 0
    /// An Export press waits for the export panel (it may be appearing, or its preview still loading).
    var exportPending = false
    /// Export: goes to the Album station and asks its export panel to choose a folder as soon as it is ready.
    func requestExport() {
        station = nil
        exportPending = true
        exportRequest += 1
    }
    /// How many photos the export panel's current choice would copy (the primary button's number); nil when the
    /// panel is not on screen (the album's own count is used then).
    @Published var exportPreviewCount: Int?

    /// The folder of this album's last verified export (remembered across launches).
    var exportFolder: String? {
        if let last = lastExport, last.ok { return last.folder }
        guard let tripId else { return nil }
        return UserDefaults.standard.string(forKey: "exportFolder.\(tripId)")
    }

    func openExportFolder() {
        guard let f = exportFolder, FileManager.default.fileExists(atPath: f) else {
            requestExport()                                 // the folder is gone or unknown: export again
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: f))
    }

    // MARK: questions (station 3)

    /// The question review runs for the path: when it ends, the questions count as answered.
    private var questionReview = false

    /// The open questions (M14c): moments without a clear best frame go to Survey, the "Have a look" photos that
    /// are not frames of those moments to the single review afterwards (time order).
    func questions() async -> (moments: [SurveyMoment], singles: [Int]) {
        guard let trip = shownTrip else { return ([], []) }
        let unclear = ((try? await api.moments(trip: trip)) ?? []).filter { !$0.clear && $0.members.count > 1 }
        let inMoments = Set(unclear.flatMap { $0.members.map(\.id) })
        let singles = photos.filter { sortVerdict($0) == .check && !inMoments.contains($0.id) }.map(\.id)
        return (unclear.map { SurveyMoment($0) }, singles)
    }

    /// "Answer N questions": Survey over the unclear moments, then a quick review of the other photos.
    func answerQuestions() {
        Task {
            let q = await questions()
            if q.moments.isEmpty && q.singles.isEmpty {
                // Only clocks are left: they are answered on People & Clocks.
                if journeyInput.unsureClocks > 0 { destination = .people } else { acceptQuestions() }
                return
            }
            guard loadedTripId != nil, !photos.isEmpty else { return }
            questionReview = true
            reviewSubset = q.singles
            surveyRequest = q.moments.isEmpty ? nil : SurveyRequest(moments: q.moments, standalone: false)
            reviewFilter = .decisions
        }
    }

    /// Accept the rest: what the app chose stays; the questions count as answered (undoable).
    func acceptQuestions() {
        guard let tripId, tripId == loadedTripId else { return }
        let was = (steps["duplicates"] == true, steps["times"] == true)
        markStep("duplicates")
        markStep("times")
        registerUndo(name: tr("acceptRest"), trip: tripId) { model in
            if !was.0 { model.markStep("duplicates", false) }
            if !was.1 { model.markStep("times", false) }
        } redo: { model in
            model.markStep("duplicates")
            model.markStep("times")
        }
        offerUndo(tr("acceptedRest"))
    }

    /// The quick review closed. A finished question review answers the questions; the path moves on.
    func reviewClosed(finished: Bool) {
        if questionReview && finished {
            markStep("duplicates")
            if journeyInput.unsureClocks == 0 { markStep("times") }
            station = nil
        }
        questionReview = false
    }

    // MARK: sidebar status per album

    @Published private(set) var snapshots: [String: JourneySnapshot] = [:]
    private static let snapshotsKey = "journey.snapshots.v1"

    private static func loadSnapshots() -> [String: JourneySnapshot] {
        guard let data = UserDefaults.standard.data(forKey: snapshotsKey),
              let s = try? JSONDecoder().decode([String: JourneySnapshot].self, from: data) else { return [:] }
        return s
    }

    private func saveSnapshots() {
        if let data = try? JSONEncoder().encode(snapshots) { UserDefaults.standard.set(data, forKey: Self.snapshotsKey) }
    }

    /// Remembers the open album's state for the sidebar (only when it changed).
    func refreshSnapshot() {
        guard let id = shownTrip else { return }
        let cover = albumCover(photos, coverId: overview?.coverId, highlights: overview?.highlights ?? [])
        let snap = JourneySnapshot(input: journeyInput, coverPath: cover?.fileURL.path)
        if snapshots[id] != snap {
            snapshots[id] = snap
            saveSnapshots()
        }
    }

    /// The path of any album: live for the open one, else the last known state corrected by the running job.
    func journeyOf(_ trip: Trip) -> AlbumJourney? {
        if trip.id == shownTrip { return journey }
        guard var input = snapshots[trip.id]?.input else { return nil }
        let runs = job.running && job.collection == trip.id
        input.analysing = runs && (job.kind ?? "analysis") == "analysis"
        input.exporting = runs && job.kind == "export"
        if input.analysing { input.progress = job.progress / 100 }
        if input.exporting { input.exportProgress = job.progress / 100 }
        return AlbumJourney(input)
    }

    /// The sidebar's line under an album's name.
    func statusLine(for trip: Trip) -> String {
        if let j = journeyOf(trip) { return j.status(lang) }
        return trip.assets == 0 ? tr("journeyNoPhotos") : Strings.photos(trip.assets, lang)
    }

    /// The cover file of any album (open: live; others: remembered).
    func coverURL(for trip: Trip) -> URL? {
        if trip.id == shownTrip {
            return albumCover(photos, coverId: overview?.coverId, highlights: overview?.highlights ?? [])?.fileURL
        }
        return snapshots[trip.id]?.coverPath.map { URL(fileURLWithPath: $0) }
    }
}
