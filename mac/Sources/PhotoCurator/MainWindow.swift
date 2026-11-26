import CuratorCore
import QuickLook
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.openWindow) private var openWindow
    @State private var showInspector = true
    @State private var newEvent = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            DetailPage()
                .id(guidePage)
                .transition(.opacity)
                .motionAnimation(.settle, value: guidePage)
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .searchable(text: $library.searchText, placement: .toolbar, prompt: library.tr("searchPrompt"))
                .searchFocused($searchFocused)
                .onSubmit(of: .search) { library.runSearch() }
                .onChange(of: library.searchFocusRequest) { _, _ in searchFocused = true }
                .inspector(isPresented: Binding(get: { showInspector && !library.destination.isGuide },
                                                set: { showInspector = $0 })) {
                    InspectorView().inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
                .overlay(alignment: .bottom) {
                    VStack(spacing: Space.m) {
                        UndoToast()
                        if library.selection.count > 1 {
                            SelectionBar(newEvent: $newEvent)
                                .padding(.bottom, 18)
                                .motionTransition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
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
                .sheet(item: $library.sheet) { s in
                    switch s {
                    case .newAlbum: NewAlbumWizard()
                    }
                }
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
    }

    /// Which guide page shows (grid destinations share one, so the grid keeps its state).
    var guidePage: String {
        switch library.destination {
        case .home: "home"
        case .step(let s): s.rawValue
        case .people: "people"
        case .settings: "settings"
        case .sorting: "sorting"
        default: "grid"
        }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) { ActivityPill() }
        if !library.destination.isGuide { gridTools }
        ToolbarItem {
            Button { library.startReview() } label: { Label(library.tr("quickReview"), systemImage: "rectangle.stack.badge.play") }
                .help(library.tr("quickReviewHelp"))
        }
        ToolbarItem {
            // Not prominent (M12e, #16): each page has its own primary action; this is a shortcut to Export.
            Button { library.destination = .step(.export) } label: { Label(library.tr("export"), systemImage: "square.and.arrow.up") }
                .help(library.tr("exportHelp"))
        }
        if !library.destination.isGuide {
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label(library.tr("inspector"), systemImage: "sidebar.right") }
                    .help(library.tr("inspector"))
            }
        }
    }

    @ToolbarContentBuilder var gridTools: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker(library.tr("show"), selection: Binding(
                    get: { [.favourites, .videos].contains(library.destination) ? library.destination : .all },
                    set: { library.destination = $0 })) {
                    Text(library.tr("allPhotos")).tag(Destination.all)
                    Text(library.tr("favourites")).tag(Destination.favourites)
                    Text(library.tr("videos")).tag(Destination.videos)
                }
                .pickerStyle(.inline)
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
        switch library.destination {
        case .home: return library.albumName
        case .step(let s): return library.tr("step_" + s.rawValue)
        case .people: return library.tr("step_photos")
        case .settings: return library.tr("settings")
        case .sorting: return library.tr("stage")
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
        if case .step(let s) = library.destination { return String(format: library.tr("stepOfThree"), s.number) + " · " + library.albumName }
        if library.destination == .people { return library.albumName }
        if library.destination == .settings { return library.tr("settingsSubtitle") }
        if library.destination == .sorting { return library.albumName }
        if library.destination == .home { return library.tr("albumHome") }
        let n = library.flat.count
        var s = Strings.photos(n, library.lang)
        if library.destination == .search, let en = library.searchResult?.english, !en.isEmpty {
            s += " · " + library.tr("alsoAs") + " “\(en)”"
        }
        return s
    }
}

