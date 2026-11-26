import CuratorCore
import QuickLook
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.openWindow) private var openWindow
    @State private var showInspector = true
    @State private var newEvent = false
    @State private var firstRunNewAlbum = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            AlbumSidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            DetailPage()
                .id(pageKey)
                .transition(.opacity)
                .motionAnimation(.settle, value: pageKey)
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .searchable(text: $library.searchText, placement: .toolbar, prompt: library.tr("searchPrompt"))
                .searchFocused($searchFocused)
                .onSubmit(of: .search) { library.runSearch() }
                .onChange(of: library.searchFocusRequest) { _, _ in searchFocused = true }
                .inspector(isPresented: Binding(get: { showInspector && !library.destination.isPage && !library.trips.isEmpty },
                                                set: { showInspector = $0 })) {
                    InspectorView().inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
                .overlay(alignment: .bottom) {
                    VStack(spacing: Space.m) {
                        UndoToast()
                        if library.selection.count > 1 {
                            SelectionBar(newEvent: $newEvent)
                                .padding(.bottom, Space.xl)
                                .motionTransition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    // Above the path's primary bar, never on top of it.
                    .padding(.bottom, library.destination == .journey ? JourneyLayout.barHeight : 0)
                }
                .overlay(alignment: .top) {
                    VStack(spacing: Space.m) {
                        ErrorBannerHost()
                        MessageBanner()
                    }
                }
                .motionAnimation(.arrive, value: library.errorBanner)
                .motionAnimation(.arrive, value: library.selection.count > 1)
                .sheet(isPresented: $newEvent) { NewEventSheet() }
                .quickLookPreview($library.quickLookURL, in: library.quickLookItems)
        }
        // Under the quick review nothing else takes keys or clicks (a hidden page would act on its own photos).
        .disabled(library.reviewFilter != nil)
        .overlay { AIGlow(active: library.job.running && library.job.phase.isAI) }
        .overlay {
            if let f = library.reviewFilter {
                QuickReviewView(filter: f).transition(.opacity)
            }
        }
        .motionAnimation(.settle, value: library.reviewFilter)
        // M12f: a light haptic on keep / leave out / compare pick (Force Touch trackpads; nothing elsewhere).
        .sensoryFeedback(trigger: library.decisionPulse) { _, new in new.tick == 0 ? nil : new.kind.sensory }
        // M12f first run: once, skippable; "Create an Album" makes a new album after this sheet has closed.
        .sheet(isPresented: Binding(get: { library.firstRunPage != nil }, set: { if !$0 { library.firstRunPage = nil } }),
               onDismiss: firstRunClosed) {
            FirstRunView(wantsNewAlbum: $firstRunNewAlbum)
        }
        .removeAlbumConfirmation()
        .onAppear {
            if FirstRun.shouldShow(seen: UserDefaults.standard.bool(forKey: FirstRun.seenKey)) { library.firstRunPage = .what }
        }
    }

    func firstRunClosed() {
        UserDefaults.standard.set(true, forKey: FirstRun.seenKey)
        if firstRunNewAlbum {
            firstRunNewAlbum = false
            library.newAlbum()
        }
    }

    /// Which page shows (grid destinations share one, so the grid keeps its state).
    var pageKey: String {
        if library.trips.isEmpty { return "empty" }
        switch library.destination {
        case .journey: return "journey"
        case .moments: return "moments"
        case .chapters: return "chapters"
        case .people: return "people"
        case .settings: return "settings"
        default: return "grid"
        }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) { ActivityPill() }
        if !library.trips.isEmpty {
            ToolbarItem { AlbumViewMenu() }
        }
        if !library.destination.isPage { gridTools }
        ToolbarItem {
            Button { library.startReview() } label: { Label(library.tr("quickReview"), systemImage: "rectangle.stack.badge.play") }
                .help(library.tr("quickReviewHelp"))
                .disabled(library.photos.isEmpty)
        }
        if !library.destination.isPage {
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label(library.tr("inspector"), systemImage: "sidebar.right") }
                    .help(library.tr("inspector"))
            }
        }
    }

    @ToolbarContentBuilder var gridTools: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker(library.tr("sort"), selection: $library.sort) {
                    ForEach(PhotoSort.allCases, id: \.self) { Text(library.tr("sort_" + $0.rawValue)).tag($0) }
                }
                .pickerStyle(.inline)
            } label: { Label(library.tr("viewOptions"), systemImage: "line.3.horizontal.decrease") }
            .help(library.tr("viewOptions"))
        }
        ToolbarItem {
            Slider(value: $library.tileSize, in: 110...340)
                .frame(width: 110)
                .help(library.tr("thumbSize"))
                .accessibilityLabel(library.tr("thumbSize"))
        }
        ToolbarSpacer(.fixed)
        if library.destination == .blurry {
            ToolbarItem {
                Button(library.tr("leaveOutAllBlurry"), systemImage: "eye.slash") { library.leaveOutAllBlurry() }
            }
        }
    }

    var title: String {
        if library.trips.isEmpty { return "Photo Curator" }
        switch library.destination {
        case .journey: return library.albumName
        case .moments: return library.tr("viewMoments")
        case .chapters: return library.tr("viewChapters")
        case .people: return library.tr("step_photos")
        case .settings: return library.tr("settings")
        case .blurry: return library.tr("blurryNav")
        case .all: return library.tr("allPhotos")
        case .favourites: return library.tr("favourites")
        case .leftOut: return library.tr("leftOut")
        case .videos: return library.tr("videos")
        case .day(let d): return formatDay(d, library.lang, style: .long)
        case .search: return "“\(library.searchResult?.query ?? library.searchText)”"
        }
    }
    var subtitle: String {
        if library.trips.isEmpty { return "" }
        switch library.destination {
        case .journey:
            let j = library.journey
            return String(format: library.tr("journeyStationOf"), library.shownStation.number) + " · " + j.status(library.lang)
        case .settings: return library.tr("settingsSubtitle")
        case .moments, .chapters, .people: return library.albumName
        default:
            var s = library.albumName + " · " + Strings.photos(library.flat.count, library.lang)
            if library.destination == .search, let en = library.searchResult?.english, !en.isEmpty {
                s += " · " + library.tr("alsoAs") + " “\(en)”"
            }
            return s
        }
    }
}

