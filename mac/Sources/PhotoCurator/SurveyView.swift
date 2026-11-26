import AppKit
import CuratorCore
import SwiftUI

// M14c: Survey, the default way to decide a moment. Every frame side by side at equal height (more than six: a
// filmstrip with the focused frame larger), the recommended one pre-selected with "Best", reason chips and the
// faces lined up per person under every frame. 1–9 / click pick, ⇧ adds, Return confirms, A accepts, Z zooms all
// frames together. State and rules: `SurveySession` (CuratorCore/Survey.swift); keys: `ReviewKeymap` (.survey).
// Writes: `LibraryModel.applySurvey` / `undoSurvey`. Motion never delays a key: the state changes at once and the
// leaving moment is drawn by a separate, non-interactive layer that clears itself after `motionBudget`.

/// The frames of a confirmed moment, drawn once more while keepers lift and the others drop.
struct SurveyDeparture: Equatable {
    let token = UUID()
    let frames: [Int]
    let keepers: Set<Int>
}

struct SurveyView: View {
    @EnvironmentObject var library: LibraryModel
    /// The survey is over: `finished` when every moment went through, false when it was stopped (Esc).
    let onEnd: (_ finished: Bool) -> Void
    /// Photos the single review goes through afterwards (completion copy).
    let singlesNext: Int
    let standalone: Bool

    @State private var session: SurveySession
    @State private var zoom = false
    /// Space held: 100% until it is released (or focus / the moment / the app's state changes, so a lost key-up
    /// never leaves the zoom stuck).
    @State private var holdZoom = false
    @State private var centre = ZoomPoint.centre
    @State private var showKeys = false
    @State private var showCoach = SurveyCoach.shouldShow(seen: UserDefaults.standard.bool(forKey: SurveyCoach.seenKey))
    @State private var departure: SurveyDeparture?
    @State private var forward = true
    @State private var completionTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(request: SurveyRequest, singlesNext: Int, onEnd: @escaping (Bool) -> Void) {
        self.onEnd = onEnd
        self.singlesNext = singlesNext
        self.standalone = request.standalone
        _session = State(initialValue: SurveySession(moments: request.moments, ordered: request.ordered))
    }

    var zoomed: Bool { zoom || holdZoom }

    var body: some View {
        VStack(spacing: Space.l) {
            header
            if let m = session.current {
                stage(m).frame(maxWidth: .infinity, maxHeight: .infinity)
                footer(m)
            } else {
                completion.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ShortcutBar(context: .survey)
        }
        .padding(.horizontal, Space.xxl).padding(.vertical, Space.l)
        .overlay { if showCoach { coach } }
        .overlay { if showKeys { KeysCard(context: .survey) { showKeys = false } } }
        .focusable().focusEffectDisabled().focused($focused)
        // Down for every key; up only matters for Space (hold to zoom). Repeats are not handled, so a held key never
        // decides moments the owner did not see.
        .onKeyPress(phases: [.down, .up]) { press in handle(press) }
        .onAppear { focused = true; momentChanged() }
        .onDisappear { completionTask?.cancel() }
        .onChange(of: session.current?.id) { _, _ in momentChanged() }
        .onChange(of: session.focus) { _, _ in if zoomed { centreOnFace() } }
        .onChange(of: focused) { _, f in if !f { holdZoom = false } }
        .onChange(of: scenePhase) { _, _ in holdZoom = false }
        .onChange(of: library.reviewUndoRequest) { _, _ in back() }
        .onChange(of: library.automationKeyTick) { _, _ in automationKey() }
    }

    // MARK: layout

    var header: some View {
        HStack(alignment: .center, spacing: Space.l) {
            Button { end(false) } label: { Label(library.tr("done"), systemImage: "xmark") }
                .buttonStyle(.glass)
            SurveyProgressRing(progress: session.progress)
                .frame(width: Space.xxxl, height: Space.xxxl)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.m) {
                    let pos = session.position
                    Text(String(format: library.tr("surveyMoment"), pos.number, pos.count))
                        .font(TypeRole.sectionTitle).monospacedDigit().foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(pos.number)))
                        .motionAnimation(.settle, value: pos.number)
                    if let m = session.current { confidence(m) }
                }
                if let m = session.current, let why = whyText(m) {
                    Text(why).font(TypeRole.supporting).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button { toggleZoom() } label: {
                Label(library.tr(zoomed ? "a11yZoomFit" : "zoomToggle"),
                      systemImage: zoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
            }
            .buttonStyle(.glass).help(library.tr("keyZoomSurvey") + " (Z)")
            .disabled(session.current == nil)
            Button { showKeys.toggle() } label: { Image(systemName: "keyboard") }
                .buttonStyle(.glass).help(library.tr("reviewKeys"))
                .accessibilityLabel(library.tr("reviewKeys"))
        }
    }

