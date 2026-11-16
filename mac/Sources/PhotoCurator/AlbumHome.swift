import CuratorCore
import SwiftUI

/// The album's home: the cover, what goes into the album, the one thing to do next, the four steps,
/// the best photos and who took them.
struct AlbumHome: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                AlbumHero()
                if library.photos.isEmpty && !library.job.running {
                    GuideEmpty(symbol: "sparkles", title: library.tr("nothingAnalysed"), text: library.tr("nothingAnalysedText"))
                } else {
                    if library.analysing { AnalysisCard() } else { NextCard() }
                    SettingsStrip()
                    if let f = library.overview?.funnel, f.taken > 0, !library.analysing { FunnelView(funnel: f) }
                    StepCards()
                    Highlights()
                    PeopleRow()
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 24)
            .frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }
    }
}

// MARK: hero

struct AlbumHero: View {
    @EnvironmentObject var library: LibraryModel
    @State private var editing = false
    @State private var name = ""
    @State private var editTrip: String?            // the album being renamed, kept if the owner switches albums
    @FocusState private var nameFocused: Bool

    var cover: Photo? {
        if let id = library.overview?.coverId, let p = library.photo(id) { return p }
        return coverPhoto(library.photos)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let cover {
                    Thumbnail(url: cover.fileURL, side: 2048)
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
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                        .focused($nameFocused)
                        .onSubmit { commit() }
                        .onExitCommand { editing = false }
                        .onChange(of: nameFocused) { _, f in if !f { commit() } }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(library.albumName).font(.system(size: 42, weight: .bold)).foregroundStyle(.white)
                            .lineLimit(2).shadow(color: .black.opacity(0.3), radius: 8)
                        Button {
                            name = library.albumName; editTrip = library.tripId; editing = true; nameFocused = true
                        } label: { Image(systemName: "pencil").font(.title3.weight(.semibold)) }
                            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                            .help(library.tr("renameAlbum")).accessibilityLabel(library.tr("renameAlbum"))
                    }
                }
                Text(facts).font(.title3).foregroundStyle(.white.opacity(0.88))
                    .contentTransition(.numericText())
            }
            .padding(28)
        }
        .clipShape(.rect(cornerRadius: 28))
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

// MARK: next

/// The single next thing to do, with photos of it and one button.
struct NextCard: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        if library.clocksWaiting > 0 {
            ClocksNextCard()
        } else if let step = library.next {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(String(format: library.tr("nextOf"), step.number), systemImage: "sparkles")
                        .font(.callout.weight(.semibold)).foregroundStyle(step.tint)
                    Text(title(step)).font(.system(size: 26, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text(text(step)).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { withAnimation(.snappy) { library.destination = .step(step) } } label: {
                        Label(library.tr("action_" + step.rawValue), systemImage: "arrow.right").labelStyle(TrailingIconLabel())
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.glassProminent).controlSize(.extraLarge).tint(step.tint)
                    .padding(.top, 6)
                    if step == .selection {
                        Button { library.startReview() } label: {
                            Label(String(format: library.tr("quickReviewN"), library.decisionsCount), systemImage: "rectangle.stack.badge.play")
                        }
                        .buttonStyle(.glass).controlSize(.large)
                        .help(library.tr("quickReviewHelp"))
                    }
                }
                Spacer(minLength: 0)
                PhotoMosaic(photos: photos(step)).frame(width: 320, height: 200)
            }
            .padding(24)
            .card(radius: 26, highlight: step.tint)
        } else {
            DoneCard()
        }
    }

    func title(_ s: GuideStep) -> String {
        let l = library.lang, o = library.overview
        switch s {
        case .selection:
            if let n = o?.moments.needYou, n > 0 { return String(format: library.tr("nextMoments"), Strings.count(n, .moment, l)) }
            return library.tr("nextSelection")
        case .story: return String(format: library.tr("nextStory"), Strings.count(library.events.count, .chapter, l))
        case .export: return String(format: library.tr("nextExport"), Strings.count(o?.funnel?.inAlbum ?? o?.export.photos ?? 0, .photo, l))
        }
    }

    func text(_ s: GuideStep) -> String { library.tr("nextText_" + s.rawValue) }

    func photos(_ s: GuideStep) -> [Photo] { stepPhotos(s, library) }
}

