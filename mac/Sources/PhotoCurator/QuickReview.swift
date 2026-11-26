import CuratorCore
import SwiftUI

/// Quick review (M10): the album one photo at a time, full window. → keeps, ← leaves out, ⌫ or ⌘Z goes back
/// and undoes, Space skips, F favourite, Z toggles 100% on the subject, E shows the faces large, C compares the
/// frames of a moment, ? the keys. Every key comes from `ReviewKeymap` (M12d); keys it does not know pass
/// through (VoiceOver, menus). Every decision is written at once; nothing is ever deleted.
struct QuickReviewView: View {
    @EnvironmentObject var library: LibraryModel
    @State var filter: ReviewFilter
    @State private var session = ReviewSession(queue: [])
    @State private var started = false
    @State private var zoom = false
    @State private var showFaces = false
    @State private var showKeys = false
    @State private var flash: ReviewAction?
    @State private var flashTask: Task<Void, Never>?
    /// The last decision, for the direction the photo leaves in (none with Reduce Motion: a cross-fade).
    @State private var lastAction: ReviewAction?
    /// What is in the middle of the view at 100% (unit coordinates); shared by both panes of the compare view.
    @State private var zoomCentre = ZoomPoint.centre
    /// Compare mode (M12d): two frames of a moment side by side.
    @State private var compare: CompareSession?
    /// Compare was opened from Selection: leaving it closes the review too.
    @State private var compareOnly = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The session goes through a chosen subset (e.g. the skipped photos), not the filter's whole queue.
    @State private var subset = false
    @FocusState private var focused: Bool

