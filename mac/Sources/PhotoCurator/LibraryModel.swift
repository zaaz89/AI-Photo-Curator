import AppKit
import CuratorCore
import Foundation
import SwiftUI

/// Sidebar destinations.
enum Destination: Hashable {
    case home, step(GuideStep), people, all, favourites, leftOut, videos, blurry, day(String), search, settings, sorting
    /// The guide's pages (album home, the steps, people and clocks, settings), not a photo grid.
    var isGuide: Bool {
        switch self { case .home, .step, .people, .settings, .sorting: true; default: false }
    }
}

/// The Selection step's three views.
enum SelectionView: String, CaseIterable, Identifiable {
    case moments, blurry, leftOut
    var id: String { rawValue }
}

/// The sheets of the album assistant.
enum AssistantSheet: String, Identifiable {
    case newAlbum
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
            recompute()
        }
    }
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
    @Published var sheet: AssistantSheet?
    /// Moments the owner went through in this session; a reopened sheet continues after them.
    var reviewedMoments: Set<Int> = []
    var exported: Bool { steps["export"] == true }
    static let stepOrder = ["import", "times", "duplicates", "blurry", "events", "export"]
    var stepsDone: Int { Self.stepOrder.filter(isDone).count }
    /// A step is done when the owner marked it, or when there is nothing left to decide in it.
    func isDone(_ step: String) -> Bool {
        if steps[step] == true { return true }
        guard let o = overview, !o.analysing, !(job.running && job.collection == tripId) else { return false }
        switch step {
        case "times": return o.clocks.pending == 0
        case "duplicates": return o.moments.needYou == 0
        case "blurry": return o.blurry.total == 0
        case "export": return o.export.done
        default: return false
        }
    }
    /// The four steps' state (done, waiting decisions), recomputed with the overview.
    var stepStates: [GuideStep: StepState] {
        var s = CuratorCore.stepStates(overview, marked: steps, analysing: analysing)
        if steps["export"] == true { s[.export]?.done = true }
        return s
    }
    var next: GuideStep? { nextStep(stepStates) }
    /// Clock suggestions nobody answered yet: they come before the steps on the album home.
    var clocksWaiting: Int { CuratorCore.clocksWaiting(overview, marked: steps, analysing: analysing) }
    @Published var selectionView: SelectionView = .moments
    @Published var destination: Destination = .home { didSet { if destination != oldValue { clearSelection(); recompute() } } }
    @Published var sort: PhotoSort = .time { didSet { recompute() } }
    @Published var selection: Set<Int> = []
    @Published var cursor: Int = -1                     // flat index into `flat`
    @Published var tileSize: Double = 190
    @Published var searchText = ""
    @Published var searchFocusRequest = 0               // ⌘F: the window moves focus to the search field
    @Published private(set) var searchResult: SearchResult? { didSet { recompute() } }
    @Published private(set) var searching = false
    @Published var settings: EngineSettings?
    /// The measured speed of this Mac for the time estimate (nil before the first analysis).
    @Published var speed: EngineSpeed?
    /// The sorting stage should play again from the folders when it next shows (or now, when it shows already).
    @Published var pendingReplay = false
    /// Changes after an analysis of this album ended and its photos were read again (the stage's cue).
    @Published private(set) var analysisFinishedTick = 0
    @Published var message: String?                     // transient error or info for the user
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

    init(api: APIClient) { self.api = api }

    var lang: Lang { Lang(rawValue: settings?.uiLanguage ?? "en") ?? .en }
    func tr(_ key: String) -> String { Strings.text(key, lang) }
    /// A text for a value from the engine; the engine's own words when there is no translation.
    func trOr(_ key: String, _ fallback: String) -> String { Strings.table[key] == nil ? fallback : Strings.text(key, lang) }

    // MARK: loading

    func start() async {
        settings = try? await api.settings()
        await loadTrips()
        startPolling()
    }

    func loadTrips() async {
        do {
            trips = try await api.trips()
            if trips.isEmpty { sheet = .newAlbum }              // first start: the wizard opens by itself
            let saved = UserDefaults.standard.string(forKey: "trip")
            if tripId == nil || !trips.contains(where: { $0.id == tripId }) {
                tripId = trips.first(where: { $0.id == saved })?.id ?? trips.first?.id
            }
        } catch { message = describe(error) }
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
        clearSelection()
        searchResult = nil
        searchText = ""
        destination = .home
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
        } catch { message = describe(error) }
    }

    // MARK: what the grid shows

    var filter: LibraryFilter {
        switch destination {
        case .all: return .all
        case .favourites: return .favourites
        case .leftOut: return .leftOut
        case .videos: return .videos
        case .blurry: return .blurry
        case .home, .step, .people, .settings, .sorting: return .all
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
        case .home, .step, .people, .settings, .sorting: return 0
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
    func toggleLeaveOut() { let t = targets; mark(t, ["rejected": .bool(!t.allSatisfy(\.rejected))], name: tr("leaveOut")) }
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
            do { try await write(api) } catch { self?.message = self?.describe(error) }
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
            catch { message = describe(error) }
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
            case "home": destination = .home
            case "selection": destination = .step(.selection)
            case "story": destination = .step(.story)
            case "export": destination = .step(.export)
            case "people": destination = .people
            case "all": destination = .all
            case "settings": destination = .settings
            case "sorting": destination = .sorting
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
        }
    }

    /// How many photos need a yes or no (the quick review's default).
    var decisionsCount: Int { photos.filter(needsDecision).count }
    func startReview(_ f: ReviewFilter = .decisions) { if loadedTripId != nil && !photos.isEmpty { reviewFilter = f } }

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
        return items.count
    }

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

    /// Adds folders to the open album and analyses the new photos. Every folder is tried; refusals are shown
    /// together, and the analysis starts when at least one folder was added.
    func addFolders(_ urls: [URL]) {
        guard let tripId, tripId == loadedTripId, !urls.isEmpty else { return }
        Task {
            var problems: [String] = [], added = 0
            do {
                let s = try await api.suggest(paths: urls.map(\.path))
                problems += s.rejected.map { "\(URL(fileURLWithPath: $0.path).lastPathComponent): \(trOr("problem_" + $0.problem, $0.problem))" }
                for f in s.folders {
                    let name = URL(fileURLWithPath: f.path).lastPathComponent
                    do { try await api.addFolder(trip: tripId, path: f.path, owner: f.owner.isEmpty ? name : f.owner); added += 1 }
                    catch { problems.append("\(name): \(describe(error))") }
                }
            } catch { problems.append(describe(error)) }
            if added > 0 {
                do { try await api.startAnalysis(trip: tripId) } catch { problems.append(describe(error)) }
                await reload()
                await pollOnce()
            }
            if !problems.isEmpty { message = problems.joined(separator: " · ") }
        }
    }

    /// The guide's Next: marks this step's checklist entries done and opens the next step.
    func finishStep(_ step: GuideStep) {
        guard let tripId else { return }
        for w in step.workflowSteps where w != "export" { steps[w] = true }
        Task {
            for w in step.workflowSteps where w != "export" { try? await api.setStep(trip: tripId, step: w, done: true) }
            overview = (try? await api.overview(trip: tripId)) ?? overview
        }
        destination = step.next.map { .step($0) } ?? .home
    }

    /// Done on the People & clocks page: the owner has seen the clocks; back to the album.
    func finishPeople() {
        guard let tripId else { return }
        for w in ["import", "times"] { steps[w] = true }
        Task {
            for w in ["import", "times"] { try? await api.setStep(trip: tripId, step: w, done: true) }
            overview = (try? await api.overview(trip: tripId)) ?? overview
        }
        destination = .home
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
            } catch { message = describe(error) }
        }
    }

    // MARK: album assistant

    /// Creates the album from the wizard, remembers which device belongs to whom, starts the analysis.
    func createAlbum(name: String, folders: [(path: String, owner: String, devices: [(String, Int)])]) async -> Bool {
        var created: String?
        do {
            let id = try await api.createAlbum(name: name)
            created = id
            for f in folders { try await api.addFolder(trip: id, path: f.path, owner: f.owner) }
            try? await api.setStep(trip: id, step: "import", done: true)
            let learned = devicesToRemember(folders.map { (owner: $0.owner, devices: $0.devices) })
            if !learned.isEmpty, let raw = try? await api.settingsRaw() {     // never overwrite the memory on a read error
                var memory = raw["device_owners"] as? [String: String] ?? [:]
                memory.merge(learned) { _, new in new }
                save(["device_owners": memory])
            }
            trips = (try? await api.trips()) ?? trips
            tripId = id
            try await api.startAnalysis(trip: id)
            destination = .sorting                     // a new album is sorted in front of the owner
            await pollNow()
            return true
        } catch {
            // A half-made album (a folder was refused) is removed so it does not linger unseen.
            if let id = created, tripId != id { _ = try? await api.finishAlbum(trip: id) }
            message = describe(error)
            return false
        }
    }

    /// Keep this frame of a moment; written in order with the other changes.
    func keep(group: Int, photo: Int?) {
        guard let tripId, tripId == loadedTripId else { return }
        reviewedMoments.insert(group)
        enqueue { api in try await api.keep(trip: tripId, group: group, photo: photo) }
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
            if job.exportOK == true { markStep("export") }
        }
    }

    // MARK: finish album

    /// Deletes the app's working data for the current album (after the owner confirmed) and
    /// opens the next album. The photo folders are not touched.
    func finishAlbum() async {
        guard let id = tripId, !(job.running && job.collection == id) else { return }
        do {
            let r = try await api.finishAlbum(trip: id)
            let name = trips.first { $0.id == id }?.name ?? id
            trips.removeAll { $0.id == id }
            tripId = trips.first?.id
            let mb = max(1, Int((Double(r.freedBytes) / 1_048_576).rounded()))
            message = String(format: tr("albumFinished"), name, mb)
        } catch { message = describe(error) }
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
            } catch { message = describe(error) }
        }
    }

    // MARK: jobs

    /// The sorting stage; `replay` plays it again from the folders to the overview.
    func showSorting(replay: Bool = false) {
        reviewFilter = nil
        destination = .sorting
        if replay { pendingReplay = true }
    }

    func analyse() {
        guard let tripId else { return }
        Task { do { try await api.startAnalysis(trip: tripId); await pollOnce() } catch { message = describe(error) } }
    }
    func stopJob() { guard let tripId else { return }; Task { try? await api.stopJob(trip: tripId) } }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()
                if self.job.running, let id = self.tripId, self.job.collection == id, self.pollCount % 4 == 0 {
                    self.overview = (try? await self.api.overview(trip: id)) ?? self.overview
                    // New photos were read: show them while the rest of the analysis runs.
                    if let n = self.overview?.facts.photos, n != self.photos.count { await self.reload() }
                }
                self.pollCount += 1
                try? await Task.sleep(for: .milliseconds(self.job.running ? 700 : 4000))
            }
        }
    }

    func pollNow() async { await pollOnce() }

    private var pollCount = 0
    private func pollOnce() async {
        guard let tripId, let s = try? await api.jobStatus(trip: tripId) else { return }
        let wasRunning = job.running
        if s.collection == nil || s.collection == tripId || s.running { job = s }
        // A job that ended between two polls is still noticed here (export result, reload).
        if wasRunning && !job.running { await reload(); analysisFinishedTick += 1; jobFinished() }
    }
    /// Analysis of this album runs (not descriptions or an export).
    var analysing: Bool { job.running && job.collection == tripId && (job.kind ?? "analysis") == "analysis" }

    // MARK: settings

    func save(_ changes: [String: Any], then: (() async -> Void)? = nil) {
        guard let json = try? JSONSerialization.data(withJSONObject: changes) else { return }
        Task {
            do { settings = try await api.saveSettings(json: json); await then?() } catch { message = describe(error) }
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

    func describe(_ error: Error) -> String {
        switch error {
        case APIError.engine(let e): return e
        case APIError.unreachable: return tr("engineUnreachable")
        case APIError.http(let c): return "HTTP \(c)"
        default: return error.localizedDescription
        }
    }
}
