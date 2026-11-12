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
            Group {
                if library.destination == .overview { OverviewView() } else { PhotoGrid() }
            }
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .toolbar { toolbar }
                .searchable(text: $library.searchText, placement: .toolbar, prompt: library.tr("searchPrompt"))
                .searchFocused($searchFocused)
                .onSubmit(of: .search) { library.runSearch() }
                .onChange(of: library.searchFocusRequest) { _, _ in searchFocused = true }
                .inspector(isPresented: Binding(get: { showInspector && library.destination != .overview },
                                                set: { showInspector = $0 })) {
                    InspectorView().inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
                .overlay(alignment: .bottom) {
                    if library.selection.count > 1 {
                        SelectionBar(newEvent: $newEvent)
                            .padding(.bottom, 18)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .top) { MessageBanner() }
                .animation(.spring(duration: 0.35), value: library.selection.count > 1)
                .sheet(isPresented: $newEvent) { NewEventSheet() }
                .sheet(item: $library.sheet) { s in
                    switch s {
                    case .newAlbum: NewAlbumWizard()
                    case .moments: MomentsSheet()
                    case .clocks: ClocksSheet()
                    case .export: ExportSheet()
                    }
                }
                .quickLookPreview($library.quickLookURL, in: library.quickLookItems)
        }
        .overlay { AIGlow(active: library.job.running && library.job.phase.isAI) }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) { ActivityPill() }
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
        ToolbarItem {
            Button { library.sheet = .export } label: { Label(library.tr("export"), systemImage: "square.and.arrow.up") }
                .buttonStyle(.glassProminent)
                .help(library.tr("exportHelp"))
        }
        ToolbarItem {
            Button { showInspector.toggle() } label: { Label(library.tr("inspector"), systemImage: "sidebar.right") }
                .help(library.tr("inspector"))
        }
    }

    var title: String {
        switch library.destination {
        case .overview: return library.tr("overview")
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
        if library.destination == .overview { return library.trips.first { $0.id == library.tripId }?.name ?? "" }
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
            Section(library.tr("album")) {
                Label(library.tr("overview"), systemImage: "sparkles.rectangle.stack").tag(Destination.overview)
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
        .safeAreaInset(edge: .bottom) { AlbumProgress().padding(10) }
    }

    func row(_ d: Destination, _ icon: String, _ title: String) -> some View {
        Label(title, systemImage: icon)
            .badge(library.count(d))
            .tag(d)
    }
}

/// Bottom of the sidebar: how far the album is, the export, and finishing the album.
/// The album is a work in progress that ends in Google Photos, not a place to keep photos.
struct AlbumProgress: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.openWindow) private var openWindow
    @State private var confirmFinish = false

    var body: some View {
        let done = library.stepsDone
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Gauge(value: Double(done), in: 0...7) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .scaleEffect(0.55).frame(width: 26, height: 26)
                    .tint(library.exported ? .green : .accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: library.tr("stepsProgress"), done)).font(.callout.weight(.medium))
                    if library.exported {
                        Label(library.tr("exported"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    }
                }
            }
            Button { openWindow(id: "classic") } label: {
                Label(library.tr("tripSteps"), systemImage: "checklist").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .help(library.tr("tripStepsHelp"))
            Button { library.sheet = .export } label: {
                Label(library.tr("exportGP"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .help(library.tr("exportHelp"))
            Button(library.tr("finishAlbum"), role: .destructive) { confirmFinish = true }
                .buttonStyle(.link)
                .font(.callout)
                .disabled(library.tripId == nil || (library.job.running && library.job.collection == library.tripId))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .padding(12)
        .background(.fill.quaternary, in: .rect(cornerRadius: 14))     // inside the glass sidebar: no glass on glass
        .confirmationDialog(String(format: library.tr("finishTitle"), library.trips.first { $0.id == library.tripId }?.name ?? ""),
                            isPresented: $confirmFinish, titleVisibility: .visible) {
            Button(library.tr("finishConfirm"), role: .destructive) { Task { await library.finishAlbum() } }
            Button(library.tr("cancel"), role: .cancel) {}
        } message: {
            Text(library.exported ? library.tr("finishText") : library.tr("finishNotExported") + "\n\n" + library.tr("finishText"))
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

/// A short message at the top of the grid (errors, "moved to …"); fades out.
struct MessageBanner: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        if let m = library.message {
            Text(m)
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: m) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { library.message = nil }
                }
                .accessibilityAddTraits(.updatesFrequently)
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