    var photo: Photo? { session.current.flatMap(library.photo) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if let c = compare {
                    CompareView(session: c, zoomed: zoom, centre: $zoomCentre, pick: pickInCompare,
                                toggleZoom: toggleZoom, showKeys: { showKeys.toggle() }, close: closeCompare)
                        .padding(.horizontal, Space.xxl).padding(.vertical, Space.l)
                } else {
                    topBar.padding(.horizontal, 22).padding(.top, 14)
                    if session.finished && started {
                        EndCard(session: session, filter: filter, again: { f, ids in begin(f, ids: ids) }, close: close)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let p = photo {
                        HStack(alignment: .top, spacing: 0) {
                            stage(p).frame(maxWidth: .infinity, maxHeight: .infinity)
                            if let siblings = momentFrames(p), siblings.count > 1 {
                                // The same people in every frame of this moment, enlarged, next to each other.
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: Space.m) {
                                        Text(String(format: library.tr("compareFrames"), siblings.count))
                                            .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                        Button { openCompare() } label: {
                                            Label(library.tr("compare") + "  C", systemImage: "rectangle.split.2x1")
                                        }
                                        .buttonStyle(.glass).help(library.tr("compareHelp"))
                                    }
                                    ScrollView([.vertical, .horizontal]) {
                                        FaceComparison(frames: siblings, current: p.id, faceSize: showFaces ? 132 : 104) { f in jump(to: f.id) }
                                    }
                                    .scrollIndicators(.never)
                                }
                                .padding(16)
                                .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
                                .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
                                .padding(.trailing, 22).padding(.vertical, 6)
                            }
                        }
                        bottom(p).padding(.horizontal, 22).padding(.bottom, 18)
                    } else if started {
                        GuideEmpty(symbol: "checkmark.circle", title: library.tr("reviewNothing"), text: library.tr("reviewNothingText"))
                            .foregroundStyle(.white).frame(maxHeight: .infinity)
                    }
                }
            }
            if showKeys { KeysCard(context: compare == nil ? .single : .compare) { showKeys = false } }
        }
        .stageDarkSurface()
        .focusable().focusEffectDisabled().focused($focused)
        // One decision per press: only the down phase, so a held key does not repeat (it would decide photos the
        // owner never saw). Keys the keymap does not know are .ignored and reach VoiceOver and the menus.
        .onKeyPress(phases: .down) { press in handle(press) }
        .onAppear {
            begin(filter, ids: library.takeReviewSubset()); focused = true
            openRequestedCompare()
        }
        .onChange(of: library.compareRequest) { _, _ in openRequestedCompare() }
        .onChange(of: library.reviewUndoRequest) { _, _ in if compare == nil { back() } }
        // Zoom never sticks: a new photo, focus moving away or the app going to the background resets it (#19).
        .onChange(of: session.current) { _, _ in zoom = false }
        .onChange(of: focused) { _, f in if !f { zoom = false } }
        .onChange(of: scenePhase) { _, _ in zoom = false }
        .onChange(of: library.automationKeyTick) { _, _ in
            let k: ReviewKey? = switch library.automationKey {
            case "right": ReviewKey.right
            case "left": ReviewKey.left
            case "back": ReviewKey.delete
            case "skip": ReviewKey.space
            case "esc": ReviewKey.escape
            case "favourite": ReviewKey.character("f")
            case "faces": ReviewKey.character("e")
            case "keys": ReviewKey.character("?")
            case "compare": ReviewKey.character("c")
            case "pick1": ReviewKey.character("1")
            case "pick2": ReviewKey.character("2")
            default: nil
            }
            if library.automationKey == "zoom" && !zoom { toggleZoom() }
            if library.automationKey == "unzoom" { zoom = false }
            if let k, let cmd = ReviewKeymap.command(for: k, in: compare == nil ? .single : .compare) { perform(cmd) }
        }
        // Another album: the ids mean something else. Close without touching any bookmark.
        .onChange(of: library.loadedTripId) { _, _ in library.reviewFilter = nil }
        .onChange(of: library.reviewFilter) { _, f in if let f, f != filter { begin(f, ids: nil) } }
    }

    // MARK: layout

    var topBar: some View {
        HStack(spacing: 14) {
            Button { close() } label: { Label(library.tr("done"), systemImage: "xmark") }
                .buttonStyle(.glass)      // Escape is handled by the view: it closes the keys card first
            Picker("", selection: Binding(get: { filter }, set: { begin($0, ids: nil) })) {
                ForEach(ReviewFilter.allCases) { f in Text(library.tr("review_" + f.rawValue)).tag(f) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 360)
            Spacer()
            let c = session.counts
            HStack(spacing: 14) {
                Label("\(c.kept)", systemImage: "checkmark.circle.fill").foregroundStyle(StatusColor.kept)
                Label("\(c.leftOut)", systemImage: "xmark.circle.fill").foregroundStyle(.secondary)
                if c.skipped > 0 { Label("\(c.skipped)", systemImage: "forward.fill").foregroundStyle(StatusColor.look) }
            }
            .font(.callout.weight(.semibold)).monospacedDigit()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(min(session.index + 1, session.queue.count)) / \(session.queue.count)")
                    .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
                if filter == .decisions && !subset {
                    let inQueue = Set(session.queue)
                    Text(String(format: library.tr("reviewRestStays"),
                                library.photos.filter { !inQueue.contains($0.id) && $0.goesToAlbumDespiteFocus }.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { showKeys.toggle() } label: { Image(systemName: "keyboard") }
                .buttonStyle(.glass).help(library.tr("reviewKeys"))
        }
        .overlay(alignment: .bottom) {
            GeometryReader { g in
                Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.8))
                            .frame(width: g.size.width * CGFloat(session.index) / CGFloat(max(1, session.queue.count)), height: 3)
                    }
            }
            .frame(height: 3).offset(y: 12)
        }
        .padding(.bottom, 14)
    }

    func stage(_ p: Photo) -> some View {
        // 100% of the original when zoomed (M12d), the whole photo otherwise; drag pans at 100%.
        ZoomablePhoto(url: p.fileURL, ratio: Double(p.width ?? 3) / Double(max(p.height ?? 2, 1)), pixelWidth: p.width,
                      zoomed: zoom && !p.isVideo, centre: $zoomCentre)
            .overlay {
                // The decision flashes on the photo: green for keep, grey for leave out.
                if let flash {
                    Image(systemName: flash == .keep ? "checkmark.circle.fill" : (flash == .leaveOut ? "xmark.circle.fill" : "forward.fill"))
                        .font(.system(size: 96, weight: .semibold))
                        .foregroundStyle(flash == .keep ? StatusColor.kept : (flash == .leaveOut ? Color.white.opacity(0.7) : StatusColor.look))
                        .shadow(radius: 20)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            // VoiceOver (#9): who and what is shown, zoom and the last decision as the value, the review's actions.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gridTileAccessibilityLabel(p, library.lang))
            .accessibilityValue(reviewAccessibilityValue(zoomed: zoom && !p.isVideo, flash: flash, library.lang))
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: Text(library.tr("reviewYes"))) { decide(.keep) }
            .accessibilityAction(named: Text(library.tr("reviewNo"))) { decide(.leaveOut) }
            .accessibilityAction(named: Text(library.tr("skip"))) { decide(.skip) }
            .accessibilityAction(named: Text(library.tr("back"))) { back() }
            .accessibilityAction(named: Text(library.tr(zoom ? "a11yZoomFit" : "zoomToggle"))) { toggleZoom() }
            .accessibilityAction(named: Text(library.tr("compare"))) { openCompare() }
            .id(p.id)
            .transition(photoTransition)
        .padding(.horizontal, 22).padding(.vertical, 6)
        .overlay(alignment: .topTrailing) {
            if showFaces, let boxes = mainFaces(p), !boxes.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(boxes.enumerated()), id: \.offset) { _, b in
                        FaceCrop(url: p.fileURL, box: b, size: 120)
                    }
                }
                .padding(14).background(.ultraThinMaterial, in: .rect(cornerRadius: 18)).padding(30)
            }
        }
    }

    func bottom(_ p: Photo) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                let inAlbum = p.goesToAlbumDespiteFocus
                Label(library.tr(inAlbum ? "inAlbum" : "notInAlbum"), systemImage: inAlbum ? "checkmark.circle.fill" : "eye.slash.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((inAlbum ? StatusColor.kept : Color.gray).opacity(0.25), in: .capsule)
                    .foregroundStyle(inAlbum ? StatusColor.kept : .white)
                ForEach(reviewReasons(p), id: \.self) { r in
                    Label(reasonText(r, p), systemImage: reasonIcon(r))
                        .font(.callout).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(StatusColor.look.opacity(0.22), in: .capsule).foregroundStyle(StatusColor.look)
                }
                if p.favorite { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                Spacer()
                Text("\(p.clock) · \(p.owner)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button { decide(.leaveOut) } label: {
                        Label(library.tr("reviewNo"), systemImage: "arrow.left").frame(minWidth: 150)
                    }
                    .buttonStyle(.glass).controlSize(.extraLarge)
                    Button { back() } label: { Label(library.tr("back"), systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.glass).controlSize(.extraLarge).disabled(!session.canGoBack)
                    Button { decide(.skip) } label: { Label(library.tr("skip"), systemImage: "forward") }
                        .buttonStyle(.glass).controlSize(.extraLarge)
                    Button { decide(.keep) } label: {
                        Label(library.tr("reviewYes"), systemImage: "arrow.right").labelStyle(TrailingIconLabel()).frame(minWidth: 150)
                    }
                    .buttonStyle(.glassProminent).tint(StatusColor.kept).controlSize(.extraLarge)
                }
            }
        }
    }

    // MARK: actions

    func begin(_ f: ReviewFilter, ids: [Int]?) {
        filter = f
        let queue = ids ?? reviewQueue(library.photos, filter: f)
        subset = ids != nil
        let start = ids == nil ? library.reviewBookmark(f) : nil
        session = ReviewSession(queue: queue, startAt: start)
        started = true
        focused = true
    }

    func decide(_ action: ReviewAction) {
        guard let p = photo, !showKeys else { return }
        let previous = action == .skip ? [:] : library.marksOf(p.id)
        switch action {
        case .keep: library.setInAlbum([p.id], true)
        case .leaveOut: library.setInAlbum([p.id], false)
        case .skip: break
        }
        // The decision is recorded and the next photo shown at once, so fast or held keys never land twice on
        // the same photo or skip one; the flash is only a short visual confirmation.
        let position = session.index + 1, total = session.queue.count
        withMotion(.quick, reduceMotion: reduceMotion) {
            lastAction = action
            session.record(action, previous: previous)
            zoom = false
            flash = action
        }
        AccessibilityNotification.Announcement(reviewAnnouncement(action, position: position, total: total, library.lang)).post()
        library.setReviewBookmark(filter, session.current)
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .milliseconds(260))
            if !Task.isCancelled { withMotion(.fade, reduceMotion: reduceMotion) { flash = nil } }
        }
    }

    func back() {
        guard let e = session.back() else { return }
        if e.action != .skip { library.restore(e.photoId, e.previous) }
        library.setReviewBookmark(filter, session.current)
        flash = nil; lastAction = nil; zoom = false
        let name = library.photo(e.photoId)?.filename ?? ""
        AccessibilityNotification.Announcement(String(format: library.tr("a11yBackUndone"), name)).post()
    }

    func favourite() { if let p = photo { library.toggleFavourite(p.id) } }

    /// Click a frame in the comparison: show that frame (no decision is recorded for the one left).
    func jump(to id: Int) {
        guard session.queue.contains(id) else { return }
        session.jump(to: id)
        library.setReviewBookmark(filter, session.current)
    }

    func close() {
        if session.finished { library.setReviewBookmark(filter, nil) }
        library.reviewFilter = nil
    }

    // MARK: keys, zoom and compare (M12d)

    /// One key press through the keymap. Not the review's key: .ignored, so it reaches VoiceOver and the menus.
    func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let key = reviewKey(press) else { return .ignored }
        var mods: ReviewKeyModifiers = []
        if press.modifiers.contains(.shift) { mods.insert(.shift) }
        if press.modifiers.contains(.command) { mods.insert(.command) }
        if press.modifiers.contains(.option) { mods.insert(.option) }
        if press.modifiers.contains(.control) { mods.insert(.control) }
        guard let cmd = ReviewKeymap.command(for: key, modifiers: mods, in: compare == nil ? .single : .compare) else {
            return .ignored
        }
        perform(cmd)
        return .handled
    }

    func reviewKey(_ press: KeyPress) -> ReviewKey? {
        let k = press.key
        if k == .rightArrow { return .right }
        if k == .leftArrow { return .left }
        if k == .upArrow { return .up }
        if k == .downArrow { return .down }
        if k == .space { return .space }
        if k == .escape { return .escape }
        if k == .return { return .returnKey }
        if k == .delete || k == .deleteForward || press.characters == "\u{8}" || press.characters == "\u{7F}" { return .delete }
        return press.characters.isEmpty ? nil : .character(press.characters)
    }

    func perform(_ cmd: ReviewCommand) {
        // With the keys card open only ? and esc work (no decision on a photo behind the card).
        if showKeys && cmd != .keys && cmd != .close { return }
        switch cmd {
        case .keep: decide(.keep)
        case .leaveOut: decide(.leaveOut)
        case .skip: decide(.skip)
        case .back: back()
        case .favourite: favourite()
        case .faces: showFaces.toggle()
        case .zoom: toggleZoom()
        case .compare: openCompare()
        case .keys: showKeys.toggle()
        case .close:
            if showKeys { showKeys = false } else if compare != nil { closeCompare() } else { close() }
        case .pickFirst: pickInCompare(1)
        case .pickSecond: pickInCompare(2)
        case .nextChallenger: compare?.next()
        case .previousChallenger: compare?.previous()
        }
    }

    /// Z: 100% of the original on the main face (or the centre), or back to the whole photo.
    func toggleZoom() {
        if zoom { zoom = false; return }
        let target: Photo?
        if let c = compare { target = library.photo(c.keeper) } else { target = photo }
        guard let p = target, !p.isVideo else { return }
        zoomCentre = ZoomMath.target(faces: p.faces?.boxes)
        zoom = true
    }

    /// Opens the compare view for the current photo's moment (the current frame on the right), or for `group`.
    @discardableResult
    func openCompare(group: Int? = nil) -> Bool {
        let current = group == nil ? photo : nil
        let frames: [Photo]
        if let group {
            frames = library.photos.filter { $0.duplicate?.group == group && !$0.isVideo }
        } else if let p = current, let siblings = momentFrames(p) {
            frames = siblings.filter { !$0.isVideo }
        } else {
            frames = []
        }
        guard frames.count > 1 else { return false }
        let keeper = frames.first { $0.duplicate?.keeper == true }?.id
        compare = CompareSession(frames: frames.map(\.id), keeper: keeper, challenger: current?.id)
        zoom = false
        showFaces = false
        return true
    }

    /// Selection asked for a moment's compare view.
    func openRequestedCompare() {
        guard let g = library.compareRequest else { return }
        library.compareRequest = nil
        compareOnly = true
        if !openCompare(group: g) { compareOnly = false; library.reviewFilter = nil }
    }

    /// 1 or 2: that frame is the one for the album, through the same call as Selection's "Keep This One".
    func pickInCompare(_ side: Int) {
        guard var c = compare, let group = library.photo(c.keeper)?.duplicate?.group else { return }
        guard let keeper = c.pick(side) else { return }
        withMotion(.fade, reduceMotion: reduceMotion) { compare = c }
        library.keep(group: group, photo: keeper)
        let name = library.photo(keeper)?.filename ?? ""
        AccessibilityNotification.Announcement(String(format: library.tr("a11yKeeperPicked"), name)).post()
    }

    func closeCompare() {
        compare = nil
        zoom = false
        if compareOnly { compareOnly = false; library.reviewFilter = nil }
        focused = true
    }

    /// The photo leaves in the direction of its key (→ keep, ← leave out); with Reduce Motion, or for a skip or
    /// Back, it cross-fades.
    var photoTransition: AnyTransition {
        guard !reduceMotion, let a = lastAction, a != .skip else { return .opacity }
        let removal = AnyTransition.opacity.combined(with: .offset(x: a == .keep ? Space.huge : -Space.huge))
        return .asymmetric(insertion: .opacity, removal: removal)
    }

    // MARK: helpers

    func mainFaces(_ p: Photo) -> [Photo.Faces.Box]? {
        guard let boxes = p.faces?.boxes else { return nil }
        let main = boxes.filter { $0.main != false }
        return Array((main.isEmpty ? boxes : main).prefix(4))
    }

    func momentFrames(_ p: Photo) -> [Photo]? {
        guard let g = p.duplicate?.group, ["exact", "near"].contains(p.duplicate?.category ?? "") else { return nil }
        return library.photos.filter { $0.duplicate?.group == g }
    }

    func reasonText(_ code: String, _ p: Photo) -> String { library.trCode("why2_", code, other: "reason_other") }

    func reasonIcon(_ code: String) -> String {
        switch code {
        case "eyes_closed": "eye.slash"
        case "eyes_unsure": "eye.trianglebadge.exclamationmark"
        case "subject_blurry", "whole_blurry": "camera.aperture"
        case "movement_blur": "figure.walk.motion"
        case "utility_image": "doc.text.viewfinder"
        case "extra_frame": "square.stack.3d.up"
        default: "exclamationmark.circle"
        }
    }
}