/// The toolbar's View menu (M14a): the album's secondary views, which are views of one album, not steps.
struct AlbumViewMenu: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        Menu {
            Button { library.open(station: nil) } label: { Label(library.tr("viewPath"), systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            Divider()
            Section(library.tr("viewPhotos")) {
                item(.all, library.tr("allPhotos"), "photo.on.rectangle")
                item(.favourites, library.tr("favourites"), "heart")
                item(.videos, library.tr("videos"), "video")
                if library.count(.blurry) > 0 { item(.blurry, library.tr("blurryNav"), "camera.aperture") }
                item(.leftOut, library.tr("leftOut"), "eye.slash")
                if library.searchResult != nil { item(.search, library.tr("searchResults"), "magnifyingglass") }
            }
            if !library.days.isEmpty {
                Menu(library.tr("days")) {
                    ForEach(library.days, id: \.self) { d in
                        Button(formatDay(d, library.lang, style: .short) + "  ·  \(library.count(.day(d)))") { library.destination = .day(d) }
                    }
                }
            }
            Divider()
            Section(library.tr("viewDetails")) {
                item(.moments, library.tr("viewMoments"), "square.stack.3d.up")
                item(.chapters, library.tr("viewChapters"), "book.pages")
                item(.people, library.tr("step_photos"), "person.2")
            }
        } label: {
            Label(library.tr("viewMenu"), systemImage: "rectangle.3.group")
        }
        .help(library.tr("viewMenuHelp"))
    }

    func item(_ d: Destination, _ title: String, _ symbol: String) -> some View {
        Button {
            library.reviewFilter = nil
            library.destination = d
        } label: {
            if library.destination == d { Label(title, systemImage: "checkmark") } else { Label(title, systemImage: symbol) }
        }
    }
}

// MARK: sidebar (M14a): albums only

/// The sidebar is the list of albums, nothing else: a cover, the name and one status line each, with a small
/// ring while it is being sorted. "+ New Album" on top; Rename, Add Folder…, Show in album, Remove Album… in the
/// context menu; ⌫ removes the selected album (after a confirmation).
struct AlbumSidebar: View {
    @EnvironmentObject var library: LibraryModel
    @State private var renaming: Trip?
    @State private var newName = ""