/// The photos that stand for a step on its cards.
@MainActor func stepPhotos(_ s: GuideStep, _ library: LibraryModel) -> [Photo] {
    let kept = library.photos.filter { !$0.rejected && !$0.isVideo }
    switch s {
    case .selection:
        let groups = kept.filter { $0.duplicate != nil && $0.duplicate?.category != "similar_scene" }
        return groups.isEmpty ? Array(kept.prefix(3)) : groups
    case .story:
        return library.events.compactMap { e in coverPhoto(kept.filter { $0.eventId == e.id }) }
    case .export:
        return (library.overview?.highlights ?? []).compactMap(library.photo) + kept.filter(\.favorite)
    }
}

/// Before the steps: a camera clock disagrees with the others and the owner has not looked at it yet.
struct ClocksNextCard: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Label(library.tr("firstCheck"), systemImage: "clock.badge.exclamationmark")
                    .font(.callout.weight(.semibold)).foregroundStyle(.teal)
                Text(String(format: library.tr("nextClocks"), library.clocksWaiting)).font(.system(size: 26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(library.tr("nextText_clocks")).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { withAnimation(.snappy) { library.destination = .people } } label: {
                    Label(library.tr("checkClocks"), systemImage: "arrow.right").labelStyle(TrailingIconLabel()).padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent).controlSize(.extraLarge).tint(.teal)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            Image(systemName: "clock.arrow.2.circlepath").font(.system(size: 90, weight: .thin)).foregroundStyle(.teal.gradient)
                .padding(.trailing, 30)
        }
        .padding(24)
        .card(radius: 26, highlight: .teal)
    }
}

struct DoneCard: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green.gradient)
            VStack(alignment: .leading, spacing: 4) {
                Text(library.tr("allDoneTitle")).font(.title2.weight(.bold))
                Text(library.tr("allDoneText")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(library.tr("openGooglePhotos")) { NSWorkspace.shared.open(URL(string: "https://photos.google.com/")!) }
                .buttonStyle(.glass).controlSize(.large)
        }
        .padding(24)
        .card(radius: 26, highlight: .green)
    }
}

// MARK: funnel

/// From everything taken to what goes into the album, as one bar whose parts add up.
struct FunnelView: View {
    @EnvironmentObject var library: LibraryModel
    let funnel: Overview.Funnel

