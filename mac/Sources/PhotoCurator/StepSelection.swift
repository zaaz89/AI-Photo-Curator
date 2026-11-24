import CuratorCore
import SwiftUI

/// Step 2: the best of each moment, blurry photos, and what was left out. Nothing is deleted;
/// left-out photos only stay out of the export.
struct StepSelection: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        StepPage(step: .selection, lead: library.tr("lead_selection"), status: status, scrolls: false) {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    Picker("", selection: $library.selectionView) {
                        ForEach(SelectionView.allCases) { v in Text(label(v)).tag(v) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 560)
                    Button { library.startReview() } label: {
                        Label(library.tr("quickReview") + "  ⌘R", systemImage: "rectangle.stack.badge.play")
                    }
                    .buttonStyle(.glassProminent).help(library.tr("quickReviewHelp"))
                }
                .padding(.horizontal, 8)
                Group {
                    switch library.selectionView {
                    case .moments: MomentsPanel()
                    case .blurry: ToggleGrid(kind: .blurry)
                    case .leftOut: ToggleGrid(kind: .leftOut)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var status: String {
        let n = library.overview?.moments.needYou ?? 0
        return n > 0 ? String(format: library.tr("momentsWait"), Strings.count(n, .moment, library.lang)) : library.tr("selectionStatusDone")
    }

    func label(_ v: SelectionView) -> String {
        switch v {
        case .moments:
            let n = library.overview?.moments.needYou ?? 0
            return library.tr("segMoments") + (n > 0 ? " · \(n)" : "")
        case .blurry: return library.tr("segBlurry") + " · \(library.photos.filter(\.foundBlurry).count)"
        case .leftOut: return library.tr("segLeftOut") + " · \(library.count(.leftOut))"
        }
    }
}

// MARK: moments

struct MomentsPanel: View {
    @EnvironmentObject var library: LibraryModel
    @State private var groups: [MomentGroup] = []
    @State private var selected: Int?
    @State private var frame = 0
    @State private var loaded = false
    @FocusState private var focused: Bool

    var current: MomentGroup? { groups.first { $0.id == selected } }
    var currentIndex: Int? { groups.firstIndex { $0.id == selected } }

    var body: some View {
        Group {
            if library.analysing && groups.isEmpty {
                AnalysisCard().frame(maxWidth: 640).frame(maxHeight: .infinity)
            } else if loaded && groups.isEmpty {
                GuideEmpty(symbol: "square.stack.3d.up.slash", title: library.tr("noMomentsTitle"), text: library.tr("noMomentsText"))
            } else {
                HStack(spacing: 16) {
                    list.frame(width: 250).frame(maxHeight: .infinity)
                    if let g = current { detail(g).frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity) } else { Spacer() }
                }
            }
        }
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(.leftArrow) { moveFrame(-1); return .handled }
        .onKeyPress(.rightArrow) { moveFrame(1); return .handled }
        .onKeyPress(.upArrow) { moveMoment(-1); return .handled }
        .onKeyPress(.downArrow) { moveMoment(1); return .handled }
        .onKeyPress(.return) { keepAndNext(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { _ in keepToo(); return .handled }
        // Also after the quick review or compare view closes: keepers picked there show here (M12d).
        .task(id: "\(library.tripId ?? "")\(library.analysing)\(library.reviewFilter == nil)") {
            if library.reviewFilter == nil { await library.writesSettled() }
            await load()
        }
    }

    var list: some View {
        ScrollViewReader { proxy in
            List(selection: Binding(get: { selected }, set: { select($0) })) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                    MomentRow(group: g, number: i + 1).tag(g.id)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(.background.secondary, in: .rect(cornerRadius: 20))
            .clipShape(.rect(cornerRadius: 20))
            .onChange(of: selected) { _, id in withMotion(.settle) { proxy.scrollTo(id) } }
        }
    }

    func detail(_ g: MomentGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: library.tr("momentOf"), (currentIndex ?? 0) + 1, groups.count)).font(.title2.weight(.bold))
                    Label(reasons(g), systemImage: g.chosenByOwner ? "hand.thumbsup.fill" : "sparkles")
                        .foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                // M12d: the moment's frames two at a time, at 100%, 1 or 2 picks (the quick review's compare view).
                Button { library.startCompare(group: g.id) } label: { Label(library.tr("compare"), systemImage: "rectangle.split.2x1") }
                    .buttonStyle(.glass).controlSize(.large).help(library.tr("compareHelp")).disabled(g.members.count < 2)
                Button(library.tr("acceptRest")) { acceptRest() }.buttonStyle(.glass).controlSize(.large)
                    .help(library.tr("acceptRestHelp"))
            }
            let frameBoxes = g.members.map { library.photo($0.id)?.faces?.boxes ?? [] }
            let keeperIndex = g.members.firstIndex { $0.id == g.keeperId } ?? 0
            // The keeper is the reference unless it shows no main face; then the frame with the most faces.
            let reference = mainFaces(frameBoxes[keeperIndex]).isEmpty
                ? (frameBoxes.indices.max { mainFaces(frameBoxes[$0]).count < mainFaces(frameBoxes[$1]).count } ?? keeperIndex)
                : keeperIndex
            let faceRows = matchFaces(frameBoxes, reference: reference)
            GeometryReader { geo in
                // Every frame of the moment is visible at once: they wrap into rows instead of
                // scrolling sideways (owner, 2026-11-16). Only extreme moments scroll down.
                frameGrid(g, faceRows: faceRows, layout: frameLayout(for: g, faceRows: faceRows.count, in: geo.size))
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .id(g.id)
            .transition(.opacity)
            Text(library.tr("momentKeys")).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
        .motionAnimation(.settle, value: g.id)
    }

    func frameGrid(_ g: MomentGroup, faceRows: [[Photo.Faces.Box?]], layout: FrameLayout) -> some View {
        let width = CGFloat(layout.frameWidth)
        let columns = Array(repeating: GridItem(.fixed(width), spacing: 16, alignment: .top), count: layout.columns)
        let members = Array(g.members.enumerated())
        return ScrollView(.vertical) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(members, id: \.element.id) { item in
                    frameCell(g, index: item.offset, member: item.element, faceRows: faceRows, width: width)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(layout.fits)
        .scrollIndicators(layout.fits ? .never : .automatic)
    }

    func frameCell(_ g: MomentGroup, index i: Int, member m: MomentGroup.Member, faceRows: [[Photo.Faces.Box?]], width: CGFloat) -> some View {
        FrameColumn(member: m, photo: library.photo(m.id), group: g, highlighted: i == frame,
                    matched: faceRows.map { $0[i] },
                    keep: { frame = i; keepAndNext() }, compact: width < 300, keepToo: { frame = i; keepToo() })
            .frame(width: width)
            .onTapGesture { frame = i; focused = true }
    }

    /// All frames on screen at once, as large as they can be (see `frameLayout` in CuratorCore).
    /// Below each photo: time and focus (about 30 points), the faces row (86), the buttons (44).
    func frameLayout(for g: MomentGroup, faceRows: Int, in size: CGSize) -> FrameLayout {
        let ratio = g.members.map { Double($0.width ?? 3) / Double(max($0.height ?? 2, 1)) }.max() ?? 1.5
        func layout(compact: Bool) -> FrameLayout {
            // Time and focus ~30, faces row (76 or 56 in narrow cells) + gap, buttons ~44 (or ~34).
            let below: Double = (faceRows > 0 ? (compact ? 66 : 86) : 0) + (compact ? 96 : 74) + 20
            return CuratorCore.frameLayout(count: g.members.count, ratio: ratio, width: size.width - 8,
                                           height: size.height - 8, below: below)
        }
        // Narrow cells need less room below the photo, which can make the photos larger.
        let wide = layout(compact: false)
        let narrow = layout(compact: true)
        return narrow.frameWidth < 300 && narrow.frameWidth > wide.frameWidth ? narrow : wide
    }

    func load() async {
        guard let trip = library.tripId else { return }
        let all = (try? await library.api.moments(trip: trip)) ?? []
        // Moments that need the owner first, then the ones decided automatically, each in time order.
        groups = all.filter { !$0.clear } + all.filter(\.clear)
        if selected == nil || !groups.contains(where: { $0.id == selected }) { select(groups.first?.id) }
        loaded = true
        if library.reviewFilter == nil { focused = true }
    }

    func select(_ id: Int?) {
        selected = id
        frame = current.map { g in g.members.firstIndex { $0.id == g.keeperId } ?? 0 } ?? 0
    }

    func moveFrame(_ d: Int) { if let g = current { frame = max(0, min(g.members.count - 1, frame + d)) } }
    func moveMoment(_ d: Int) {
        guard let i = currentIndex else { return }
        select(groups[max(0, min(groups.count - 1, i + d))].id)
    }

    /// The highlighted frame is the one for the album; on to the next moment.
    func keepAndNext() {
        guard let g = current, let i = currentIndex, g.members.indices.contains(frame) else { return }
        let chosen = g.members[frame].id
        library.keep(group: g.id, photo: chosen)
        groups[i] = updated(g, keeper: chosen)
        if i + 1 < groups.count { select(groups[i + 1].id) }
    }

    /// The highlighted frame goes to the album as well (favourite), next to the chosen one.
    func keepToo() {
        guard let g = current, g.members.indices.contains(frame) else { return }
        library.toggleKeepToo(g.members[frame].id)
    }

    func acceptRest() {
        guard let i = currentIndex else { return }
        library.acceptRest(groups[i...].map(\.id))     // undoable; the toast says so
    }

    /// The local copy shows the owner's choice at once; the engine's answer replaces it on reload.
    func updated(_ g: MomentGroup, keeper: Int) -> MomentGroup {
        let data = try? JSONSerialization.data(withJSONObject: [
            "id": g.id, "category": g.category, "keeper_id": keeper,
            "reasons": ["keeper": ["chosen by you"], "margin": g.reasons.margin ?? 0],
            "members": g.members.map { m in
                ["id": m.id, "path": m.path, "owner": m.owner ?? "", "local_time": m.localTime ?? "",
                 "width": m.width ?? 0, "height": m.height ?? 0, "rejected": m.rejected ?? false] as [String: Any]
            },
        ])
        return data.flatMap { try? JSONDecoder().decode(MomentGroup.self, from: $0) } ?? g
    }

    func reasons(_ g: MomentGroup) -> String {
        if g.chosenByOwner { return library.tr("yourChoiceLong") }
        let r = (g.reasons.keeper ?? []).filter { !$0.hasPrefix("a recommendation") }
        let text = r.map { library.trOr("why_" + $0, $0) }.joined(separator: ", ")
        return (g.clear ? library.tr("decidedBecause") : library.tr("suggestedBecause")) + " " + text
    }
}

struct MomentRow: View {
    @EnvironmentObject var library: LibraryModel
    let group: MomentGroup
    let number: Int

    var body: some View {
        let keeper = group.members.first { $0.id == group.keeperId } ?? group.members.first
        HStack(spacing: 10) {
            if let k = keeper {
                Thumbnail(url: URL(fileURLWithPath: k.path), side: 260).frame(width: 64, height: 46).clipShape(.rect(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: library.tr("momentN"), number)).font(.callout.weight(.semibold))
                Text(String((keeper?.localTime ?? "").dropFirst(11).prefix(5)) + " · " + Strings.photos(group.members.count, library.lang))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            Image(systemName: group.chosenByOwner ? "hand.thumbsup.fill" : (group.clear ? "sparkles" : "circle.fill"))
                .font(group.clear || group.chosenByOwner ? .callout : .caption2)
                .foregroundStyle(group.chosenByOwner ? StatusColor.kept : (group.clear ? .secondary : StatusColor.look))
                .help(library.tr(group.chosenByOwner ? "yourChoice" : (group.clear ? "decidedAuto" : "needsYou")))
        }
        .padding(.vertical, 3)
    }
}

/// One frame of a moment: the photo large, faces with eyes open or closed, focus, and the two choices.
struct FrameColumn: View {
    @EnvironmentObject var library: LibraryModel
    let member: MomentGroup.Member
    let photo: Photo?
    let group: MomentGroup
    let highlighted: Bool
    /// This frame's faces in the same order as in the other frames (one per person; nil: not found here).
    var matched: [Photo.Faces.Box?] = []
    let keep: () -> Void
    var compact = false                     // narrow cell: icon buttons, smaller face crops
    let keepToo: () -> Void

    var isKeeper: Bool { member.id == group.keeperId }
    var alsoKept: Bool { !isKeeper && (photo?.keep == true || photo?.favorite == true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Thumbnail(url: URL(fileURLWithPath: member.path), side: 1024, fill: false)
                .aspectRatio(CGFloat(member.width ?? 3) / CGFloat(max(member.height ?? 2, 1)), contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(alignment: .topLeading) { badge }
                .overlay {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: highlighted ? 4 : 0)
                }
                .opacity(isKeeper || alsoKept || highlighted ? 1 : 0.82)
                .scaleEffect(highlighted ? 1 : 0.985)
                .motionAnimation(.quick, value: highlighted)
                .onTapGesture(count: 2) { keep() }
            HStack(spacing: 6) {
                Text(String((member.localTime ?? "").dropFirst(11).prefix(8))).monospacedDigit().font(.callout.weight(.medium))
                Text(member.owner ?? "").foregroundStyle(.secondary).font(.callout)
                Spacer()
                if let t = photo?.focus?.tier { chip("tier_" + t, warn: t != "sharp") }
            }
            if !matched.isEmpty {
                HStack(spacing: 10) {
                    ForEach(matched.indices, id: \.self) { r in
                        if let b = matched[r] {
                            FaceCrop(url: URL(fileURLWithPath: member.path), box: b, size: compact ? 56 : 76)
                        } else {
                            Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .frame(width: compact ? 56 : 76, height: compact ? 56 : 76)
                                .overlay { Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(.tertiary) }
                                .help(library.tr("faceNotFound"))
                        }
                    }
                }
            } else if let f = photo?.faces {
                HStack(spacing: 6) {
                    chip(f.eyesClosed > 0 ? "eyesClosed" : "eyesOpen", warn: f.eyesClosed > 0)
                    chip(f.lookingAway > 0 ? "lookingAway" : "lookingAtCamera", warn: f.lookingAway > 0)
                }
            }
            // Full labels when they fit; in narrow cells the same buttons with icons only (help shows the text).
            // Side by side when they fit; in narrow cells one under the other, still with words.
            ViewThatFits(in: .horizontal) {
                buttons(iconsOnly: false, stacked: false)
                buttons(iconsOnly: false, stacked: true)
                buttons(iconsOnly: true, stacked: false)
            }
            .controlSize(compact ? .regular : .large)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    func buttons(iconsOnly: Bool, stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button(action: keep) {
                Label(library.tr(isKeeper ? "chosenForAlbum" : "keepThisOne"), systemImage: isKeeper ? "checkmark.circle.fill" : "circle")
                    .labelStyle(iconsOnly ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .buttonStyle(.glass).tint(isKeeper ? .green : nil)
            .disabled(isKeeper)
            .help(library.tr(isKeeper ? "chosenForAlbum" : "keepThisOne"))
            if !isKeeper {
                Button(action: keepToo) {
                    Label(library.tr(alsoKept ? "keptToo" : "keepToo"), systemImage: alsoKept ? "plus.circle.fill" : "plus.circle")
                        .labelStyle(iconsOnly ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                }
                .buttonStyle(.glass).tint(alsoKept ? .green : nil)
                .help(library.tr("keepTooHelp"))
            }
        }
        .fixedSize()
    }

    @ViewBuilder var badge: some View {
        if isKeeper {
            Label(library.tr(group.chosenByOwner ? "yourChoice" : "recommended"), systemImage: group.chosenByOwner ? "hand.thumbsup" : "sparkles")
                .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(.regularMaterial, in: .capsule).padding(8)
        } else if alsoKept {
            Label(library.tr("alsoInAlbum"), systemImage: "heart.fill")
                .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(.regularMaterial, in: .capsule).foregroundStyle(.pink).padding(8)
        }
    }

    func chip(_ key: String, warn: Bool) -> some View {
        Text(library.tr(key)).font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((warn ? StatusColor.warning : StatusColor.kept).opacity(0.18), in: .capsule)
            .foregroundStyle(warn ? StatusColor.lookText : StatusColor.keptText)
    }
}

// MARK: blurry and left out

/// A grid where one click keeps a photo or leaves it out.
struct ToggleGrid: View {
    @EnvironmentObject var library: LibraryModel
    enum Kind { case blurry, leftOut }
    let kind: Kind
    @State private var ids: [Int] = []

    var items: [Photo] { ids.compactMap(library.photo) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(library.tr(kind == .blurry ? "blurryLead" : "leftOutLead")).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if kind == .blurry && !ids.isEmpty {
                    Button(library.tr("keepAll")) { library.setBlurryInAlbum(ids, true) }.buttonStyle(.glass)
                    Button(library.tr("leaveOutAll")) { library.setBlurryInAlbum(ids, false) }.buttonStyle(.glass)
                }
            }
            if ids.isEmpty {
                GuideEmpty(symbol: kind == .blurry ? "camera.aperture" : "eye.slash",
                           title: library.tr(kind == .blurry ? "noBlurryTitle" : "noLeftOutTitle"),
                           text: library.tr(kind == .blurry ? "noBlurryText" : "noLeftOutText"))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(items) { p in
                            // In the album = what the export takes (a blurry photo needs the owner's keep).
                            let inAlbum = kind == .blurry ? p.goesToAlbumDespiteFocus : !p.rejected
                            Button {
                                if kind == .blurry { library.setBlurryInAlbum([p.id], !inAlbum) } else { library.setLeftOut([p.id], inAlbum) }
                            } label: {
                                PhotoCover(photo: p, side: 520, radius: 14)
                                    .frame(height: 150)
                                    .opacity(inAlbum ? 1 : 0.45)
                                    .saturation(inAlbum ? 1 : 0.2)
                                    .overlay(alignment: .bottomTrailing) {
                                        Label(library.tr(inAlbum ? "inAlbum" : "notInAlbum"),
                                              systemImage: inAlbum ? "checkmark.circle.fill" : "eye.slash.fill")
                                            .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(.regularMaterial, in: .capsule)
                                            .foregroundStyle(inAlbum ? Color.green : Color.secondary).padding(8)
                                    }
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help(library.tr(inAlbum ? "clickToLeaveOut" : "clickToKeep"))
                            .motionAnimation(.quick, value: inAlbum)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
        // The list is fixed when the view opens, so a photo does not vanish under the pointer when clicked.
        .onAppear { refresh() }
        .onChange(of: library.loadedTripId) { _, _ in refresh() }
    }

    func refresh() {
        switch kind {
        case .blurry: ids = library.photos.filter(\.foundBlurry).map(\.id)
        case .leftOut: ids = library.photos.filter(\.rejected).map(\.id)
        }
    }
}

/// Lets one button switch between full and icon-only labels.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