    var body: some View {
        List(selection: Binding(get: { library.tripId }, set: { id in
            guard let id, id != library.tripId else { return }
            library.reviewFilter = nil
            library.tripId = id                       // opens the album on its path
        })) {
            ForEach(library.trips) { t in
                AlbumRow(trip: t)
                    .tag(t.id)
                    // A click on the open album goes back to its path (from a grid or a secondary view).
                    .simultaneousGesture(TapGesture().onEnded {
                        if t.id == library.tripId && library.destination != .journey { library.open(station: nil) }
                    })
                    .motionTransition(.move(edge: .top).combined(with: .opacity))
                    .contextMenu { menu(t) }
            }
        }
        .onDeleteCommand { if let id = library.tripId { library.removeAlbumRequest = id } }
        .safeAreaInset(edge: .top) {
            Button { library.newAlbum() } label: {
                Label(library.tr("newAlbumButton"), systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)                    // no glass inside the sidebar (it is glass already)
            .controlSize(.large)
            .padding(.horizontal, Space.l).padding(.bottom, Space.s)
            .help(library.tr("newAlbumButton") + "  (⌘N)")
        }
        .safeAreaInset(edge: .bottom) {
            Button { library.reviewFilter = nil; library.destination = .settings } label: {
                Label(library.tr("settings"), systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(library.destination == .settings ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .font(TypeRole.supporting)
            .help(library.tr("settings") + "  (⌘,)")
            .padding(Space.l)
        }
        .overlay {
            if library.trips.isEmpty {
                Text(library.tr("sidebarEmpty")).font(TypeRole.supporting).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(Space.xl)
            }
        }
        .alert(library.tr("renameAlbum"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(library.tr("albumNamePrompt"), text: $newName)
            Button(library.tr("rename")) { if let t = renaming { library.renameAlbum(newName, trip: t.id) }; renaming = nil }
                .keyboardShortcut(.defaultAction)
            Button(library.tr("cancel"), role: .cancel) { renaming = nil }
        }
    }

    @ViewBuilder func menu(_ t: Trip) -> some View {
        Button(library.tr("rename") + "…") { newName = t.name; renaming = t }
        Button(library.tr("addFolderMenu")) { library.chooseFolders(trip: t.id) }
        Menu(library.tr("showInAlbum")) {
            Button(library.tr("allPhotos")) { show(t, .all) }
            Button(library.tr("leftOut")) { show(t, .leftOut) }
        }
        Divider()
        Button(library.tr("removeAlbumMenu"), role: .destructive) { library.removeAlbumRequest = t.id }
            .disabled(library.job.running && library.job.collection == t.id)
    }

    func show(_ t: Trip, _ d: Destination) {
        library.reviewFilter = nil
        if library.tripId != t.id { library.tripId = t.id }
        library.destination = d
    }
}

/// One album in the sidebar: cover, name, status ("Sorting · day 3 of 7", "6 questions", "Exported").
struct AlbumRow: View {
    @EnvironmentObject var library: LibraryModel
    let trip: Trip

    var body: some View {
        let journey = library.journeyOf(trip)
        let status = library.statusLine(for: trip)
        HStack(spacing: Space.m) {
            cover
                .frame(width: 34, height: 34)
                .clipShape(.rect(cornerRadius: Radius.small))
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(trip.name).font(TypeRole.body.weight(.medium)).lineLimit(1)
                Text(status).font(TypeRole.caption).foregroundStyle(statusStyle(journey)).lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            if let p = journey?.ringProgress {
                ProgressRing(progress: p).frame(width: 16, height: 16)
                    .motionTransition(.scale.combined(with: .opacity))
            } else if journey?.isDone == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(StatusColor.kept).font(TypeRole.caption)
            }
        }
        .padding(.vertical, Space.xxs)
        .motionAnimation(.settle, value: status)
        .motionAnimation(.quick, value: journey?.ringProgress == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trip.name + ", " + status)
    }

    @ViewBuilder var cover: some View {
        if let url = library.coverURL(for: trip) {
            Thumbnail(url: url, side: 160)
        } else {
            ZStack {
                Rectangle().fill(.fill.tertiary)
                Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.secondary).font(TypeRole.caption)
            }
        }
    }

    func statusStyle(_ j: AlbumJourney?) -> AnyShapeStyle {
        if case .answer? = j?.action { return AnyShapeStyle(StatusColor.lookText) }
        if case .retry? = j?.action { return AnyShapeStyle(StatusColor.removed) }
        return AnyShapeStyle(.secondary)
    }
}

/// A small determinate ring (sidebar rows): the album's sorting or export progress.
struct ProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 2.5)
            Circle().trim(from: 0, to: max(0.03, min(1, progress)))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .motionAnimation(.settle, value: progress)
        .accessibilityHidden(true)
    }
}