    @ViewBuilder
    func confidence(_ m: SurveyMoment) -> some View {
        if m.isCloseCall {
            Label(library.tr("surveyCloseCall"), systemImage: "scalemass")
                .font(TypeRole.label.weight(.semibold))
                .padding(.horizontal, Space.m).padding(.vertical, Space.xxs)
                .background(StatusColor.look, in: .capsule)
                .foregroundStyle(StatusColor.onLook)
                .help(library.tr("surveyCloseCallHelp"))
        } else if let c = m.confidence {
            Text(library.tr(c.textKey))
                .font(TypeRole.label)
                .padding(.horizontal, Space.m).padding(.vertical, Space.xxs)
                .background(.ultraThinMaterial, in: .capsule)
                .foregroundStyle(.secondary)
        }
    }

    /// "Frame 2 is the best: sharpest frame, eyes open on all faces": the engine's reasons, else the best frame's
    /// positive chips.
    func whyText(_ m: SurveyMoment) -> String? {
        guard let rec = m.recommended, let n = m.frames.firstIndex(of: rec) else { return nil }
        var parts = m.reasons.map { library.trCode("why_", $0, other: "reason_other") }
        if parts.isEmpty, let p = library.photo(rec) {
            parts = surveyChips(p).filter(\.positive).map { library.tr($0.textKey) }
        }
        guard !parts.isEmpty else { return nil }
        return String(format: library.tr("surveyWhy"), n + 1, parts.joined(separator: ", "))
    }

    func faces(_ m: SurveyMoment) -> SurveyFaces {
        let boxes = m.frames.map { library.photo($0)?.faces?.boxes ?? [] }
        return SurveyFaces(frames: boxes, preferred: m.recommended.flatMap { m.frames.firstIndex(of: $0) } ?? 0)
    }

    /// Points under each photo: the chips row, and the face strip when the moment has faces.
    func below(people: Int) -> Double {
        Double(Space.s + SurveyFrame.chipHeight + (people > 0 ? Space.s + SurveyFrame.maxFace : 0))
    }

