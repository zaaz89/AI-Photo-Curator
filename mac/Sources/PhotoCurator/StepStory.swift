import CuratorCore
import SwiftUI

/// Step 3: the album as a story. Days hold chapters (the engine's events); every chapter can be
/// renamed, merged with the one before, opened, split at a photo, and its descriptions edited.
struct StepStory: View {
    @EnvironmentObject var library: LibraryModel
    @State private var open: TripEvent?

    var body: some View {
        StepPage(step: .story, lead: library.tr("lead_story"), status: status) {
            VStack(alignment: .leading, spacing: 30) {
                DescriptionsCard()
                if library.analysing && library.events.isEmpty {
                    AnalysisCard(compact: true)
                }
                ForEach(chaptersByDay(library.events)) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(formatDay(day.day, library.lang, style: .long)).font(.title2.weight(.bold))
                            if let place = dayPlace(day) { Text(place).font(.title3).foregroundStyle(.secondary) }
                            Spacer()
                            Menu {
                                Button(library.tr("resetChapters")) { library.resetChapters(day: day.day) }
                            } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.button).buttonStyle(.plain).foregroundStyle(.secondary)
                                .help(library.tr("dayMenu")).accessibilityLabel(library.tr("dayMenu"))
                        }
                        ForEach(Array(day.chapters.enumerated()), id: \.element.id) { i, e in
                            ChapterCard(event: e, first: i == 0) { open = e }
                        }
                    }
                }
            }
        }
        .sheet(item: $open) { e in ChapterSheet(eventId: e.id) }
    }

    var status: String {
        Strings.count(library.events.count, .chapter, library.lang) + " · " +
            Strings.count(Set(library.events.map(\.day)).count, .day, library.lang)
    }

    func dayPlace(_ d: DayChapters) -> String? {
        let labels = d.chapters.compactMap(\.placeLabel).filter { !$0.isEmpty }
        return labels.isEmpty ? nil : Array(NSOrderedSet(array: labels)).compactMap { $0 as? String }.prefix(3).joined(separator: ", ")
    }
}

/// AI descriptions: how many are done, how long the rest takes on this Mac, and start.
struct DescriptionsCard: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        let d = library.overview?.descriptions
        let describing = library.job.running && library.job.kind == "describe" && library.job.collection == library.tripId
        HStack(spacing: 16) {
            AIRing(symbol: "text.bubble", size: 46, spinning: describing,
                   progress: d.map { Double($0.done) / Double(max(1, $0.photos)) })
            VStack(alignment: .leading, spacing: 4) {
                Text(library.tr("descTitle")).font(.headline)
                Text(text(d, describing)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if describing {
                Button(library.tr("stop")) { library.stopJob() }.buttonStyle(.glass).controlSize(.large)
            } else if let d, d.done < d.photos {
                Button(library.tr("describe")) { library.describePhotos() }
                    .buttonStyle(.glassProminent).controlSize(.large).tint(.purple)
                    .disabled(library.job.running)
            }
        }
        .padding(18)
        .card()
    }

    func text(_ d: Overview.Descriptions?, _ running: Bool) -> String {
        guard let d else { return library.tr("stillAnalysing") }
        if running { return library.job.status }
        if d.photos > 0 && d.done >= d.photos { return String(format: library.tr("descAll"), d.photos) }
        return String(format: library.tr("descSome"), d.done, d.photos, max(1, d.minutesLeft)) + " " + library.tr("descWhere")
    }
}