    var body: some View {
        let parts = funnelParts(funnel)
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: library.tr("funnelTitle"),
                         detail: String(format: library.tr("funnelLead"), Strings.photos(funnel.taken, library.lang), funnel.inAlbum))
            GeometryReader { g in
                HStack(spacing: 3) {
                    ForEach(parts) { p in
                        Rectangle().fill(color(p.kind).gradient)
                            .frame(width: max(6, (g.size.width - CGFloat(parts.count - 1) * 3) * CGFloat(p.count) / CGFloat(max(1, funnel.taken))))
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 16)
            HStack(spacing: 10) {
                ForEach(parts) { p in
                    Button { open(p.kind) } label: {
                        HStack(spacing: 8) {
                            Circle().fill(color(p.kind)).frame(width: 10, height: 10)
                            Text("\(p.count)").font(.headline).monospacedDigit()
                            Text(library.tr("funnel_" + p.kind.rawValue)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.fill.quaternary, in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help(library.tr("funnelHelp_" + p.kind.rawValue))
                }
            }
        }
        .padding(22)
        .card()
    }

    func color(_ k: FunnelPart.Kind) -> Color {
        switch k {
        case .inAlbum: .green
        case .extraFrames: .blue
        case .blurry: .orange
        case .leftOut: .gray
        }
    }

    func open(_ k: FunnelPart.Kind) {
        withAnimation(.snappy) {
            switch k {
            case .inAlbum: library.destination = .step(.export)
            case .extraFrames: library.selectionView = .moments; library.destination = .step(.selection)
            case .blurry: library.selectionView = .blurry; library.destination = .step(.selection)
            case .leftOut: library.selectionView = .leftOut; library.destination = .step(.selection)
            }
        }
    }
}

// MARK: the four steps

struct StepCards: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        let states = library.stepStates
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: library.tr("guideTitle"), detail: library.tr("guideLead"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: GuideStep.allCases.count), spacing: 16) {
                ForEach(GuideStep.allCases) { s in
                    let st = states[s] ?? StepState(done: false, waiting: 0)
                    Button { withAnimation(.snappy) { library.destination = .step(s) } } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            PhotoMosaic(photos: stepPhotos(s, library), radius: 16).frame(height: 130)
                                .overlay(alignment: .topLeading) {
                                    Text("\(s.number)").font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white).frame(width: 28, height: 28)
                                        .background(s.tint.gradient, in: .circle).padding(10)
                                }
                            HStack(spacing: 8) {
                                Text(library.tr("step_" + s.rawValue)).font(.headline)
                                Spacer()
                                if st.done {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else if st.waiting > 0 {
                                    Text("\(st.waiting)").font(.caption.weight(.bold)).monospacedDigit()
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(.orange.opacity(0.2), in: .capsule).foregroundStyle(.orange)
                                }
                            }
                            Text(status(s, st)).font(.callout).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                        }
                        .padding(14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .card(radius: 22, hover: true, highlight: library.next == s ? s.tint : nil)
                }
            }
        }
    }

    func status(_ s: GuideStep, _ st: StepState) -> String {
        let l = library.lang
        guard let o = library.overview, !library.analysing else { return library.tr("stillAnalysing") }
        switch s {
        case .selection:
            if o.moments.needYou > 0 { return String(format: library.tr("momentsWait"), Strings.count(o.moments.needYou, .moment, l)) }
            return String(format: library.tr("momentsChosen"), Strings.count(o.moments.total, .moment, l))
        case .story:
            return Strings.count(library.events.count, .chapter, l) + " · " + Strings.count(o.events.days, .day, l)
        case .export:
            return o.export.done ? library.tr("exportDone")
                : String(format: library.tr("exportReadyShort"), Strings.photos(o.funnel?.inAlbum ?? o.export.photos, l))
        }
    }
}

// MARK: highlights and people

struct Highlights: View {
    @EnvironmentObject var library: LibraryModel

    var picks: [Photo] {
        let ids = library.overview?.highlights ?? []
        let fromEngine = ids.compactMap(library.photo)
        if !fromEngine.isEmpty { return fromEngine }
        // Before the engine has ranks: one photo per chapter.
        return library.events.compactMap { e in coverPhoto(library.photos.filter { $0.eventId == e.id }) }
    }

    var body: some View {
        let p = picks
        if !p.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: library.tr("highlightsTitle"), detail: library.tr("highlightsLead"))
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(p) { photo in
                            PhotoCover(photo: photo, side: 520, radius: 18)
                                .frame(width: tileWidth(photo), height: 200)
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                                .onTapGesture { library.destination = .all; library.click(photo, modifiers: []) }
                                .help(photo.filename)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    func tileWidth(_ p: Photo) -> CGFloat {
        guard let w = p.width, let h = p.height, h > 0 else { return 270 }
        return min(360, max(140, 200 * CGFloat(w) / CGFloat(h)))
    }
}

struct PeopleRow: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        if let people = library.overview?.people, people.count > 0, !library.analysing {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(title: library.tr("peopleTitle"), detail: library.tr("peopleLead"))
                    Button { withAnimation(.snappy) { library.destination = .people } } label: {
                        Label(library.tr("editPeople"), systemImage: "pencil")
                    }
                    .buttonStyle(.glass)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { i, p in
                        let index = library.sources.firstIndex { $0.id == p.sourceId } ?? i
                        HStack(spacing: 14) {
                            PersonBadge(name: p.owner, index: index, size: 46)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(p.owner).font(.headline)
                                Text(String(format: library.tr("personCounts"), Strings.photos(p.taken, library.lang), p.inAlbum))
                                    .font(.callout).foregroundStyle(.secondary)
                                ProgressView(value: Double(p.inAlbum), total: Double(max(1, p.taken)))
                                    .tint(personColor(index))
                            }
                        }
                        .padding(16)
                        .card()
                    }
                }
            }
        }
    }
}
