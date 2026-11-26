import AppKit
import CuratorCore
import SwiftUI

// M14a "one album, one path". An album is one journey with four stations (Photos, Analysis, Questions, Album),
// a slim rail at the top and ONE primary button at the bottom. Where the album is comes from `AlbumJourney`
// (CuratorCore, pure and tested); this file only draws it. See notes/m14a-journey.md.

enum JourneyLayout {
    /// Height of the primary bar; toasts and the selection bar float above it.
    static let barHeight: CGFloat = 84
}

/// The album's path: rail, the station on screen, the primary bar.
struct AlbumJourneyView: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The station shown before the last change (sets the direction of the horizontal settle).
    @State private var lastShown: JourneyStation = .photos
    /// The station whose completion moment plays (≤ 0.6 s, never blocks).
    @State private var completing: JourneyStation?

    /// The album and its current station, so a change of album never plays a completion moment.
    struct Key: Equatable { let trip: String?; let station: JourneyStation }

    var body: some View {
        let journey = library.journey
        let shown = journey.shown(library.station)
        let forward = shown >= lastShown
        VStack(spacing: 0) {
            JourneyRail(journey: journey, shown: shown, completing: completing)
                .padding(.top, Space.m)
                .padding(.bottom, Space.m)
            ZStack {
                station(shown)
                    .id(shown)
                    .motionTransition(.asymmetric(
                        insertion: .offset(x: forward ? 56 : -56).combined(with: .opacity),
                        removal: .offset(x: forward ? -56 : 56).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            JourneyPrimaryBar(journey: journey, shown: shown)
        }
        .motionAnimation(.settle, value: shown)
        .onChange(of: shown) { _, new in lastShown = new }
        .onAppear { lastShown = shown }
        .onChange(of: Key(trip: library.shownTrip, station: journey.current)) { old, new in
            guard old.trip != nil, old.trip == new.trip else { return }
            let done = completedStations(from: old.station, to: new.station)
            guard let last = done.last else { return }
            library.station = nil                                   // the path follows the album forward
            // Sorting went straight to the album: nothing was unsure. Say so instead of a silent skip.
            if done.contains(.decisions) && old.station < .decisions { library.message = library.tr("journeyNoQuestions") }
            completing = last
            Task {
                try? await Task.sleep(for: .seconds(motionBudget))
                if completing == last { withMotion(.fade, reduceMotion: reduceMotion) { completing = nil } }
            }
        }
    }

    @ViewBuilder func station(_ s: JourneyStation) -> some View {
        switch s {
        case .photos: PhotosStation()
        case .analysis: SortingStage()
        case .decisions: QuestionsStation()
        case .album: AlbumStation()
        }
    }
}

// MARK: rail

/// The four stations as one slim rail. The current station and every one before it can be opened; the pill
/// under the station on screen slides between them (matched geometry). A station that just completed shows its
/// check with one bounce and a short ring (Reduce Motion: the check only).
struct JourneyRail: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rail
    let journey: AlbumJourney
    let shown: JourneyStation
    let completing: JourneyStation?

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(JourneyStation.allCases) { s in
                stationButton(s)
                if s != .album {
                    Capsule()
                        .fill(journey.isComplete(s) ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
                        .frame(width: Space.xxxl, height: 2)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .glassEffect(.regular, in: .capsule)                  // navigation: Liquid Glass is allowed here
        .motionAnimation(.settle, value: shown)
        .motionAnimation(.quick, value: journey.current)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(library.tr("journeyRail"))
    }

    func stationButton(_ s: JourneyStation) -> some View {
        let open = journey.canOpen(s)
        let complete = journey.isComplete(s)
        let isShown = s == shown
        return Button { withMotion(.settle, reduceMotion: reduceMotion) { library.open(station: s) } } label: {
            HStack(spacing: Space.s) {
                ZStack {
                    Circle().fill(isShown ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                    if complete {
                        Image(systemName: "checkmark")
                            .font(TypeRole.caption.weight(.bold))
                            .foregroundStyle(isShown ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                            .symbolBounce(on: completing == s)
                    } else if s == .analysis && journey.input.analysing {
                        AIRing(symbol: "sparkles", size: 22, spinning: true, progress: journey.ringProgress)
                            .foregroundStyle(isShown ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    } else {
                        Text("\(s.number)").font(TypeRole.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(isShown ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    }
                }
                .frame(width: 22, height: 22)
                .overlay {
                    if completing == s && !reduceMotion { CompletionRing() }
                }
                Text(s.title(library.lang))
                    .font(TypeRole.label.weight(isShown ? .semibold : .regular))
                    .foregroundStyle(!open ? AnyShapeStyle(.tertiary) : (isShown ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
                if s == .decisions, case .answer(let n) = journey.action, !isShown {
                    Text("\(n)").font(TypeRole.caption.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
                        .background(StatusColor.look.opacity(0.18), in: .capsule)
                        .foregroundStyle(StatusColor.lookText)
                        .contentTransition(.numericText(value: Double(n)))
                }
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .background {
                if isShown {
                    Capsule().fill(.tint.opacity(0.14))
                        .matchedGeometryEffect(id: "shownStation", in: rail)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .help(open ? s.title(library.lang) + "  (⌘\(s.menuDigit))" : library.tr("journeyStationLater"))
        .accessibilityLabel("\(s.number). " + s.title(library.lang))
        .accessibilityValue(complete ? library.tr("journeyStationDone") : (s == journey.current ? library.tr("journeyStationNow") : ""))
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }
}

/// The short ring of a station that just completed: grows and fades once (≤ 0.6 s).
private struct CompletionRing: View {
    @State private var on = false
    var body: some View {
        Circle().strokeBorder(.tint, lineWidth: 2)
            .scaleEffect(on ? 1.9 : 1)
            .opacity(on ? 0 : 0.7)
            .onAppear { withMotion(.arrive) { on = true } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: primary bar

/// The one primary button of the album, with what it waits for. Its label morphs when the action changes
/// ("Start" → "Continue" → "Answer 6 questions" → "Export 187 photos" → "Open Folder"). ⌘Return.
struct JourneyPrimaryBar: View {
    @EnvironmentObject var library: LibraryModel
    let journey: AlbumJourney
    let shown: JourneyStation

    var body: some View {
        let title = journey.actionTitle(library.lang)
        HStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(journey.status(library.lang))
                    .font(TypeRole.cardTitle)
                    .contentTransition(.numericText())
                if let why = journey.waitReason(library.lang) ?? hint {
                    Text(why).font(TypeRole.supporting).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.l)
            if journey.input.analysing && shown != .analysis {
                Button(library.tr("journeyWatch")) { library.open(station: .analysis) }.buttonStyle(.glass).controlSize(.large)
            }
            Button { library.performPrimary() } label: {
                Label {
                    Text(title).contentTransition(.interpolate)
                } icon: {
                    Image(systemName: journey.actionSymbol).contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, Space.m)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .disabled(!journey.action.isEnabled)
            .keyboardShortcut(.return, modifiers: .command)
            .help(title + "  (⌘↩)")
            .accessibilityHint(journey.waitReason(library.lang) ?? "")
            .motionAnimation(.quick, value: title)
        }
        .padding(.horizontal, Space.huge).padding(.vertical, Space.l)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// A line under the status that says what the button will do, where it helps.
    var hint: String? {
        switch journey.action {
        case .start: library.tr("journeyStartHint")
        case .resume: library.tr("journeyResumeHint")
        case .answer: library.tr("journeyAnswerHint")
        case .openFolder: library.tr("journeyDoneHint")
        default: nil
        }
    }
}

// MARK: station 1: photos

/// Whose photos are in the album: one chip per folder (person and camera), drop or add more, remove one with ×.
/// Camera clocks are aligned by themselves; they only come up here when the app is not sure.
struct PhotosStation: View {
    @EnvironmentObject var library: LibraryModel
    @State private var targeted = false
    @State private var removing: SourceInfo?

    var body: some View {
        let journey = library.journey
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxxl) {
                StationHeader(title: library.tr("photosStationTitle"), lead: library.tr("photosStationLead"))
                if !library.sources.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: Space.l)], spacing: Space.l) {
                        ForEach(Array(library.sources.enumerated()), id: \.element.id) { i, s in
                            FolderChip(source: s, index: i, removable: !library.job.running) { removing = s }
                                .motionTransition(.scale(scale: 0.94).combined(with: .opacity))
                        }
                    }
                }
                dropZone(big: library.sources.isEmpty)
                if journey.input.started { clocksLine(journey) }
                Label(library.tr("readOnlyNote"), systemImage: "lock.shield")
                    .font(TypeRole.supporting).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.huge).padding(.vertical, Space.xxxl)
            .frame(maxWidth: 980).frame(maxWidth: .infinity)
        }
        .motionAnimation(.arrive, value: library.sources)
        .confirmationDialog(removing.map { confirm($0).title } ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { s in
            Button(confirm(s).button, role: .destructive) { library.removeFolder(s); removing = nil }
            Button(library.tr("removeFolderKeep"), role: .cancel) { removing = nil }
        } message: { s in
            Text(confirm(s).message)
        }
    }

    func confirm(_ s: SourceInfo) -> (title: String, message: String, button: String) {
        removeFolderConfirm(sourceChipName(s, among: library.sources), photos: s.assets ?? 0, library.lang)
    }

    func dropZone(big: Bool) -> some View {
        Button { library.chooseFolders() } label: {
            VStack(spacing: Space.m) {
                Image(systemName: "folder.badge.plus").font(big ? TypeRole.heroSymbol : .title2).foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: targeted)
                Text(library.tr(big ? "dropFolders" : "photosStationAddMore")).font(TypeRole.cardTitle)
                if big { Text(library.tr("photosStationDropHint")).font(TypeRole.supporting).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, minHeight: big ? 220 : 96)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: Radius.large)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .background(targeted ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: Radius.large))
        }
        .dropDestination(for: URL.self) { urls, _ in library.addFolders(urls); return true } isTargeted: { targeted = $0 }
        .motionAnimation(.quick, value: targeted)
        .accessibilityLabel(library.tr("dropFolders"))
        .accessibilityHint(library.tr("photosStationDropHint"))
    }

    @ViewBuilder func clocksLine(_ journey: AlbumJourney) -> some View {
        let unsure = journey.input.unsureClocks
        HStack(spacing: Space.m) {
            if unsure > 0 && !journey.input.decisionsDone {
                Image(systemName: "clock.badge.questionmark").foregroundStyle(StatusColor.warning)
                Text(String(format: library.tr("photosStationClocksUnsure"), unsure)).font(TypeRole.body)
                Spacer()
                Button(library.tr("photosStationClocksCheck")) { library.destination = .people }.buttonStyle(.glass)
            } else {
                Image(systemName: "clock.badge.checkmark").foregroundStyle(StatusColor.kept)
                Text(library.tr(journey.analysisSettled ? "photosStationClocksOK" : "photosStationClocksLater"))
                    .font(TypeRole.body).foregroundStyle(.secondary)
                Spacer()
                Button(library.tr("photosStationPeople")) { library.destination = .people }.buttonStyle(.link)
            }
        }
        .padding(Space.xl)
        .card(radius: Radius.large)
    }
}

/// One folder of the album as a chip: the person's badge, "Ana · iPhone 15", the folder and its photo count,
/// and × to take it out of the album (with a confirmation; the folder itself is never touched).
struct FolderChip: View {
    @EnvironmentObject var library: LibraryModel
    let source: SourceInfo
    let index: Int
    let removable: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Space.l) {
            PersonBadge(name: source.owner, index: index, size: 40)
            VStack(alignment: .leading, spacing: Space.xxs) {
                // M14c: unique in the album ("Jarek Pawlak · Ceremony"), from the engine.
                Text(sourceChipName(source, among: library.sources))
                    .font(TypeRole.cardTitle).lineLimit(1).truncationMode(.middle)
                Text(details).font(TypeRole.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!removable)
            .help(removable ? library.tr("removeFolderHelp") : library.tr("removeFolderBusy"))
            .accessibilityLabel(String(format: library.tr("removeFolderA11y"), sourceChipName(source, among: library.sources)))
        }
        .padding(Space.l)
        .card(radius: Radius.large, hover: true)
        .contextMenu {
            Button(library.tr("showInFinder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source.path)])
            }
            Button(library.tr("photosStationPeople")) { library.destination = .people }
            Divider()
            Button(library.tr("removeFolderMenu"), role: .destructive, action: remove).disabled(!removable)
        }
        .accessibilityElement(children: .combine)
    }

    var details: String {
        var parts = [URL(fileURLWithPath: source.path).lastPathComponent]
        if let n = source.assets, n > 0 { parts.append(Strings.photos(n, library.lang)) }
        return parts.joined(separator: " · ")
    }
}

/// The title and lead of a station page.
struct StationHeader: View {
    let title: String
    let lead: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).scaledFont(30, weight: .bold, relativeTo: .title)
            Text(lead).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: station 3: questions

/// The open questions as one card stack: how many, about how long, what kind. "Answer N questions" (the primary
/// button) runs a quick review of exactly those photos; "Accept the Rest" keeps the app's choices.
struct QuestionsStation: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        let journey = library.journey
        let input = journey.input
        ScrollView {
            VStack(spacing: Space.xxxl) {
                if journey.questions > 0 {
                    CardStack(photos: samplePhotos)
                        .frame(width: 300, height: 220)
                        .padding(.top, Space.xl)
                    VStack(spacing: Space.s) {
                        Text(Strings.count(journey.questions, .question, library.lang))
                            .scaledFont(34, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                            .contentTransition(.numericText(value: Double(journey.questions)))
                        Text(Strings.duration(questionsEstimate(moments: input.openMoments, look: input.haveALook,
                                                                clocks: input.unsureClocks), library.lang))
                            .font(.title3).foregroundStyle(.secondary)
                        Text(library.tr("questionsLead")).font(TypeRole.body).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 520)
                    }
                    VStack(spacing: Space.s) {
                        if input.openMoments > 0 {
                            questionRow("square.stack.3d.up", String(format: library.tr("questionsMoments"), Strings.count(input.openMoments, .moment, library.lang)),
                                action: library.tr("questionsOpenMoments")) { library.destination = .moments }
                        }
                        if input.haveALook > 0 {
                            questionRow("eye", String(format: library.tr("questionsLook"), Strings.photos(input.haveALook, library.lang)), action: nil) {}
                        }
                        if input.unsureClocks > 0 {
                            questionRow("clock.badge.questionmark", String(format: library.tr("questionsClocks"), input.unsureClocks),
                                action: library.tr("photosStationClocksCheck")) { library.destination = .people }
                        }
                    }
                    .frame(maxWidth: 560)
                    Button(library.tr("acceptRest")) { library.acceptQuestions() }
                        .buttonStyle(.glass).controlSize(.large)
                        .help(library.tr("questionsAcceptHelp"))
                    SettingsStrip().frame(maxWidth: 560)
                } else {
                    answered
                }
            }
            .padding(.horizontal, Space.huge).padding(.vertical, Space.xxxl)
            .frame(maxWidth: .infinity)
        }
        .motionAnimation(.settle, value: journey.questions)
    }

    var answered: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "checkmark.seal.fill").font(TypeRole.heroSymbol).foregroundStyle(StatusColor.kept.gradient)
                .symbolBounce(on: true)
            Text(library.tr("questionsDoneTitle")).font(TypeRole.pageTitle)
            Text(library.tr("questionsDoneText")).font(TypeRole.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 480)
            HStack(spacing: Space.l) {
                Button(library.tr("questionsReviewAgain")) { library.startReview() }.buttonStyle(.glass)
                Button(library.tr("questionsOpenMoments")) { library.destination = .moments }.buttonStyle(.link)
            }
        }
        .padding(.top, Space.giant)
    }

    func questionRow(_ symbol: String, _ text: String, action: String?, perform: @escaping () -> Void) -> some View {
        HStack(spacing: Space.l) {
            Image(systemName: symbol).foregroundStyle(StatusColor.look).frame(width: 24)
            Text(text).font(TypeRole.body)
            Spacer()
            if let action { Button(action, action: perform).buttonStyle(.link) }
        }
        .padding(.horizontal, Space.xl).padding(.vertical, Space.l)
        .card(radius: Radius.medium)
    }

    /// Up to three photos for the stack: the "Have a look" ones first, then the best frames of moments.
    var samplePhotos: [Photo] {
        let look = library.photos.filter { sortVerdict($0) == .check }
        let moments = library.photos.filter { isMomentFrame($0) && $0.duplicate?.keeper == true }
        return Array((look + moments).prefix(3))
    }
}

/// Three photo cards fanned out a little: the questions as a stack to go through.
struct CardStack: View {
    let photos: [Photo]
    var body: some View {
        ZStack {
            ForEach(Array(photos.prefix(3).enumerated().reversed()), id: \.element.id) { i, p in
                PhotoCover(photo: p, side: 520, radius: Radius.large)
                    .frame(width: 240, height: 170)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                    .rotationEffect(.degrees(Double(i) * 5 - 5))
                    .offset(x: CGFloat(i) * 14 - 14, y: CGFloat(i) * -6)
            }
            if photos.isEmpty {
                RoundedRectangle(cornerRadius: Radius.large).fill(.fill.tertiary).frame(width: 240, height: 170)
                Image(systemName: "questionmark.bubble").font(TypeRole.heroSymbol).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: station 4: album

/// The album as it will be exported: the cover with its numbers, the export inline, the days. Once exported:
/// Done, with Open Folder as the primary button and Clear Working Data as the way to finish.
struct AlbumStation: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        let journey = library.journey
        ScrollView {
            VStack(alignment: .leading, spacing: Space.huge) {
                AlbumHero()
                if journey.isDone { done }
                StepExport()
                DayStory()
            }
            .padding(.horizontal, Space.huge).padding(.vertical, Space.xxxl)
            .frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }
    }

    var done: some View {
        HStack(spacing: Space.l) {
            Image(systemName: "checkmark.seal.fill").font(.title).foregroundStyle(StatusColor.kept.gradient)
                .symbolBounce(on: library.exported)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(library.tr("albumDoneTitle")).font(TypeRole.sectionTitle)
                Text(library.tr("albumDoneText")).font(TypeRole.supporting).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(library.tr("albumExportAgain")) { library.requestExport() }.buttonStyle(.glass)
            Button(library.tr("clearWorkingData")) { library.removeAlbumRequest = library.tripId }.buttonStyle(.glass)
                .help(library.tr("clearWorkingDataHelp"))
        }
        .padding(Space.xl)
        .card()
    }
}
