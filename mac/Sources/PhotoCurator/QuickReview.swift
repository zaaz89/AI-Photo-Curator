import CuratorCore
import SwiftUI

/// Quick review (M10): the album one photo at a time, full window. → keeps, ← leaves out, ⌫ or ⌘Z goes back
/// and undoes, Space skips, F favourite, hold Z zooms on the subject, E shows the faces large, ? the keys.
/// Every decision is written at once; nothing is ever deleted.
struct QuickReviewView: View {
    @EnvironmentObject var library: LibraryModel
    @State var filter: ReviewFilter
    @State private var session = ReviewSession(queue: [])
    @State private var started = false
    @State private var zoom = false
    @State private var showFaces = false
    @State private var showKeys = false
    @State private var flash: ReviewAction?
    @State private var slide: CGFloat = 0
    @FocusState private var focused: Bool

    var photo: Photo? { session.current.flatMap(library.photo) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar.padding(.horizontal, 22).padding(.top, 14)
                if session.finished && started {
                    EndCard(session: session, filter: filter, again: { f, ids in begin(f, ids: ids) }, close: close)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let p = photo {
                    stage(p).frame(maxWidth: .infinity, maxHeight: .infinity)
                    bottom(p).padding(.horizontal, 22).padding(.bottom, 18)
                } else if started {
                    GuideEmpty(symbol: "checkmark.circle", title: library.tr("reviewNothing"), text: library.tr("reviewNothingText"))
                        .foregroundStyle(.white).frame(maxHeight: .infinity)
                }
            }
            if showKeys { KeysCard { showKeys = false } }
        }
        .environment(\.colorScheme, .dark)
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(.rightArrow) { decide(.keep); return .handled }
        .onKeyPress(.leftArrow) { decide(.leaveOut); return .handled }
        .onKeyPress(.space) { decide(.skip); return .handled }
        .onKeyPress(keys: [.delete, .deleteForward, KeyEquivalent("\u{8}"), KeyEquivalent("\u{7F}")]) { _ in back(); return .handled }
        .onKeyPress(.escape) { if showKeys { showKeys = false } else { close() }; return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { _ in favourite(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "eE")) { _ in showFaces.toggle(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "?/")) { _ in showKeys.toggle(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "zZ"), phases: [.down, .up]) { press in
            zoom = press.phase == .down
            return .handled
        }
        .onAppear { begin(filter, ids: nil); focused = true }
        .onChange(of: library.reviewUndoRequest) { _, _ in back() }
        .onChange(of: library.loadedTripId) { _, _ in close() }       // another album: the ids mean something else
    }

    // MARK: layout

