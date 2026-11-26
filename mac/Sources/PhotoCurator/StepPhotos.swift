import AppKit
import CuratorCore
import SwiftUI

/// Step 1: whose photos these are (names editable, folders can be added) and the cameras' clocks,
/// shown as lanes on one time line so a shift is visible before it is applied.
struct StepPhotos: View {
    @EnvironmentObject var library: LibraryModel
    @State private var clocks: [DeviceClock] = []

    var body: some View {
        StepPage(title: library.tr("stepTitle_photos"), symbol: "person.2.crop.square.stack", lead: library.tr("lead_photos"), status: status) {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(title: library.tr("whoTitle"), detail: library.tr("whoLead"))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(Array(library.sources.enumerated()), id: \.element.id) { i, s in
                            SourceCard(source: s, index: i)
                        }
                        AddFolderCard()
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(title: library.tr("clocksTitle"), detail: library.tr("clockLanesLead"))
                    if library.analysing {
                        AnalysisCard(compact: true)
                    } else if clocks.count < 2 {
                        Label(library.tr("clocksOneText"), systemImage: "checkmark.circle.fill")
                            .font(.title3).foregroundStyle(.secondary)
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading).card()
                    } else {
                        ClockLanes(clocks: clocks, reload: load)
                    }
                }
            }
        }
        .task(id: "\(library.tripId ?? "")\(library.analysing)") { await load() }
    }

    var status: String {
        let pending = clocks.filter(\.pending).count
        return pending > 0 ? String(format: library.tr("clocksPendingShort"), pending)
            : Strings.count(library.sources.count, .person, library.lang) + " · " + Strings.photos(library.photos.count, library.lang)
    }

    func load() async {
        guard let t = library.tripId else { return }
        clocks = (try? await library.api.clocks(trip: t)) ?? []
    }
}

/// One folder: the person (name editable in place), the folder, how many photos, which cameras.
struct SourceCard: View {
    @EnvironmentObject var library: LibraryModel
    let source: SourceInfo
    let index: Int
    @State private var name = ""
    @State private var trip: String?
    @FocusState private var focused: Bool

    var mine: [Photo] { library.photos.filter { $0.sourceId == source.id } }

    var body: some View {
        let photos = mine
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PersonBadge(name: name.isEmpty ? source.owner : name, index: index, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    TextField(library.tr("whosePhotos"), text: $name)
                        .textFieldStyle(.plain).font(.title3.weight(.semibold))
                        .focused($focused)
                        .onSubmit { library.renamePerson(source: source.id, to: name, trip: trip) }
                        .onChange(of: focused) { _, f in if !f { library.renamePerson(source: source.id, to: name, trip: trip) } }
                    Text(library.tr("tapToRename")).font(.caption).foregroundStyle(.tertiary)
                }
            }
            PhotoMosaic(photos: photos.filter { !$0.rejected && !$0.isVideo }, radius: 12).frame(height: 120)
            VStack(alignment: .leading, spacing: 5) {
                Label(Strings.photos(source.assets ?? photos.count, library.lang), systemImage: "photo.on.rectangle")
                if !devices(photos).isEmpty { Label(devices(photos), systemImage: "camera") }
                HStack(spacing: 6) {
                    Label(URL(fileURLWithPath: source.path).lastPathComponent, systemImage: "folder").lineLimit(1)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source.path)]) } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.plain).foregroundStyle(.tint).help(library.tr("showInFinder"))
                    .accessibilityLabel(library.tr("showInFinder"))
                }
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .padding(16)
        .card()
        .onAppear { name = source.owner; trip = library.shownTrip }
        .onDisappear { if focused { library.renamePerson(source: source.id, to: name, trip: trip) } }
        .onChange(of: source.owner) { _, n in if !focused { name = n } }
    }

    func devices(_ photos: [Photo]) -> String {
        var counts: [String: Int] = [:]
        for p in photos { if let d = p.device, !d.isEmpty { counts[d, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(2).map(\.key).joined(separator: ", ")
    }
}

/// Add another person's folder to this album; only the new photos are read.
struct AddFolderCard: View {
    @EnvironmentObject var library: LibraryModel
    @State private var targeted = false

    var body: some View {
        Button { choose() } label: {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.plus").font(.system(size: 34, weight: .light)).foregroundStyle(.tint)
                Text(library.tr("addFolderTitle")).font(.headline)
                Text(library.tr("addFolderText")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 250)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .background(targeted ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 22))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(library.job.running)
        .dropDestination(for: URL.self) { urls, _ in library.addFolders(urls); return true } isTargeted: { targeted = $0 }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = library.tr("addFolders")
        panel.message = library.tr("chooseFoldersMessage")
        if panel.runModal() == .OK { library.addFolders(panel.urls) }
    }
}

// MARK: clocks

/// One lane per camera across the album's time span, a dot per photo. A suggested shift draws the
/// dots where they would move; the owner aligns, declines, undoes or nudges by hand.
struct ClockLanes: View {
    @EnvironmentObject var library: LibraryModel
    let clocks: [DeviceClock]
    let reload: () async -> Void

    var body: some View {
        let span = timeSpan
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(clocks.enumerated()), id: \.element.id) { i, c in
                ClockLane(clock: c, index: personIndex(c.owner), photos: photos(of: c), span: span, reload: reload,
                          returnKeyAligns: c.id == firstPendingId)
                if i < clocks.count - 1 { Divider().padding(.leading, 16) }
            }
            if let span {
                HStack {
                    Text(timeLabel(span.0)); Spacer(); Text(timeLabel(span.1))
                }
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .padding(.vertical, 6)
        .card()
    }

    /// The one lane whose Align button answers the Return key (the first pending suggestion).
    var firstPendingId: Int? { clocks.first { $0.pending && $0.suggestedS != nil && $0.status != "reference" }?.id }

    func personIndex(_ owner: String) -> Int { library.sources.firstIndex { $0.owner == owner } ?? 0 }

    func photos(of c: DeviceClock) -> [Photo] {
        library.photos.filter { $0.owner == c.owner && ($0.device ?? "") == c.device }
    }

    /// The album's first and last capture time, with room for the largest suggested shift.
    var timeSpan: (Date, Date)? {
        let dates = library.photos.compactMap { $0.time.flatMap(parseLocalTime) }
        guard let a = dates.min(), let b = dates.max() else { return nil }
        let pad = max(60, clocks.compactMap(\.suggestedS).map(abs).max() ?? 0) + b.timeIntervalSince(a) * 0.03
        return (a.addingTimeInterval(-pad), b.addingTimeInterval(pad))
    }

    func timeLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: library.lang == .sl ? "sl_SI" : "en_GB")
        f.setLocalizedDateFormatFromTemplate("EEEdMMMHHmm")
        return f.string(from: d)
    }
}