    func stage(_ m: SurveyMoment) -> some View {
        let photos = m.frames.compactMap { library.photo($0) }
        let f = faces(m)
        let ratios = photos.map(SurveyFrame.ratio)
        return GeometryReader { g in
            let layout = surveyLayout(ratios: ratios, width: Double(g.size.width), height: Double(g.size.height),
                                      below: below(people: f.people), spacing: Double(Space.l))
            ZStack(alignment: .top) {
                row(m, photos: photos, faces: f, layout: layout)
                    .id(m.id)
                    .motionTransition(.asymmetric(
                        insertion: .offset(x: forward ? Space.giant * 2 : -Space.giant * 2).combined(with: .opacity),
                        removal: .identity))
                if let d = departure, !layout.filmstrip {
                    SurveyDepartingRow(departure: d, height: CGFloat(layout.height))
                        .id(d.token)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
        }
    }

    @ViewBuilder
    func row(_ m: SurveyMoment, photos: [Photo], faces: SurveyFaces, layout: SurveyLayout) -> some View {
        let cells = ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
            let isFocused = i == session.focus
            SurveyFrame(photo: p, number: i + 1, count: photos.count,
                        height: CGFloat(isFocused ? layout.focusedHeight : layout.height),
                        recommended: p.id == m.recommended, keeper: session.isKeeper(p.id), focused: isFocused,
                        zoomed: zoomed, centre: $centre, faces: faces.strip(frame: i),
                        activeFace: zoomed && faces.people > 1 ? session.face : nil) { shift in
                withMotion(.quick, reduceMotion: reduceMotion) {
                    if shift { session.toggleKeeper(i + 1) } else { session.pick(i + 1) }
                }
                focused = true
            }
            .id(p.id)
        }
        if layout.filmstrip {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Space.l) { cells }
                        .padding(.horizontal, Space.xs)
                }
                .onChange(of: session.focus) { _, i in
                    guard m.frames.indices.contains(i) else { return }
                    withMotion(.settle, reduceMotion: reduceMotion) { proxy.scrollTo(m.frames[i], anchor: .center) }
                }
            }
        } else {
            HStack(alignment: .top, spacing: Space.l) { cells }
                .frame(maxWidth: .infinity)
        }
    }

    func footer(_ m: SurveyMoment) -> some View {
        HStack(spacing: Space.l) {
            let kept = session.keepers.count
            Text(kept == 0 ? library.tr("surveyNoKeeper") : String(format: library.tr("surveyTally"), kept, m.frames.count - kept))
                .font(TypeRole.supporting.weight(.semibold)).monospacedDigit()
                .foregroundStyle(kept == 0 ? StatusColor.look : Color.secondary)
                .contentTransition(.numericText(value: Double(kept)))
                .motionAnimation(.quick, value: kept)
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: Space.l) {
                HStack(spacing: Space.l) {
                    Button { back() } label: { Label(library.tr("back"), systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.glass).disabled(!session.canGoBack)
                    Button { skip() } label: { Label(library.tr("surveySkip"), systemImage: "forward") }
                        .buttonStyle(.glass)
                    Button { confirm(accepting: true) } label: { Label(library.tr("surveyAccept"), systemImage: "sparkles") }
                        .buttonStyle(.glass).help(library.tr("keyAccept") + " (A)")
                    Button { confirm(accepting: false) } label: {
                        Label(library.tr("surveyConfirm"), systemImage: "return").frame(minWidth: Space.giant * 3)
                    }
                    .buttonStyle(.glassProminent).tint(StatusColor.kept).help(library.tr("keyConfirm") + " (↩)")
                }
                .controlSize(.large)
            }
        }
    }

    var completion: some View {
        let c = session.counts
        return VStack(spacing: Space.xl) {
            Image(systemName: "checkmark.seal.fill").font(TypeRole.heroSymbol).foregroundStyle(StatusColor.kept)
                .symbolBounce(on: session.history.count)
                .accessibilityHidden(true)
            Text(library.tr("surveyDoneTitle")).font(TypeRole.pageTitle).foregroundStyle(.white)
            Text(String(format: library.tr("surveyTally"), c.kept, c.leftOut))
                .font(TypeRole.body).foregroundStyle(.secondary).monospacedDigit()
            Button { end(true) } label: {
                Label(singlesNext > 0 ? String(format: library.tr("surveyDoneNext"), Strings.photos(singlesNext, library.lang))
                                      : library.tr(standalone ? "surveyContinue" : "surveyDoneAlbum"),
                      systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabel())
            }
            .buttonStyle(.glassProminent).controlSize(.extraLarge)
        }
        .motionTransition(.scale(scale: 0.94).combined(with: .opacity))
    }

    var coach: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(library.tr("coachTitle")).font(TypeRole.sectionTitle)
            ForEach(ReviewKeymap.coach, id: \.textKey) { e in
                HStack(spacing: Space.l) {
                    Text(e.keys).font(TypeRole.cardTitle).monospaced()
                        .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
                        .frame(minWidth: Space.giant * 2)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: Radius.small))
                    Text(library.tr(e.textKey)).font(TypeRole.body).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Button(library.tr("coachDismiss")) { dismissCoach() }
                .buttonStyle(.glassProminent).padding(.top, Space.xs)
        }
        .padding(Space.xxxl)
        .background(.regularMaterial, in: .rect(cornerRadius: Radius.card))
        .frame(maxWidth: Space.giant * 12)
        .motionTransition(.scale(scale: 0.96).combined(with: .opacity))
    }

    // MARK: keys

    func handle(_ press: KeyPress) -> KeyPress.Result {
        let key = surveyKey(press)
        if press.phase == .up {
            guard key == .space, holdZoom else { return .ignored }
            holdZoom = false
            return .handled
        }
        var mods: ReviewKeyModifiers = []
        if press.modifiers.contains(.shift) { mods.insert(.shift) }
        if press.modifiers.contains(.command) { mods.insert(.command) }
        if press.modifiers.contains(.option) { mods.insert(.option) }
        if press.modifiers.contains(.control) { mods.insert(.control) }
        guard let key, let action = ReviewKeymap.action(for: key, modifiers: mods, in: .survey) else { return .ignored }
        if showCoach { dismissCoach() }          // the key still acts: the coach never costs a press
        perform(action)
        return .handled
    }

    func surveyKey(_ press: KeyPress) -> ReviewKey? {
        // Digits by their physical key, so ⇧1 is "1 with Shift" on every layout (it types "!" on a US keyboard).
        if let e = NSApp.currentEvent, e.type == .keyDown || e.type == .keyUp,
           let n = ReviewKeymap.digit(forKeyCode: e.keyCode) { return .digit(n) }
        let k = press.key
        if k == .rightArrow { return .right }
        if k == .leftArrow { return .left }
        if k == .upArrow { return .up }
        if k == .downArrow { return .down }
        if k == .space { return .space }
        if k == .escape { return .escape }
        if k == .return { return .returnKey }
        if k == .tab { return .tab }
        if k == .delete || k == .deleteForward || press.characters == "\u{8}" || press.characters == "\u{7F}" { return .delete }
        return press.characters.isEmpty ? nil : .character(press.characters)
    }

    func perform(_ a: KeyAction) {
        // With the keys card open only ? and esc work (no decision on a moment behind the card).
        if showKeys && a != .command(.keys) && a != .command(.close) { return }
        if session.finished {
            switch a {
            case .command(.confirm), .command(.accept), .command(.close): end(true)
            case .command(.back): back()
            case .command(.keys): showKeys.toggle()
            default: break
            }
            return
        }
        switch a {
        case .pick(let n): withMotion(.quick, reduceMotion: reduceMotion) { _ = session.pick(n) }
        case .toggleKeeper(let n): withMotion(.quick, reduceMotion: reduceMotion) { _ = session.toggleKeeper(n) }
        case .command(let c):
            switch c {
            case .confirm: confirm(accepting: false)
            case .accept: confirm(accepting: true)
            case .focusNext: withMotion(.quick, reduceMotion: reduceMotion) { session.moveFocus(1) }
            case .focusPrevious: withMotion(.quick, reduceMotion: reduceMotion) { session.moveFocus(-1) }
            case .keep: withMotion(.quick, reduceMotion: reduceMotion) { session.keepFocused() }
            case .leaveOut: withMotion(.quick, reduceMotion: reduceMotion) { session.leaveOutFocused() }
            case .nextFace: nextFace()
            case .zoom: toggleZoom()
            case .zoomHold: if !holdZoom { centreOnFace(); holdZoom = true }
            case .back: back()
            case .favourite: favourite()
            case .skip: skip()
            case .keys: showKeys.toggle()
            case .close: if showKeys { showKeys = false } else { end(false) }
            default: break
            }
        }
    }

    func automationKey() {
        let k: ReviewKey? = switch library.automationKey {
        case "right": ReviewKey.right
        case "left": ReviewKey.left
        case "back": ReviewKey.delete
        case "skip": ReviewKey.character("s")
        case "esc": ReviewKey.escape
        case "favourite": ReviewKey.character("f")
        case "keys": ReviewKey.character("?")
        case "pick1": ReviewKey.digit(1)
        case "pick2": ReviewKey.digit(2)
        case "confirm": ReviewKey.returnKey
        case "accept": ReviewKey.character("a")
        case "zoom": zoom ? nil : ReviewKey.character("z")
        case "unzoom": zoom ? ReviewKey.character("z") : nil
        default: nil
        }
        if let k, let a = ReviewKeymap.action(for: k, in: .survey) { perform(a) }
    }

    // MARK: actions

    /// Return (or A): the decision is written, the next moment comes in at once; the confirmed frames are drawn
    /// once more on top (keepers lift, the others drop) without taking any input.
    func confirm(accepting: Bool) {
        guard let m = session.current else { return }
        let previous = Dictionary(uniqueKeysWithValues: m.frames.map { ($0, library.marksOf($0)) })
        let previousKeeper = m.chosenByOwner ? m.recommended : nil
        var next = session
        let decision = accepting ? next.accept(previous: previous, previousKeeper: previousKeeper)
                                 : next.confirm(previous: previous, previousKeeper: previousKeeper)
        guard let d = decision else { return }
        library.applySurvey(d)
        let pos = session.position
        forward = true
        departure = reduceMotion ? nil : SurveyDeparture(frames: m.frames, keepers: Set(d.keepers))
        withMotion(.arrive, reduceMotion: reduceMotion) {
            session = next
            zoom = false
            holdZoom = false
        }
        clearDeparture()
        AccessibilityNotification.Announcement(String(format: library.tr("surveyConfirmedA11y"), pos.number, pos.count, d.keepers.count)).post()
        if session.finished { startCompletion() }
    }

    func skip() {
        guard session.current != nil else { return }
        forward = true
        departure = nil
        withMotion(.arrive, reduceMotion: reduceMotion) { session.skip() }
        if session.finished { startCompletion() }
    }

    /// ⌫ / ⌘Z: the previous moment again, its frames' marks and keeper restored.
    func back() {
        completionTask?.cancel()
        guard session.canGoBack else { return }
        forward = false
        departure = nil
        var e: SurveyEntry?
        withMotion(.settle, reduceMotion: reduceMotion) { e = session.back() }
        guard let e else { return }
        library.undoSurvey(e)
        AccessibilityNotification.Announcement(String(format: library.tr("surveyBackA11y"), e.index + 1)).post()
    }

    /// F: favourite on the focused frame; a favourite is in the album, so it becomes a keeper too.
    func favourite() {
        guard let id = session.focusedId else { return }
        library.toggleFavourite(id)
        if library.photo(id)?.favorite == true { withMotion(.quick, reduceMotion: reduceMotion) { session.keepFocused() } }
    }

    func toggleZoom() {
        guard session.current != nil else { return }
        if zoom { zoom = false; holdZoom = false; return }
        centreOnFace()
        zoom = true
    }

    func nextFace() {
        guard let m = session.current else { return }
        session.nextFace(people: faces(m).people)
        centreOnFace()
        if !zoomed { zoom = true }
    }

    func centreOnFace() {
        guard let m = session.current else { return }
        let boxes = session.focusedId.flatMap { library.photo($0) }?.faces?.boxes
        centre = faces(m).zoomTarget(person: session.face, frame: session.focus, fallback: boxes)
    }

    /// A new moment: zoom off, except a close call with faces, which opens on the faces at 100% (M14c).
    func momentChanged() {
        holdZoom = false
        guard let m = session.current else { zoom = false; return }
        if m.isCloseCall && faces(m).people > 0 {
            centreOnFace()
            zoom = true
        } else {
            zoom = false
        }
    }

    func clearDeparture() {
        guard let token = departure?.token else { return }
        Task {
            try? await Task.sleep(for: .seconds(motionBudget))
            if departure?.token == token { departure = nil }
        }
    }

    /// The last moment is done: a short completion moment, then the review moves on by itself (Return: now,
    /// ⌫: back to the last moment instead).
    func startCompletion() {
        completionTask?.cancel()
        completionTask = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            if !Task.isCancelled && session.finished { end(true) }
        }
    }

    func dismissCoach() {
        UserDefaults.standard.set(true, forKey: SurveyCoach.seenKey)
        withMotion(.fade, reduceMotion: reduceMotion) { showCoach = false }
    }

    func end(_ finished: Bool) {
        completionTask?.cancel()
        completionTask = nil
        holdZoom = false
        onEnd(finished && session.finished)
    }
}

