import CuratorCore
import SwiftUI

/// Step 2: the best of each moment, blurry photos, and what was left out. Nothing is deleted;
/// left-out photos only stay out of the export.
struct StepSelection: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        StepPage(step: .selection, lead: library.tr("lead_selection"), status: status, scrolls: false) {
            VStack(spacing: 16) {
                Picker("", selection: $library.selectionView) {
                    ForEach(SelectionView.allCases) { v in Text(label(v)).tag(v) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 560)
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
        .task(id: "\(library.tripId ?? "")\(library.analysing)") { await load() }
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
            .onChange(of: selected) { _, id in withAnimation { proxy.scrollTo(id) } }
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
                Button(library.tr("acceptRest")) { acceptRest() }.buttonStyle(.glass).controlSize(.large)
                    .help(library.tr("acceptRestHelp"))
            }
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(g.members.enumerated()), id: \.element.id) { i, m in
                            FrameColumn(member: m, photo: library.photo(m.id), group: g, highlighted: i == frame,
                                        keep: { frame = i; keepAndNext() }, keepToo: { frame = i; keepToo() })
                                .frame(width: frameWidth(g, geo.size))
                                .onTapGesture { frame = i; focused = true }
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(g.members.count > 3 ? .automatic : .never)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .id(g.id)
            .transition(.opacity)
            Text(library.tr("momentKeys")).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
        .animation(.snappy(duration: 0.25), value: g.id)
    }

    /// Up to three frames share the width; more scroll sideways. The photo also has to fit the height
    /// left for it (time, faces and buttons take about 150 points below it).
    func frameWidth(_ g: MomentGroup, _ size: CGSize) -> CGFloat {
        let n = CGFloat(min(3, max(1, g.members.count)))
        let byWidth = (size.width - 8 - 16 * (n - 1)) / n
        let ratio = g.members.map { CGFloat($0.width ?? 3) / CGFloat(max($0.height ?? 2, 1)) }.max() ?? 1.5
        let byHeight = max(120, size.height - 160) * ratio
        return max(220, min(byWidth, byHeight))
    }

    func load() async {
        guard let trip = library.tripId else { return }
        let all = (try? await library.api.moments(trip: trip)) ?? []
        // Moments that need the owner first, then the ones decided automatically, each in time order.
        groups = all.filter { !$0.clear } + all.filter(\.clear)
        if selected == nil || !groups.contains(where: { $0.id == selected }) { select(groups.first?.id) }
        loaded = true
        focused = true
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
        groups[i...].forEach { library.reviewedMoments.insert($0.id) }
        library.markStep("duplicates")
        library.message = library.tr("acceptedRest")
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
                .foregroundStyle(group.chosenByOwner ? .green : (group.clear ? .secondary : .orange))
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
    let keep: () -> Void
    let keepToo: () -> Void

    var isKeeper: Bool { member.id == group.keeperId }
    var alsoKept: Bool { !isKeeper && photo?.favorite == true }

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
                .animation(.snappy(duration: 0.2), value: highlighted)
                .onTapGesture(count: 2) { keep() }
            HStack(spacing: 6) {
                Text(String((member.localTime ?? "").dropFirst(11).prefix(8))).monospacedDigit().font(.callout.weight(.medium))
                Text(member.owner ?? "").foregroundStyle(.secondary).font(.callout)
                Spacer()
                if let t = photo?.focus?.tier { chip("tier_" + t, warn: t != "sharp") }
            }
            if let boxes = photo?.faces?.boxes, !boxes.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(boxes.prefix(4).enumerated()), id: \.offset) { _, b in
                        FaceCrop(url: URL(fileURLWithPath: member.path), box: b, size: 54)
                    }
                    if boxes.count > 4 { Text("+\(boxes.count - 4)").font(.callout).foregroundStyle(.secondary) }
                }
            } else if let f = photo?.faces {
                HStack(spacing: 6) {
                    chip(f.eyesClosed > 0 ? "eyesClosed" : "eyesOpen", warn: f.eyesClosed > 0)
                    chip(f.lookingAway > 0 ? "lookingAway" : "lookingAtCamera", warn: f.lookingAway > 0)
                }
            }
            HStack(spacing: 8) {
                Button(action: keep) {
                    Label(library.tr(isKeeper ? "chosenForAlbum" : "keepThisOne"), systemImage: isKeeper ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.glass).tint(isKeeper ? .green : nil)
                .disabled(isKeeper)
                if !isKeeper {
                    Button(action: keepToo) {
                        Label(library.tr(alsoKept ? "keptToo" : "keepToo"), systemImage: alsoKept ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.glass).tint(alsoKept ? .pink : nil)
                    .help(library.tr("keepTooHelp"))
                }
            }
            .controlSize(.large)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
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
            .background((warn ? Color.orange : Color.green).opacity(0.18), in: .capsule)
            .foregroundStyle(warn ? .orange : .green)
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
                            .animation(.snappy(duration: 0.2), value: inAlbum)
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
