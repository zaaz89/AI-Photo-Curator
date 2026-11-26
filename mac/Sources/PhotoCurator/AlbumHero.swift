import CuratorCore
import SwiftUI

/// The album's cover on the path's Album station (M12f, M14a): the cover photo with a slow parallax, the name
/// (renamed in place), dates and numbers, the counters and who took the photos.
struct AlbumHero: View {
    @EnvironmentObject var library: LibraryModel
    @State private var editing = false
    @State private var name = ""
    @State private var editTrip: String?            // the album being renamed, kept if the owner switches albums
    @FocusState private var nameFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The engine's cover while it is in the album, else the best kept photo (M12f, `albumCover`).
    var cover: Photo? {
        albumCover(library.photos, coverId: library.overview?.coverId, highlights: library.overview?.highlights ?? [])
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let cover {
                    // Slow parallax while the page scrolls (M12f): the photo moves at a fraction of the scroll and is
                    // slightly enlarged so no edge shows. Still under Reduce Motion.
                    let still = reduceMotion
                    Thumbnail(url: cover.fileURL, side: 2048)
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .scaleEffect(still ? 1 : 1.12)
                                .offset(y: still ? 0 : -phase.value * 20)
                        }
                } else {
                    LinearGradient(colors: aiGradientColors.map { $0.opacity(0.55) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(height: 360).frame(maxWidth: .infinity)
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.72), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            VStack(alignment: .leading, spacing: 8) {
                if editing {
                    TextField(library.tr("albumNamePrompt"), text: $name)
                        .textFieldStyle(.plain)
                        .scaledFont(42, weight: .bold, relativeTo: .largeTitle)
                        .foregroundStyle(.white)
                        .focused($nameFocused)
                        .onSubmit { commit() }
                        .onExitCommand { editing = false }
                        .onChange(of: nameFocused) { _, f in if !f { commit() } }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(library.albumName).scaledFont(42, weight: .bold, relativeTo: .largeTitle).foregroundStyle(.white)
                            .lineLimit(2).shadow(color: .black.opacity(0.3), radius: 8)
                        Button {
                            name = library.albumName; editTrip = library.tripId; editing = true; nameFocused = true
                        } label: { Image(systemName: "pencil").font(.title3.weight(.semibold)) }
                            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                            .help(library.tr("renameAlbum")).accessibilityLabel(library.tr("renameAlbum"))
                    }
                }
                let subtitle = albumSubtitle(library)
                Text(subtitle.isEmpty ? facts : subtitle).font(.title3).foregroundStyle(.white.opacity(0.88))
                    .contentTransition(.numericText())
                if !library.photos.isEmpty { StoryCounters().padding(.top, Space.xs) }
            }
            .padding(28)
        }
        .clipShape(.rect(cornerRadius: Radius.hero))
        .onChange(of: library.tripId) { _, _ in commit() }      // a half-typed name goes to its own album
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
        .overlay(alignment: .topTrailing) { peopleStack.padding(20) }
    }

    func commit() {
        if editing { library.renameAlbum(name, trip: editTrip) }
        editing = false
    }

    var facts: String {
        guard let f = library.overview?.facts else { return Strings.photos(library.photos.count, library.lang) }
        let l = library.lang
        var parts = [Strings.count(f.photos - f.videos, .photo, l)]
        if f.videos > 0 { parts.append(Strings.count(f.videos, .video, l)) }
        if f.days > 0 { parts.append(Strings.count(f.days, .day, l)) }
        if !f.places.isEmpty { parts.append(f.places.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    var peopleStack: some View {
        HStack(spacing: -10) {
            ForEach(Array(library.sources.enumerated()), id: \.element.id) { i, s in
                PersonBadge(name: s.owner, index: i, size: 40).help(s.owner)
            }
        }
    }
}
