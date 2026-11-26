import CuratorCore
import SwiftUI

// M12f: the album home as a story (roadmap M18.2, without maps and without new engine data). The header lives in
// AlbumHome.swift (`AlbumHero`); this file has its pieces: the counters on the cover, the day cards and the
// always-visible way back to the sorting stage (audit #30).

// MARK: header pieces

/// Dates and places under the album name: "Thu 23 Oct – Sun 26 Oct · Pienza, Siena".
@MainActor func albumSubtitle(_ library: LibraryModel) -> String {
    let l = library.lang
    var parts: [String] = []
    if let f = library.overview?.facts, let span = albumDaySpan(start: f.start, end: f.end) {
        let first = formatDay(span.first, l, style: .short)
        parts.append(span.last.map { first + " – " + formatDay($0, l, style: .short) } ?? first)
    }
    if let places = library.overview?.facts.places, !places.isEmpty {
        parts.append(places.prefix(3).joined(separator: ", "))
    }
    return parts.joined(separator: " · ")
}

/// The album's numbers on the cover; digits roll when they change (numericText, `settle`).
struct StoryCounters: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        let l = library.lang
        let funnel = library.overview?.funnel
        let taken = funnel?.taken ?? library.photos.count
        let inAlbum = funnel?.inAlbum ?? library.photos.filter(\.goesToAlbumDespiteFocus).count
        let days = library.overview?.facts.days ?? 0
        let chapters = library.events.count
        HStack(spacing: Space.m) {
            pill(String(format: library.tr("storyInAlbum"), inAlbum), symbol: "checkmark.circle.fill", value: inAlbum)
            pill(String(format: library.tr("storyTaken"), Strings.photos(taken, l)), symbol: "camera", value: taken)
            if days > 0 { pill(Strings.count(days, .day, l), symbol: "calendar", value: days) }
            if chapters > 0 { pill(Strings.count(chapters, .chapter, l), symbol: "book.closed", value: chapters) }
        }
        .motionAnimation(.settle, value: [inAlbum, taken, days, chapters])
    }

    /// Dark translucent pill on the photo (no glass on photos).
    func pill(_ text: String, symbol: String, value: Int) -> some View {
        Label {
            Text(text).contentTransition(.numericText(value: Double(value)))
        } icon: {
            Image(systemName: symbol)
        }
        .font(TypeRole.label.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
        .background(.black.opacity(0.38), in: .capsule)
    }
}

/// Watch the sorting while it runs, or play it again: always on Home (audit #30), in the funnel card's header.
struct ReplaySortingButton: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        Button { library.showSorting(replay: !library.analysing) } label: {
            Label(library.analysing ? library.tr("stageWatch") : library.tr("stageReplay"),
                  systemImage: "sparkles.rectangle.stack")
        }
        .buttonStyle(.bordered)
        .help(library.tr("stageLinkText"))
    }
}

// MARK: day cards

/// The album day by day: each day's best photo, how many photos, the chapter names. A click opens All Photos on
/// that day's cover. Cards fade a little at the row's edges while scrolling (off under Reduce Motion).
struct DayStory: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cards = dayCards(photos: library.photos, events: library.events, highlights: library.overview?.highlights ?? [])
        let still = reduceMotion
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: Space.l) {
                SectionTitle(title: library.tr("daysTitle"), detail: library.tr("daysLead"))
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Space.xl) {
                        ForEach(cards) { card in
                            DayCardView(card: card)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .opacity(phase.isIdentity ? 1 : 0.55)
                                        .scaleEffect(phase.isIdentity || still ? 1 : 0.95)
                                }
                        }
                    }
                    .padding(.vertical, Space.m)
                    .padding(.horizontal, Space.xs)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct DayCardView: View {
    @EnvironmentObject var library: LibraryModel
    let card: DayCard

    var body: some View {
        let cover = card.coverId.flatMap(library.photo)
        Button { open(cover) } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                Group {
                    if let cover {
                        PhotoCover(photo: cover, side: 520, radius: Radius.large)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.large).fill(.fill.quaternary)
                    }
                }
                .frame(height: 150)
                Text(formatDay(card.day, library.lang, style: .short)).font(TypeRole.cardTitle)
                Text(String(format: library.tr("dayCounts"), Strings.photos(card.taken, library.lang), card.inAlbum))
                    .font(TypeRole.label).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                chips
            }
            .padding(Space.l)
            .frame(width: 260, alignment: .leading)
            .card(radius: Radius.card)
        }
        .buttonStyle(.pressableCard)
        .disabled(cover == nil)
        .help(card.place ?? formatDay(card.day, library.lang, style: .long))
        .accessibilityLabel(accessibilityText)
    }

    /// Up to two chapter names and "+n".
    @ViewBuilder var chips: some View {
        HStack(spacing: Space.xs) {
            ForEach(card.chapters.prefix(2), id: \.self) { name in
                chip(name)
            }
            if card.chapters.count > 2 { chip("+\(card.chapters.count - 2)") }
        }
        .frame(minHeight: 22, alignment: .leading)
    }

    func chip(_ text: String) -> some View {
        Text(text).font(TypeRole.caption.weight(.medium)).lineLimit(1)
            .padding(.horizontal, Space.m).padding(.vertical, Space.xxs)
            .background(.fill.tertiary, in: .capsule)
    }

    var accessibilityText: String {
        var parts = [formatDay(card.day, library.lang, style: .long),
                     String(format: library.tr("dayCounts"), Strings.photos(card.taken, library.lang), card.inAlbum)]
        if !card.chapters.isEmpty { parts.append(card.chapters.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }

    func open(_ cover: Photo?) {
        guard let cover else { return }
        withMotion(.settle) { library.destination = .all }
        library.click(cover, modifiers: [])
    }
}
