import AppKit
import CuratorCore
import Foundation
import SwiftUI

/// Sidebar destinations.
enum Destination: Hashable {
    case all, favourites, leftOut, videos, day(String), search
}

/// The app's state for one window: trips, the current trip's photos, selection, marks with undo,
/// search, and the engine's background job.
@MainActor final class LibraryModel: ObservableObject {
    let api: APIClient

    @Published var trips: [Trip] = []
    @Published var tripId: String? { didSet { if tripId != oldValue { tripChanged() } } }
    @Published private(set) var photos: [Photo] = []
    @Published private(set) var events: [TripEvent] = []
    @Published private(set) var sources: [SourceInfo] = []
    @Published var destination: Destination = .all { didSet { if destination != oldValue { clearSelection() } } }
    @Published var sort: PhotoSort = .time
    @Published var selection: Set<Int> = []
    @Published var cursor: Int = -1                     // flat index into `flat`
    @Published var tileSize: Double = 190
    @Published var searchText = ""
    @Published private(set) var searchResult: SearchResult?
    @Published private(set) var searching = false
    @Published var settings: EngineSettings?
    @Published var message: String?                     // transient error or info for the user
    @Published private(set) var job = JobStatus(running: false, status: "")
    @Published private(set) var loading = false

    weak var undoManager: UndoManager?
    private var pollTask: Task<Void, Never>?

    init(api: APIClient) { self.api = api }

    var lang: Lang { Lang(rawValue: settings?.uiLanguage ?? "en") ?? .en }
    func tr(_ key: String) -> String { Strings.text(key, lang) }

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
        } catch { message = describe(error) }
    }

    private func tripChanged() {
        undoManager?.removeAllActions()            // undo must never write into another trip
        clearSelection()
        searchResult = nil
        searchText = ""
        if destination == .search { destination = .all }
        if let tripId { UserDefaults.standard.set(tripId, forKey: "trip") }
        Task { await reload() }
    }

    func reload() async {
        guard let tripId else { photos = []; events = []; return }
        loading = true
        defer { loading = false }
        do {
            async let t = api.timeline(trip: tripId)
            async let s = api.sources(trip: tripId)
            let (timeline, src) = try await (t, s)
            guard tripId == self.tripId else { return }
            photos = timeline.items
            events = timeline.events
            sources = src
            if cursor >= flat.count { cursor = flat.count - 1 }
        } catch { message = describe(error) }
    }

    // MARK: what the grid shows

    var filter: LibraryFilter {
        switch destination {
        case .all: return .all
        case .favourites: return .favourites
        case .leftOut: return .leftOut
        case .videos: return .videos
        case .day(let d): return .day(d)
        case .search: return .ids(searchResult?.results.map(\.id) ?? [])
        }
    }
    var visibleSections: [PhotoSection] { sections(photos, events: events, filter: filter, sort: destination == .search ? .time : sort) }
    var flat: [Photo] { visibleSections.flatMap(\.photos) }
    var days: [String] { Array(Set(photos.filter { !$0.rejected }.map(\.day))).sorted() }
    var selectedPhotos: [Photo] { flat.filter { selection.contains($0.id) } }
    var single: Photo? { selection.count == 1 ? photos.first { selection.contains($0.id) } : nil }
    func count(_ d: Destination) -> Int {
        switch d {
        case .all: return photos.filter { !$0.rejected }.count
        case .favourites: return photos.filter(\.favorite).count
        case .leftOut: return photos.filter(\.rejected).count
        case .videos: return photos.filter { $0.isVideo && !$0.rejected }.count
        case .day(let day): return photos.filter { $0.day == day && !$0.rejected }.count
        case .search: return searchResult?.results.count ?? 0
        }
    }
    /// Photos not analysed yet (no focus data) shimmer while a job runs.
    func isPending(_ p: Photo) -> Bool { job.running && !p.isVideo && p.focus == nil }

    // MARK: selection

    func clearSelection() { selection = []; cursor = -1 }

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
        case "rejected": return .bool(p.rejected)
        case "wallpaper": return .bool(p.wallpaper)
        default: return p.focus?.override.map { .string($0) } ?? .null
        }
    }

    /// Applies marks to photos, registers undo with each photo's previous values.
    func mark(_ items: [Photo], _ fields: [String: MarkValue], name: String) {
        guard let tripId, !items.isEmpty else { return }
        let previous = items.map { p in (p.id, Dictionary(uniqueKeysWithValues: fields.keys.map { ($0, current(p, $0)) })) }
        let ids = items.map(\.id)
        apply(ids: ids, fields)                                  // the grid reacts at once
        Task {
            do {
                try await api.setMarks(trip: tripId, ids: ids, fields)
                registerUndo(name: name, trip: tripId) { model in
                    for (id, f) in previous { model.apply(ids: [id], f) }
                    for (id, f) in previous { try await model.api.setMark(trip: tripId, id: id, f) }
                } redo: { model in
                    model.apply(ids: ids, fields)
                    try await model.api.setMarks(trip: tripId, ids: ids, fields)
                }
                await reload()
            } catch { message = describe(error); await reload() }
        }
    }

    private func registerUndo(name: String, trip: String,
                              undo: @escaping @MainActor (LibraryModel) async throws -> Void,
                              redo: @escaping @MainActor (LibraryModel) async throws -> Void) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.tripId == trip else { return }
                Task { do { try await undo(model) } catch { model.message = model.describe(error) }; await model.reload() }
                model.registerUndo(name: name, trip: trip, undo: redo, redo: undo)
            }
        }
        um.setActionName(name)
    }

    /// Local, optimistic copy of the marks so the grid updates without waiting for the engine.
    private func apply(ids: [Int], _ fields: [String: MarkValue]) {
        let set = Set(ids)
        for i in photos.indices where set.contains(photos[i].id) {
            for (k, v) in fields {
                switch (k, v) {
                case ("favorite", .bool(let b)): photos[i].favorite = b
                case ("rejected", .bool(let b)): photos[i].rejected = b
                case ("wallpaper", .bool(let b)): photos[i].wallpaper = b
                default: break
                }
            }
        }
    }

    // MARK: events

    func move(toEvent event: Int?, newName: String? = nil) {
        guard let tripId else { return }
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

    // MARK: search

    func runSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard let tripId, !q.isEmpty else { return }
        searching = true
        Task {
            defer { searching = false }
            do {
                searchResult = try await api.search(trip: tripId, query: q)
                destination = .search
            } catch { message = describe(error) }
        }
    }

    // MARK: jobs

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
                let wasRunning = self.job.running
                await self.pollOnce()
                if wasRunning && !self.job.running { await self.reload() }
                try? await Task.sleep(for: .milliseconds(self.job.running ? 700 : 4000))
            }
        }
    }

    private func pollOnce() async {
        guard let tripId, let s = try? await api.jobStatus(trip: tripId) else { return }
        if s.collection == nil || s.collection == tripId || s.running { job = s }
    }

    // MARK: settings

    func save(_ changes: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: changes) else { return }
        Task { do { settings = try await api.saveSettings(json: json) } catch { message = describe(error) } }
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