/// One frame of a moment in Survey: the photo (zoomable, in sync with the others), its number and badges, up to
/// three reason chips and the faces strip.
struct SurveyFrame: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let chipHeight = Space.xxxl
    static let maxFace = Space.giant + Space.xxxl
    let photo: Photo
    let number: Int
    let count: Int
    let height: CGFloat
    let recommended: Bool
    let keeper: Bool
    let focused: Bool
    let zoomed: Bool
    @Binding var centre: ZoomPoint
    /// This frame's faces, one per person in the same order under every frame (nil: not found here).
    let faces: [Photo.Faces.Box?]
    /// The person Tab is on while zoomed (ringed in every frame).
    let activeFace: Int?
    /// Click (true with ⇧).
    let tap: (Bool) -> Void

    static func ratio(_ p: Photo) -> Double { Double(p.width ?? 3) / Double(max(p.height ?? 2, 1)) }

    var body: some View {
        let ratio = Self.ratio(photo)
        let width = height * CGFloat(ratio)
        VStack(alignment: .leading, spacing: Space.s) {
            ZoomablePhoto(url: photo.fileURL, ratio: ratio, pixelWidth: photo.width, zoomed: zoomed && !photo.isVideo,
                          centre: $centre)
                .frame(width: width, height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.medium)
                        .strokeBorder(focused ? StatusColor.accent : (keeper ? StatusColor.kept : Color.clear),
                                      lineWidth: focused ? 3 : 2)
                }
                .overlay(alignment: .topLeading) { badges.padding(Space.m) }
                .overlay(alignment: .topTrailing) { state.padding(Space.m) }
                // Kept frames stand up; the others sit back (dimmer, a little lower), so the choice reads at a glance.
                .opacity(keeper ? 1 : 0.62)
                .saturation(keeper ? 1 : 0.75)
                .offset(y: keeper || reduceMotion ? 0 : Space.s)
                .motionAnimation(.quick, value: keeper)
                .motionAnimation(.quick, value: focused)
                .motionAnimation(.settle, value: height)
            chips.frame(height: Self.chipHeight, alignment: .leading)
            if !faces.isEmpty { faceStrip(width: width) }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture { tap(NSEvent.modifierFlags.contains(.shift)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: library.tr("surveyFrameA11y"), number, count, gridTileAccessibilityLabel(photo, library.lang)))
        .accessibilityValue([recommended ? library.tr("surveyBest") : nil, library.tr(keeper ? "surveyKeep" : "surveyOut")]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(focused ? [.isImage, .isSelected] : .isImage)
        .accessibilityAction { tap(false) }
    }

    var badges: some View {
        HStack(spacing: Space.xs) {
            Text("\(number)").font(TypeRole.label.weight(.bold)).monospacedDigit()
                .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
                .background(.regularMaterial, in: .rect(cornerRadius: Radius.small))
            if recommended {
                Label(library.tr("surveyBest"), systemImage: "sparkles")
                    .font(TypeRole.label.weight(.semibold))
                    .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
                    .background(.regularMaterial, in: .capsule)
            }
        }
    }

    var state: some View {
        Image(systemName: keeper ? "checkmark.circle.fill" : "circle")
            .font(TypeRole.sectionTitle)
            .foregroundStyle(keeper ? StatusColor.kept : Color.white.opacity(0.8))
            .shadow(radius: 4)
            .symbolBounce(on: keeper)
            .contentTransition(.symbolEffect(.replace))
            .help(library.tr(keeper ? "surveyKeep" : "surveyOut"))
    }

    var chips: some View {
        HStack(spacing: Space.xs) {
            ForEach(surveyChips(photo), id: \.self) { c in
                Label(library.tr(c.textKey), systemImage: c.symbol)
                    .font(TypeRole.caption.weight(.medium)).lineLimit(1)
                    .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
                    .background((c.positive ? StatusColor.kept : StatusColor.look).opacity(0.22), in: .capsule)
                    .foregroundStyle(c.positive ? StatusColor.kept : StatusColor.look)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    func faceStrip(width: CGFloat) -> some View {
        let n = CGFloat(max(faces.count, 1))
        let size = min(Self.maxFace, max(Space.xxxl, (width - Space.s * (n - 1)) / n))
        return HStack(spacing: Space.s) {
            ForEach(faces.indices, id: \.self) { r in
                Group {
                    if let b = faces[r] {
                        FaceCrop(url: photo.fileURL, box: b, size: size)
                    } else {
                        Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .frame(width: size, height: size)
                            .overlay { Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(.tertiary) }
                            .help(library.tr("faceNotFound"))
                    }
                }
                .overlay { Circle().strokeBorder(StatusColor.accent, lineWidth: activeFace == r ? 3 : 0) }
            }
        }
    }
}

/// The confirmed moment's frames, once more, for the hand-off: keepers lift away, the others drop. Never takes input.
struct SurveyDepartingRow: View {
    @EnvironmentObject var library: LibraryModel
    let departure: SurveyDeparture
    let height: CGFloat
    @State private var gone = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.l) {
            ForEach(departure.frames, id: \.self) { id in
                if let p = library.photo(id) {
                    let keep = departure.keepers.contains(id)
                    Thumbnail(url: p.fileURL, side: 1024, fill: false)
                        .frame(width: height * CGFloat(SurveyFrame.ratio(p)), height: height)
                        .clipShape(.rect(cornerRadius: Radius.medium))
                        .scaleEffect(gone ? (keep ? 1.03 : 0.94) : 1)
                        .offset(y: gone ? (keep ? -Space.huge : Space.giant * 2) : 0)
                        .opacity(gone ? 0 : 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withMotion(.drop) { gone = true } }
    }
}

/// "Moment 3 of 12" as a ring.
struct SurveyProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(.tertiary, lineWidth: 3)
            Circle().trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(StatusColor.kept, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .motionAnimation(.settle, value: progress)
        }
        .accessibilityHidden(true)
    }
}

/// The always-visible keys at the bottom of the review (M14c), from `ReviewKeymap.bar`.
struct ShortcutBar: View {
    @EnvironmentObject var library: LibraryModel
    let context: ReviewContext

    var body: some View {
        HStack(spacing: Space.xl) {
            ForEach(ReviewKeymap.bar(context), id: \.textKey) { e in
                HStack(spacing: Space.xs) {
                    Text(e.keys).font(TypeRole.caption.weight(.semibold)).monospaced()
                        .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: Radius.small))
                    Text(library.tr(e.textKey)).font(TypeRole.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(library.tr("barA11y"))
    }
}