/// One chapter: cover, name editable in place, time and place, a strip of its photos.
struct ChapterCard: View {
    @EnvironmentObject var library: LibraryModel
    let event: TripEvent
    let first: Bool
    let open: () -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let photos = library.photos.filter { $0.eventId == event.id && !$0.rejected }
        HStack(alignment: .top, spacing: 18) {
            Group {
                if let c = coverPhoto(photos) { PhotoCover(photo: c, side: 520, radius: 16) }
                else { RoundedRectangle(cornerRadius: 16).fill(.fill.quaternary) }
            }
            .frame(width: 240, height: 160)
            .onTapGesture(perform: open)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    TextField(library.tr("chapterName"), text: $name)
                        .textFieldStyle(.plain).font(.title2.weight(.semibold))
                        .focused($focused)
                        .onSubmit { library.renameEvent(event.id, to: name) }
                        .onChange(of: focused) { _, f in if !f { library.renameEvent(event.id, to: name) } }
                    Menu {
                        Button(library.tr("openChapter"), action: open)
                        if !first { Button(library.tr("mergePrevious")) { library.mergeWithPrevious(event.id) } }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        .menuStyle(.button).buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel(library.tr("chapterMenu"))
                }
                Text(meta(photos)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(photos.prefix(8)) { p in
                        PhotoCover(photo: p, side: 260, radius: 8).frame(width: 66, height: 50)
                    }
                    if photos.count > 8 {
                        Text("+\(photos.count - 8)").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                            .frame(width: 50, height: 50).background(.fill.quaternary, in: .rect(cornerRadius: 8))
                    }
                }
                .onTapGesture(perform: open)
                Spacer(minLength: 0)
                Button(action: open) { Label(library.tr("openChapter"), systemImage: "rectangle.expand.vertical") }
                    .buttonStyle(.glass)
            }
        }
        .padding(16)
        .card(hover: true)
        .onAppear { name = event.name }
        .onDisappear { if focused { library.renameEvent(event.id, to: name) } }
        .onChange(of: event.name) { _, n in if !focused { name = n } }
    }

    func meta(_ photos: [Photo]) -> String {
        let times = photos.map(\.clock).filter { !$0.isEmpty }.sorted()
        var parts = [Strings.photos(photos.count, library.lang)]
        if let a = times.first, let b = times.last { parts.append(a == b ? a : "\(a)–\(b)") }
        if let p = event.placeLabel, !p.isEmpty { parts.append(p) }
        return parts.joined(separator: " · ")
    }
}

/// A chapter opened: its photos with their descriptions, each editable; a new chapter can start at any photo.
struct ChapterSheet: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let eventId: Int

    var event: TripEvent? { library.events.first { $0.id == eventId } }

    var body: some View {
        let photos = library.photos.filter { $0.eventId == eventId }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event?.name ?? "").font(.title.weight(.bold))
                    Text(library.tr("chapterSheetLead")).foregroundStyle(.secondary)
                }
                Spacer()
                // Escape closes; Return stays with the description being written.
                Button(library.tr("done")) { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.cancelAction)
            }
            .padding(24)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 22) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                        DescribedPhoto(photo: p, canSplit: i > 0)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            if photos.isEmpty {
                GuideEmpty(symbol: "photo.on.rectangle", title: library.tr("chapterEmpty"), text: "")
            }
        }
        .frame(minWidth: 900, minHeight: 640)
    }
}

struct DescribedPhoto: View {
    @EnvironmentObject var library: LibraryModel
    let photo: Photo
    let canSplit: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoCover(photo: photo, side: 520, radius: 14)
                .frame(height: 180)
                .opacity(photo.rejected ? 0.45 : 1)
                .overlay(alignment: .topTrailing) {
                    if photo.rejected {
                        Text(library.tr("leftOut")).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: .capsule).padding(8)
                    }
                }
            HStack(spacing: 6) {
                Text(photo.clock).monospacedDigit().font(.callout.weight(.medium))
                Text(photo.owner).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if photo.ai?.edited == true {
                    Label(library.tr("yourText"), systemImage: "pencil").font(.caption).foregroundStyle(.secondary)
                }
                if canSplit {
                    Button { library.newChapter(at: photo.id) } label: { Image(systemName: "scissors") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(library.tr("newChapterHere")).accessibilityLabel(library.tr("newChapterHere"))
                }
            }
            TextField(library.tr("descPlaceholder"), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .focused($focused)
                .padding(10)
                .background(.fill.quaternary, in: .rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: focused ? 2 : 0) }
                .contentShape(.rect)
                .onTapGesture { focused = true }          // the whole box starts editing, not only the text line
                .onSubmit { save() }
                .onChange(of: focused) { _, f in if !f { save() } }
        }
        .onAppear { text = photo.ai?.description ?? "" }
        .onDisappear { save() }                      // the sheet closed while typing
        .onChange(of: photo.ai?.description) { _, d in if !focused { text = d ?? "" } }
    }

    func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t != (photo.ai?.description ?? "") { library.setDescription(photo.id, t) }
    }
}