struct ClockLane: View {
    @EnvironmentObject var library: LibraryModel
    let clock: DeviceClock
    let index: Int
    let photos: [Photo]
    let span: (Date, Date)?
    let reload: () async -> Void
    var returnKeyAligns = false
    @State private var manual = false
    @State private var seconds: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 10) {
                PersonBadge(name: clock.owner, index: index, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(clock.owner).font(.headline)
                    Text(clock.device).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 190, alignment: .leading)
            lane.frame(height: 34)
            actions.frame(width: 250, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottomLeading) {
            Text(note).font(.caption).foregroundStyle(clock.pending ? .orange : .secondary)
                .padding(.leading, 16 + 190 + 16).padding(.bottom, 2).lineLimit(1)
        }
    }

    var lane: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.quaternary).frame(height: 6).frame(maxHeight: .infinity)
                if let span {
                    let xs = photos.compactMap { timelinePosition($0.time, start: span.0, end: span.1) }
                    ForEach(Array(xs.enumerated()), id: \.offset) { _, x in
                        Circle().fill(personColor(index)).frame(width: 7, height: 7)
                            .position(x: x * g.size.width, y: g.size.height / 2)
                    }
                    if clock.pending, let s = clock.suggestedS {
                        let shifted = photos.compactMap { p in
                            p.time.flatMap(parseLocalTime).map { $0.addingTimeInterval(s) }
                        }.map { min(1, max(0, $0.timeIntervalSince(span.0) / max(1, span.1.timeIntervalSince(span.0)))) }
                        ForEach(Array(shifted.enumerated()), id: \.offset) { _, x in
                            Circle().strokeBorder(personColor(index), lineWidth: 1.5).frame(width: 9, height: 9)
                                .position(x: x * g.size.width, y: g.size.height / 2 - 11)
                        }
                    }
                }
            }
        }
        .accessibilityLabel(note)
    }

    @ViewBuilder var actions: some View {
        HStack(spacing: 8) {
            if clock.status == "reference" {
                Label(library.tr("clockReferenceShort"), systemImage: "scope").font(.callout).foregroundStyle(.secondary)
            } else if clock.pending, let s = clock.suggestedS {
                Button(String(format: library.tr("alignBy"), shiftText(s))) { act("accept") }.buttonStyle(.glassProminent)
                    .defaultActionKey(if: returnKeyAligns)
                Button(library.tr("no")) { act("reject") }.buttonStyle(.glass)
            } else if let a = clock.appliedS, a != 0 {
                Button(library.tr("undo")) { act("reset") }.buttonStyle(.glass)
            }
            if clock.status != "reference" {
                Button { seconds = clock.appliedS ?? 0; manual = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.glass).help(library.tr("manualShift")).accessibilityLabel(library.tr("manualShift"))
                    .popover(isPresented: $manual, arrowEdge: .bottom) { manualPopover }
            }
        }
    }

    var manualPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(library.tr("manualShift")).font(.headline)
            Text(library.tr("manualShiftText")).font(.callout).foregroundStyle(.secondary).frame(width: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ForEach([-600.0, -60, -10, 10, 60, 600], id: \.self) { d in
                    Button(shiftText(d)) { seconds += d }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            Text(shiftText(seconds) == "0 s" ? "0 s" : shiftText(seconds)).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
            HStack {
                Spacer()
                Button(library.tr("cancel")) { manual = false }
                Button(library.tr("apply")) { act("manual", seconds); manual = false }.buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
    }

    var note: String {
        if clock.status == "reference" { return library.tr("clockReference") }
        if let a = clock.appliedS, a != 0 { return String(format: library.tr("clockShifted"), shiftText(a)) }
        if clock.pending { return clock.evidence?.note ?? library.tr("clockSuggested") }
        return Strings.photos(clock.photos, library.lang) + " · " + library.tr("clockNoChange")
    }

    func act(_ action: String, _ s: Double? = nil) {
        guard let t = library.tripId else { return }
        Task {
            do { try await library.api.clock(trip: t, id: clock.clockId, action: action, seconds: s) }
            catch { library.message = library.describe(error) }
            await reload()
            await library.reload()
        }
    }
}