/// No album yet: one big New Album and a drop zone for folders (they become the new album's folders).
struct EmptyAlbums: View {
    @EnvironmentObject var library: LibraryModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: Space.xxxl) {
            VStack(spacing: Space.m) {
                Image(systemName: "photo.stack").font(TypeRole.heroSymbol).foregroundStyle(.tint)
                Text(library.tr("emptyTitle")).font(TypeRole.pageTitle)
                Text(library.tr("emptyText")).font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 520)
            }
            Button { library.newAlbum() } label: {
                Label(library.tr("newAlbumButton"), systemImage: "plus").padding(.horizontal, Space.l)
            }
            .buttonStyle(.glassProminent).controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            VStack(spacing: Space.s) {
                Image(systemName: "folder.badge.plus").font(.title2).foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: targeted)
                Text(library.tr("emptyDrop")).font(TypeRole.cardTitle)
            }
            .frame(maxWidth: 520, minHeight: 140)
            .background {
                RoundedRectangle(cornerRadius: Radius.large)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .background(targeted ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: Radius.large))
            }
            .dropDestination(for: URL.self) { urls, _ in library.newAlbum(with: urls); return true } isTargeted: { targeted = $0 }
            .motionAnimation(.quick, value: targeted)
            .accessibilityLabel(library.tr("emptyDrop"))
            Label(library.tr("readOnlyNote"), systemImage: "lock.shield").font(TypeRole.supporting).foregroundStyle(.secondary)
        }
        .padding(Space.giant)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The one confirmation for removing an album (sidebar ⌫, context menu, ⌘⌫, Clear Working Data…). It says plainly
/// what goes (the album and its working data in Photo Curator) and what stays (the photos, the exported folder),
/// and that it cannot be undone.
private struct RemoveAlbumConfirmation: ViewModifier {
    @EnvironmentObject var library: LibraryModel

    func body(content: Content) -> some View {
        let trip = library.trips.first { $0.id == library.removeAlbumRequest }
        let exported = trip.map { library.journeyOf($0)?.input.exported ?? false } ?? false
        let text = removeAlbumConfirm(trip?.name ?? "", exported: exported, library.lang)
        return content.confirmationDialog(text.title,
                                          isPresented: Binding(get: { trip != nil }, set: { if !$0 { library.removeAlbumRequest = nil } }),
                                          titleVisibility: .visible, presenting: trip) { t in
            Button(text.button, role: .destructive) {
                library.removeAlbumRequest = nil
                Task { await library.removeAlbum(t.id) }
            }
            Button(library.tr("removeAlbumKeep"), role: .cancel) { library.removeAlbumRequest = nil }
        } message: { _ in
            Text(text.message)
        }
    }
}

extension View {
    func removeAlbumConfirmation() -> some View { modifier(RemoveAlbumConfirmation()) }
}

/// A short information at the top of the page ("moved to …", "freed 50 MB"); fades out and is announced.
/// Errors go to `ErrorBannerHost` instead, which stays until dismissed (M12e, #8).
struct MessageBanner: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        if let m = library.message {
            Text(m)
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 10)
                .motionTransition(.move(edge: .top).combined(with: .opacity))
                .task(id: m) {
                    AccessibilityNotification.Announcement(m).post()
                    try? await Task.sleep(for: .seconds(4))
                    withMotion(.fade) { library.message = nil }
                }
        }
    }
}

/// The sticky error banner at the top of the window (M12e, #8): human text, Details, Try Again, Dismiss.
struct ErrorBannerHost: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        if let e = library.errorBanner {
            ErrorBanner(error: e.error, retry: e.retry, dismiss: { withMotion(.fade) { library.errorBanner = nil } })
                .id(e.id)
                .padding(.top, Space.l)
                .padding(.horizontal, Space.xl)
                .motionTransition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

enum DayStyle { case short, long }

func formatDay(_ day: String, _ lang: Lang, style: DayStyle) -> String {
    if day == Photo.undated { return Strings.text("noDate", lang) }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
    guard let date = f.date(from: day) else { return day }
    let o = DateFormatter(); o.timeZone = TimeZone(identifier: "UTC")
    o.locale = Locale(identifier: lang == .sl ? "sl_SI" : "en_GB")
    o.setLocalizedDateFormatFromTemplate(style == .short ? "EEEdMMM" : "EEEEdMMMMyyyy")
    return o.string(from: date)
}


/// The page on screen: the album's path, one of its secondary views, settings, or a photo grid.
struct DetailPage: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        if library.trips.isEmpty {
            EmptyAlbums()
        } else {
            switch library.destination {
            case .journey: AlbumJourneyView()
            case .moments: StepSelection()
            case .chapters: StepStory()
            case .people: StepPhotos()
            case .settings: SettingsPage()
            default: PhotoGrid()
            }
        }
    }
}