    var topBar: some View {
        HStack(spacing: 14) {
            Button { close() } label: { Label(library.tr("done"), systemImage: "xmark") }
                .buttonStyle(.glass).keyboardShortcut(.cancelAction)
            Picker("", selection: Binding(get: { filter }, set: { begin($0, ids: nil) })) {
                ForEach(ReviewFilter.allCases) { f in Text(library.tr("review_" + f.rawValue)).tag(f) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 360)
            Spacer()
            let c = session.counts
            HStack(spacing: 14) {
                Label("\(c.kept)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Label("\(c.leftOut)", systemImage: "xmark.circle.fill").foregroundStyle(.secondary)
                if c.skipped > 0 { Label("\(c.skipped)", systemImage: "forward.fill").foregroundStyle(.orange) }
            }
            .font(.callout.weight(.semibold)).monospacedDigit()
            Text("\(min(session.index + 1, session.queue.count)) / \(session.queue.count)")
                .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
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
        GeometryReader { g in
            let anchor = zoomAnchor(p)
            Thumbnail(url: p.fileURL, side: 2048, fill: false)
                .aspectRatio(CGFloat(p.width ?? 3) / CGFloat(max(p.height ?? 2, 1)), contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .scaleEffect(zoom ? 3 : 1, anchor: anchor)
                .frame(width: g.size.width, height: g.size.height)
                .clipped()
                .overlay {
                    // The decision flashes on the photo: green for keep, grey for leave out.
                    if let flash {
                        Image(systemName: flash == .keep ? "checkmark.circle.fill" : (flash == .leaveOut ? "xmark.circle.fill" : "forward.fill"))
                            .font(.system(size: 96, weight: .semibold))
                            .foregroundStyle(flash == .keep ? Color.green : (flash == .leaveOut ? Color.white.opacity(0.7) : Color.orange))
                            .shadow(radius: 20)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .offset(x: slide)
                .animation(.snappy(duration: 0.18), value: zoom)
                .id(p.id)
                .transition(.opacity)
        }
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
                    .background((inAlbum ? Color.green : Color.gray).opacity(0.25), in: .capsule)
                    .foregroundStyle(inAlbum ? .green : .white)
                ForEach(reviewReasons(p), id: \.self) { r in
                    Label(reasonText(r, p), systemImage: reasonIcon(r))
                        .font(.callout).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.orange.opacity(0.22), in: .capsule).foregroundStyle(.orange)
                }
                if p.favorite { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                Spacer()
                Text("\(p.clock) · \(p.owner)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            if let siblings = momentFrames(p), siblings.count > 1 {
                HStack(spacing: 6) {
                    Text(library.tr("sameMoment")).font(.caption).foregroundStyle(.secondary)
                    ForEach(siblings) { s in
                        PhotoCover(photo: s, side: 260, radius: 6).frame(width: 64, height: 44)
                            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(s.id == p.id ? Color.white : .clear, lineWidth: 2) }
                            .opacity(s.goesToAlbumDespiteFocus ? 1 : 0.45)
                    }
                    Spacer()
                }
            }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button { decide(.leaveOut) } label: {
                        Label(library.tr("leaveOut"), systemImage: "arrow.left").frame(minWidth: 140)
                    }
                    .buttonStyle(.glass).controlSize(.extraLarge)
                    Button { back() } label: { Label(library.tr("back"), systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.glass).controlSize(.extraLarge).disabled(!session.canGoBack)
                    Button { decide(.skip) } label: { Label(library.tr("skip"), systemImage: "forward") }
                        .buttonStyle(.glass).controlSize(.extraLarge)
                    Button { decide(.keep) } label: {
                        Label(library.tr("keep"), systemImage: "arrow.right").labelStyle(TrailingIconLabel()).frame(minWidth: 140)
                    }
                    .buttonStyle(.glassProminent).tint(.green).controlSize(.extraLarge)
                }
            }
        }
    }

    // MARK: actions

    func begin(_ f: ReviewFilter, ids: [Int]?) {
        filter = f
        let queue = ids ?? reviewQueue(library.photos, filter: f)
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
        withAnimation(.snappy(duration: 0.12)) { flash = action; slide = action == .keep ? 40 : (action == .leaveOut ? -40 : 0) }
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.snappy(duration: 0.15)) {
                session.record(action, previous: previous)
                flash = nil; slide = 0; zoom = false
            }
            library.setReviewBookmark(filter, session.current)
        }
    }

    func back() {
        guard let e = session.back() else { return }
        if e.action != .skip { library.restore(e.photoId, e.previous) }
        library.setReviewBookmark(filter, session.current)
        flash = nil; slide = 0
    }

    func favourite() { if let p = photo { library.toggleFavourite(p.id) } }

    func close() {
        if session.finished { library.setReviewBookmark(filter, nil) }
        library.reviewFilter = nil
    }

    // MARK: helpers

    func mainFaces(_ p: Photo) -> [Photo.Faces.Box]? {
        guard let boxes = p.faces?.boxes else { return nil }
        let main = boxes.filter { $0.main != false }
        return Array((main.isEmpty ? boxes : main).prefix(4))
    }

    /// Hold Z zooms on the main face, else on the centre.
    func zoomAnchor(_ p: Photo) -> UnitPoint {
        guard let b = mainFaces(p)?.max(by: { $0.w * $0.h < $1.w * $1.h }) else { return .center }
        return UnitPoint(x: b.x + b.w / 2, y: b.y + b.h / 2)
    }

    func momentFrames(_ p: Photo) -> [Photo]? {
        guard let g = p.duplicate?.group, ["exact", "near"].contains(p.duplicate?.category ?? "") else { return nil }
        return library.photos.filter { $0.duplicate?.group == g }
    }

    func reasonText(_ code: String, _ p: Photo) -> String { library.trOr("why2_" + code, code) }

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
            Text(library.tr("reviewDone")).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
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
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(library.tr("reviewKeys")).font(.title2.weight(.bold))
            ForEach([("→", "keyKeep"), ("←", "keyLeaveOut"), ("⌫  ⌘Z", "keyBack"), ("␣", "keySkip"), ("F", "keyFavourite"),
                     ("Z", "keyZoom"), ("E", "keyFaces"), ("?", "keyKeys"), ("esc", "keyClose")], id: \.0) { k, t in
                HStack {
                    Text(k).font(.system(.body, design: .rounded).weight(.semibold)).frame(width: 80, alignment: .leading)
                    Text(library.tr(t)).foregroundStyle(.secondary)
                }
            }
            Button(library.tr("done"), action: close).buttonStyle(.glassProminent).padding(.top, 6)
        }
        .padding(26)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .frame(maxWidth: 440)
    }
}
