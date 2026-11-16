import CuratorCore
import SwiftUI

/// Step 3: the album as a story. Days hold chapters (the engine's events); every chapter can be
/// renamed, merged with the one before, opened, and split at a photo. (No descriptions: Google Photos writes
/// its own, decided 2026-11-16.)
struct StepStory: View {
    @EnvironmentObject var library: LibraryModel
    @State private var open: TripEvent?

    var body: some View {
        StepPage(step: .story, lead: library.tr("lead_story"), status: status) {
            VStack(alignment: .leading, spacing: 30) {
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

/// One chapter: cover, name editable in place, time and place, a strip of its photos.
struct ChapterCard: View {
    @EnvironmentObject var library: LibraryModel
    let event: TripEvent
    let first: Bool
    let open: () -> Void
    @State private var name = ""
    @State private var trip: String?
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
                        .onSubmit { library.renameEvent(event.id, to: name, trip: trip) }
                        .onChange(of: focused) { _, f in if !f { library.renameEvent(event.id, to: name, trip: trip) } }
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
        .onAppear { name = event.name; trip = library.shownTrip }
        .onDisappear { if focused { library.renameEvent(event.id, to: name, trip: trip) } }
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

/// A chapter opened: its photos; a new chapter can start at any photo.
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
                Button(library.tr("done")) { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
            .padding(24)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 18) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                        ChapterPhoto(photo: p, canSplit: i > 0)
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

/// A photo of an opened chapter; the scissors start a new chapter at it.
struct ChapterPhoto: View {
    @EnvironmentObject var library: LibraryModel
    let photo: Photo
    let canSplit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotoCover(photo: photo, side: 520, radius: 14)
                .frame(height: 170)
                .opacity(photo.rejected ? 0.45 : 1)
                .overlay(alignment: .topTrailing) {
                    if photo.rejected {
                        Text(library.tr("leftOut")).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: .capsule).padding(8)
                    }
                }
            HStack(spacing: 8) {
                Text(photo.clock).monospacedDigit().font(.callout.weight(.medium))
                Text(photo.owner).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if canSplit {
                    Button { library.newChapter(at: photo.id) } label: { Label(library.tr("newChapterShort"), systemImage: "scissors") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                        .help(library.tr("newChapterHere")).accessibilityLabel(library.tr("newChapterHere"))
                }
            }
        }
    }
}