/// The end of a review: what was decided, and what to do next.
struct EndCard: View {
    @EnvironmentObject var library: LibraryModel
    let session: ReviewSession
    let filter: ReviewFilter
    let again: (ReviewFilter, [Int]?) -> Void
    let close: () -> Void

    var body: some View {
        let c = session.counts
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green.gradient)
            Text(library.tr("reviewDone")).scaledFont(30, weight: .bold, relativeTo: .title).foregroundStyle(.white)
            Text(String(format: library.tr("reviewCounts"), c.kept, c.leftOut, c.skipped)).font(.title3).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if !session.skippedIds.isEmpty {
                    Button(library.tr("reviewSkipped")) { again(filter, session.skippedIds) }.buttonStyle(.glass).controlSize(.extraLarge)
                }
                Button(library.tr("reviewLeftOut")) { again(.leftOut, nil) }.buttonStyle(.glass).controlSize(.extraLarge)
                Button(library.tr("goToStory")) { close(); library.destination = .step(.story) }
                    .buttonStyle(.glassProminent).controlSize(.extraLarge)
            }
        }
    }
}

/// Every key of the quick review on one card.
struct KeysCard: View {
    @EnvironmentObject var library: LibraryModel
    var context: ReviewContext = .single
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(library.tr("reviewKeys")).font(.title2.weight(.bold))
            // The same table the keys are handled with (`ReviewKeymap`), so the card can't drift.
            ForEach(ReviewKeymap.entries(context), id: \.textKey) { e in
                HStack {
                    Text(e.keys).font(.system(.body, design: .rounded).weight(.semibold)).frame(width: 80, alignment: .leading)
                    Text(library.tr(e.textKey)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Button(library.tr("done"), action: close).buttonStyle(.glassProminent).padding(.top, 6)
        }
        .padding(26)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .frame(maxWidth: 440)
    }
}