struct Sidebar: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(selection: Binding(get: { library.destination }, set: { if let d = $0 { library.destination = d } })) {
            Section(library.tr("guide")) {
                // In the order of the flow (M12e, #15), the same as the Guide menu.
                Label(library.tr("albumHome"), systemImage: "house").tag(Destination.home)
                Label(library.tr("step_photos"), systemImage: "person.2")
                    .badge(library.clocksWaiting)
                    .tag(Destination.people)
                Label(library.tr("stage"), systemImage: "sparkles.rectangle.stack").tag(Destination.sorting)
                ForEach(GuideStep.allCases) { s in
                    let st = library.stepStates[s] ?? StepState(done: false, waiting: 0)
                    HStack(spacing: 8) {
                        Label {
                            Text(library.tr("step_" + s.rawValue))
                        } icon: {
                            Image(systemName: st.done ? "checkmark.circle.fill" : "\(s.number).circle")
                                .foregroundStyle(st.done ? AnyShapeStyle(.green) : AnyShapeStyle(s.tint))
                        }
                        Spacer()
                        if st.waiting > 0 {
                            Text("\(st.waiting)").font(.caption.weight(.bold)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.orange.opacity(0.2), in: .capsule).foregroundStyle(.orange)
                        }
                    }
                    .tag(Destination.step(s))
                }
            }
            Section(library.tr("library")) {
                row(.all, "photo.on.rectangle", library.tr("allPhotos"))
                if library.count(.blurry) > 0 { row(.blurry, "camera.aperture", library.tr("blurryNav")) }
                row(.leftOut, "eye.slash", library.tr("leftOut"))
                if library.searchResult != nil { row(.search, "magnifyingglass", library.tr("searchResults")) }
            }
            if !library.days.isEmpty {
                Section(library.tr("days")) {
                    ForEach(library.days, id: \.self) { d in row(.day(d), "calendar", formatDay(d, library.lang, style: .short)) }
                }
            }
        }
        .safeAreaInset(edge: .top) { TripPicker().padding(.horizontal, 10).padding(.bottom, 6) }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Button { library.reviewFilter = nil; library.destination = .settings } label: {
                    Label(library.tr("settings"), systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(library.destination == .settings ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .font(.callout)
                .help(library.tr("settings") + "  (⌘,)")
                FinishAlbumButton()
            }
            .padding(12)
        }
    }

    func row(_ d: Destination, _ icon: String, _ title: String) -> some View {
        Label(title, systemImage: icon)
            .badge(library.count(d))
            .tag(d)
    }
}

/// Bottom of the sidebar: clearing the album's working data (analysis, marks, thumbnails), never the photos.
/// Title and button say what is removed; the unexported warning comes first (M12e, #22).
struct FinishAlbumButton: View {
    @EnvironmentObject var library: LibraryModel
    @State private var confirmFinish = false

    var body: some View {
        Button(role: .destructive) { confirmFinish = true } label: {
            Label(library.tr("finishAlbum"), systemImage: "checkmark.rectangle.stack").frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .font(.callout)
        .disabled(library.tripId == nil || (library.job.running && library.job.collection == library.tripId))
        .help(library.tr("finishHelp"))
        .confirmationDialog(finishAlbumTitle(library.albumName, exported: library.exported, library.lang),
                            isPresented: $confirmFinish, titleVisibility: .visible) {
            Button(library.tr("finishConfirm"), role: .destructive) { Task { await library.finishAlbum() } }
            Button(library.tr("cancel"), role: .cancel) {}
        } message: {
            Text(finishAlbumText(exported: library.exported, library.lang))
        }
    }
}

struct TripPicker: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Menu {
            ForEach(library.trips) { t in
                Button { library.tripId = t.id } label: {
                    if t.id == library.tripId { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                }
            }
            Divider()
            Button(library.tr("newTrip")) { library.sheet = .newAlbum }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "suitcase.fill").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(library.trips.first { $0.id == library.tripId }?.name ?? library.tr("noTrip"))
                        .font(.headline).lineLimit(1)
                    Text(Strings.photos(library.photos.count, library.lang)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .background(.fill.tertiary, in: .rect(cornerRadius: 10))      // the sidebar is glass already: no glass on glass
        .accessibilityLabel(library.tr("trip"))
    }
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


/// The page the sidebar points at: the album home, a step, people and clocks, or a photo grid.
struct DetailPage: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        switch library.destination {
        case .home: AlbumHome()
        case .step(.selection): StepSelection()
        case .step(.story): StepStory()
        case .step(.export): StepExport()
        case .people: StepPhotos()
        case .settings: SettingsPage()
        case .sorting: SortingStage()
        default: PhotoGrid()
        }
    }
}
