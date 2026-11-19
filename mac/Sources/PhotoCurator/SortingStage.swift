import CuratorCore
import SwiftUI

// MARK: the stage's own state

/// What the sorting stage has shown so far. The data (verdicts) always come from the library; this only says
/// how far the show has got: which photos have flown in, which verdicts are shown, which frames are stacked.
@MainActor final class StageModel: ObservableObject {
    enum Act { case idle, arrival, quality, moments }
    struct Gather: Equatable { let keeper: Int; let layer: Int }

    @Published var arrived = Set<Int>()
    @Published var revealed = Set<Int>()
    @Published var stackedShown = Set<Int>()
    @Published var lifting = Set<Int>()
    @Published var scanning = Set<Int>()
    @Published var gathering: [Int: Gather] = [:]
    @Published var settled = false
    @Published var act: Act = .idle
    @Published var images: [Int: NSImage] = [:]
    @Published var aspects: [Int: Double] = [:]

    weak var library: LibraryModel?
    var motion = true
    private var trip: String?
    private var queue: Task<Void, Never>?
    private var queued = Set<Int>()             // arrivals waiting in the queue
    private var finishing = false               // the closing acts are queued
    private var loading = Set<Int>()

    var busy: Bool { act != .idle }

    /// Opening the page: a finished album shows its overview at once; a running analysis is followed live.
    func attach(_ lib: LibraryModel) {
        library = lib
        if trip != lib.tripId { reset(to: lib.tripId) }
        if !lib.analysing && !lib.photos.isEmpty && lib.photos.allSatisfy(hasResults) && arrived.isEmpty {
            showAll(lib.photos)
        }
        sync()
    }

    private func reset(to id: String?) {
        queue?.cancel(); queue = nil
        trip = id
        arrived = []; revealed = []; stackedShown = []; lifting = []; scanning = []; gathering = [:]
        settled = false; act = .idle; queued = []; finishing = false
        images = [:]; aspects = [:]; loading = []; toLoad = []
    }

    private func showAll(_ photos: [Photo]) {
        let ids = Set(photos.map(\.id))
        arrived = ids; revealed = ids; stackedShown = ids; settled = true
        load(photos)
    }

    /// Follows the library: new photos fly in, and once the analysis is over the verdicts play out.
    func sync() {
        guard let lib = library else { return }
        if trip != lib.tripId { reset(to: lib.tripId) }
        let present = Set(lib.photos.map(\.id))
        if !arrived.isSubset(of: present) {             // a photo left the album (Finish album, a folder removed)
            arrived.formIntersection(present); revealed.formIntersection(present); stackedShown.formIntersection(present)
        }
        let new = lib.photos.filter { !arrived.contains($0.id) && !queued.contains($0.id) }
        if !new.isEmpty {
            settled = false
            load(new)
            queued.formUnion(new.map(\.id))
            enqueue { await self.arrive(new.map(\.id)) }
        }
        let scored = lib.photos.filter { hasResults($0) && !revealed.contains($0.id) }
        if !scored.isEmpty && !finishing && (!lib.analysing || lib.photos.allSatisfy(hasResults)) {
            // Focus and faces are known for everyone: show them now (during the analysis too), moments at the end.
            finishing = true
            enqueue { await self.quality() }
        }
        if !lib.analysing && !finishing && !settled && !lib.photos.isEmpty && lib.photos.allSatisfy(hasResults) && arrived == present {
            finishing = true
            enqueue { await self.quality() }
        }
    }

    /// "Show what you did": everything flies again, from the folders to the overview.
    func replay() {
        guard let lib = library else { return }
        queue?.cancel(); queue = nil
        withAnimation(motion ? .easeInOut(duration: 0.35) : nil) {
            arrived = []; revealed = []; stackedShown = []; lifting = []; scanning = []; gathering = [:]
            settled = false; act = .idle
        }
        queued = Set(lib.photos.map(\.id)); finishing = true
        let ids = lib.photos.map(\.id)
        load(lib.photos)
        enqueue {
            await self.pause(0.5)
            await self.arrive(ids)
            await self.quality()
        }
    }

    private func enqueue(_ step: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            if Task.isCancelled { return }
            await step()
        }
    }

    private func pause(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }

    private func animate(_ a: Animation, _ change: () -> Void) {
        if motion { withAnimation(a, change) } else { withAnimation(.easeInOut(duration: 0.15), change) }
    }

    private var toLoad: [Photo] = []
    private var loaders = 0

    /// Thumbnails come from macOS (Quick Look), several at once, in time order so the first to fly are ready first.
    private func load(_ photos: [Photo]) {
        let todo = photos.filter { !loading.contains($0.id) && images[$0.id] == nil }
        loading.formUnion(todo.map(\.id))
        toLoad.append(contentsOf: todo)
        while loaders < 8 && !toLoad.isEmpty {
            loaders += 1
            Task { @MainActor in
                while !toLoad.isEmpty {
                    let p = toLoad.removeFirst()
                    guard let img = await ThumbnailCache.shared.image(for: p.fileURL, side: 260) else { continue }
                    images[p.id] = img
                    if img.size.height > 0 { aspects[p.id] = img.size.width / img.size.height }
                }
                loaders -= 1
            }
        }
    }

    // Act 1: photos fly from their folders into the album, in time order.
    private func arrive(_ ids: [Int]) async {
        act = .arrival
        let gap = stagger(ids.count, total: 3.0, min: 0.008, max: 0.09)
        for id in ids {
            if Task.isCancelled { return }
            animate(.spring(response: 0.75, dampingFraction: 0.76)) { _ = arrived.insert(id) }
            queued.remove(id)
            await pause(gap)
        }
        act = .idle
    }

    // Act 2: every judged photo gets its verdict; blurry ones lift and drop into "Removed".
    private func quality() async {
        guard let lib = library else { return }
        act = .quality
        await pause(0.4)
        let todo = lib.photos.filter { arrived.contains($0.id) && hasResults($0) && !revealed.contains($0.id) }
        let removed = todo.filter { sortVerdict($0) == .removed }.count
        let gap = stagger(todo.count, total: 3.0, min: 0.01, max: 0.08)
        for p in todo {
            if Task.isCancelled { return }
            scanning.insert(p.id)
            if sortVerdict(p) == .removed && removed <= 40 && motion {
                animate(.easeOut(duration: 0.2)) { _ = lifting.insert(p.id) }
                await pause(0.3)
                animate(.spring(response: 0.8, dampingFraction: 0.7)) { _ = revealed.insert(p.id); _ = lifting.remove(p.id) }
                await pause(0.12)
            } else {
                animate(.snappy(duration: 0.25)) { _ = revealed.insert(p.id) }
                await pause(gap)
            }
            scanning.remove(p.id)
        }
        act = .idle
        finishing = false
        // Moments are built last: stack them once the analysis is over.
        if !lib.analysing { await moments() }
    }

    // Act 3: near-identical frames slide onto the best one, then into "Stacked". Then the overview.
    private func moments() async {
        guard let lib = library else { return }
        act = .moments
        let extras = lib.photos.filter { sortVerdict($0) == .stacked && !stackedShown.contains($0.id) }
        let groups = Dictionary(grouping: extras) { $0.duplicate?.group ?? -1 }
        let gap = stagger(groups.count, total: 4.0, min: 0.05, max: 0.5)
        for (g, frames) in groups.sorted(by: { $0.key < $1.key }) {
            if Task.isCancelled { return }
            let keeper = lib.photos.first { $0.duplicate?.group == g && $0.duplicate?.keeper == true && sortVerdict($0) != .stacked }
            if let k = keeper, groups.count <= 40, motion {
                animate(.spring(response: 0.55, dampingFraction: 0.78)) {
                    for (i, f) in frames.enumerated() { gathering[f.id] = Gather(keeper: k.id, layer: i + 1) }
                }
                await pause(0.45)
            }
            animate(.spring(response: 0.8, dampingFraction: 0.74)) {
                for f in frames { gathering[f.id] = nil; stackedShown.insert(f.id) }
            }
            await pause(gap)
        }
        await pause(0.4)
        animate(.spring(response: 1.0, dampingFraction: 0.82)) { settled = true; act = .idle }
    }

    /// Analysis finished: play the rest.
    func analysisEnded() {
        guard let lib = library, !lib.photos.isEmpty else { return }
        if lib.photos.contains(where: { !revealed.contains($0.id) }) {
            if !finishing { finishing = true; enqueue { await self.quality() } }
        } else {
            enqueue { await self.moments() }
        }
    }
}

// MARK: the page

private enum StagePlace: Equatable { case source, album, onKeeper(Int, Int), tray(SortVerdict, Int) }

private struct TileFrame: Equatable {
    var rect: CGRect
    var rotation: Double = 0
    var z: Double = 10
}

/// The sorting stage (M12): photos fly in by day, a light sweep follows the analysis, blurry ones drop into
/// "Removed", near-identical frames stack behind the best one, and everything settles into one overview with
/// three trays. Every photo can be put back from its tray.
struct SortingStage: View {
    @EnvironmentObject var library: LibraryModel
    @StateObject private var stage = StageModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openTray: SortVerdict?

    var body: some View {
        GeometryReader { g in
            let geo = StageGeometry(size: g.size, settled: stage.settled)
            let places = placesNow()
            let flow = stageFlow(albumItems(places), in: geo.albumRect, maxHeight: stage.settled ? 230 : 170)
            let frames = tileFrames(places, flow: flow, geo: geo)
            let sweep = sweepIds()
            ZStack(alignment: .topLeading) {
                StageBackground()
                StageHeader(stage: stage, counts: counts(places)).frame(width: g.size.width)
                if !stage.settled {
                    ForEach(Array(library.sources.enumerated()), id: \.element.id) { i, s in
                        SourceChip(owner: s.owner, count: library.photos.filter { $0.sourceId == s.id && stage.arrived.contains($0.id) }.count,
                                   total: library.photos.filter { $0.sourceId == s.id }.count)
                            .position(geo.sourcePoint(i))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                ForEach(flow.days, id: \.day) { d in
                    Text(dayLabel(d.day))
                        .font(.system(size: stage.settled ? 15 : 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .modifier(LeadingAnchor(x: d.origin.x, y: d.origin.y + 11))
                }
                ForEach(SortVerdict.trays, id: \.self) { v in
                    TrayCard(verdict: v, count: trayCount(v, places), rect: geo.trayRect(v), settled: stage.settled) { openTray = v }
                        .popover(isPresented: Binding(get: { openTray == v }, set: { if !$0 { openTray = nil } }),
                                 arrowEdge: .top) { TrayContents(verdict: v, ids: trayIds(v, places)) { openTray = nil } }
                }
                ForEach(library.photos) { p in
                    if let f = frames[p.id] {
                        StageTile(photo: p, image: stage.images[p.id], size: f.rect.size,
                                  verdict: stage.revealed.contains(p.id) ? sortVerdict(p) : nil,
                                  scanning: stage.scanning.contains(p.id) || sweep.contains(p.id),
                                  lifted: stage.lifting.contains(p.id),
                                  stacked: stackedCount(p, places))
                            .rotationEffect(.degrees(f.rotation))
                            .position(x: f.rect.midX, y: f.rect.midY)
                            .zIndex(f.z)
                            .opacity(places[p.id] == .source ? 0 : 1)
                            .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8), value: f)
                            .onTapGesture { tapped(p, places) }
                    }
                }
            }
        }
        .clipped()
        .onAppear { stage.motion = !reduceMotion; stage.attach(library) }
        .onChange(of: library.photos) { _, _ in stage.sync() }
        .onChange(of: library.tripId) { _, _ in stage.attach(library) }
        .onChange(of: library.analysing) { was, now in if was && !now { stage.analysisEnded() } }
        .onChange(of: library.stageReplayTick) { _, _ in stage.replay() }
        .onChange(of: reduceMotion) { _, r in stage.motion = !r }
    }

    // MARK: where everything is

    private func placesNow() -> [Int: StagePlace] {
        var out: [Int: StagePlace] = [:]
        var slots: [SortVerdict: Int] = [:]
        for p in library.photos {
            if !stage.arrived.contains(p.id) { out[p.id] = .source; continue }
            if let g = stage.gathering[p.id] { out[p.id] = .onKeeper(g.keeper, g.layer); continue }
            let v = sortVerdict(p)
            if v == .removed && stage.revealed.contains(p.id) || v == .stacked && stage.stackedShown.contains(p.id) {
                let n = slots[v, default: 0]; slots[v] = n + 1
                out[p.id] = .tray(v, n)
            } else {
                out[p.id] = .album
            }
        }
        return out
    }

    private func albumItems(_ places: [Int: StagePlace]) -> [StageItem] {
        library.photos.filter { places[$0.id] == .album }.map { p in
            StageItem(id: p.id, day: p.day, aspect: stage.aspects[p.id] ?? defaultAspect(p))
        }
    }

    private func defaultAspect(_ p: Photo) -> Double {
        guard let w = p.width, let h = p.height, w > 0, h > 0 else { return 1.5 }
        return Double(w) / Double(h)
    }

    private func tileFrames(_ places: [Int: StagePlace], flow: StageFlow, geo: StageGeometry) -> [Int: TileFrame] {
        var out: [Int: TileFrame] = [:]
        let sourceIndex = Dictionary(uniqueKeysWithValues: library.sources.enumerated().map { ($1.id, $0) })
        let trayTotals = Dictionary(grouping: places.values.compactMap { if case .tray(let v, _) = $0 { return v }; return nil }) { $0 }
            .mapValues(\.count)
        for p in library.photos {
            guard let place = places[p.id] else { continue }
            let aspect = stage.aspects[p.id] ?? defaultAspect(p)
            let jitter = Double((p.id * 7919) % 13) / 6.0 - 1.0
            switch place {
            case .source:
                let c = geo.sourcePoint(sourceIndex[p.sourceId] ?? 0)
                out[p.id] = TileFrame(rect: CGRect(x: c.x - 20 * aspect, y: c.y - 20, width: 40 * aspect, height: 40),
                                      rotation: jitter * 12, z: 1)
            case .album:
                if let r = flow.slots[p.id] { out[p.id] = TileFrame(rect: r, z: stage.lifting.contains(p.id) ? 70 : 10) }
            case .onKeeper:
                break
            case .tray(let v, let slot):
                let r = geo.trayRect(v)
                let h: CGFloat = min(76, r.height - 90)
                let n = max(1, trayTotals[v] ?? 1)
                let step = min(h * 0.85, (r.width - 48 - h * 1.4) / CGFloat(max(1, n - 1)))
                let x = r.minX + 24 + CGFloat(slot) * max(3, step)
                out[p.id] = TileFrame(rect: CGRect(x: x, y: r.maxY - h - 18, width: h * aspect, height: h),
                                      rotation: -6 + Double(slot % 5) * 3 + jitter, z: 30 + Double(slot) * 0.01)
            }
            if stage.lifting.contains(p.id), var f = out[p.id] { f.rect = f.rect.offsetBy(dx: 0, dy: -18); out[p.id] = f }
        }
        for p in library.photos {
            if case .onKeeper(let k, let layer) = places[p.id], let kf = out[k] {
                out[p.id] = TileFrame(rect: kf.rect.offsetBy(dx: CGFloat(layer) * 9, dy: CGFloat(layer) * -9),
                                      rotation: Double(layer) * 3.5, z: 40 + Double(layer))
            }
        }
        return out
    }

    /// During the analysis the sweep follows the engine's progress through the photos, in time order.
    private func sweepIds() -> Set<Int> {
        guard library.analysing, [.quality, .faces, .working].contains(library.job.phase) else { return [] }
        let ordered = library.photos.filter { stage.arrived.contains($0.id) && !$0.isVideo }
        guard !ordered.isEmpty else { return [] }
        let at = min(ordered.count - 1, Int(Double(ordered.count) * library.job.progress / 100))
        return Set(ordered[max(0, at - 2)...at].map(\.id))
    }

    private func counts(_ places: [Int: StagePlace]) -> StageCounts {
        var c = StageCounts()
        for p in library.photos {
            guard let place = places[p.id], place != .source else { continue }
            c.read += 1
            switch place {
            case .tray(.removed, _): c.removed += 1
            case .tray(.stacked, _): c.stacked += 1
            default:
                c.inAlbum += 1
                if stage.revealed.contains(p.id) && sortVerdict(p) == .check { c.check += 1 }
            }
        }
        return c
    }

    private func trayIds(_ v: SortVerdict, _ places: [Int: StagePlace]) -> [Int] {
        library.photos.filter { p in
            if v == .check { return stage.revealed.contains(p.id) && sortVerdict(p) == .check }
            if case .tray(let t, _) = places[p.id] { return t == v }
            return false
        }.map(\.id)
    }

    private func trayCount(_ v: SortVerdict, _ places: [Int: StagePlace]) -> Int { trayIds(v, places).count }

    private func stackedCount(_ p: Photo, _ places: [Int: StagePlace]) -> Int {
        guard let g = p.duplicate?.group, p.duplicate?.keeper == true, places[p.id] == .album else { return 0 }
        var n = 0
        for o in library.photos where o.duplicate?.group == g && o.id != p.id {
            if case .tray(.stacked, _) = places[o.id] { n += 1 }
        }
        return n
    }

    private func tapped(_ p: Photo, _ places: [Int: StagePlace]) {
        if case .tray(let v, _) = places[p.id] { openTray = v; return }
        if stage.revealed.contains(p.id) && sortVerdict(p) == .check { openTray = .check }
    }

    private func dayLabel(_ day: String) -> String {
        day == Photo.undated ? library.tr("stageUndated") : formatDay(day, library.lang, style: .short)
    }
}

/// Places a label by its leading edge (positions are centres otherwise).
private struct LeadingAnchor: ViewModifier {
    let x: CGFloat, y: CGFloat
    func body(content: Content) -> some View {
        content.frame(width: 260, alignment: .leading).position(x: x + 130, y: y)
    }
}

extension SortVerdict {
    static let trays: [SortVerdict] = [.removed, .stacked, .check]
}

struct StageCounts { var read = 0, inAlbum = 0, stacked = 0, removed = 0, check = 0 }

struct StageGeometry {
    let size: CGSize
    let settled: Bool
    let headerH: CGFloat = 150
    let trayH: CGFloat = 170
    var trayTop: CGFloat { size.height - trayH - 20 }
    var albumRect: CGRect {
        let left: CGFloat = settled ? 36 : 250
        return CGRect(x: left, y: headerH, width: max(100, size.width - left - 36), height: max(100, trayTop - headerH - 22))
    }
    func trayRect(_ v: SortVerdict) -> CGRect {
        let i = CGFloat(SortVerdict.trays.firstIndex(of: v) ?? 0)
        let gap: CGFloat = 16, w = (size.width - 72 - 2 * gap) / 3
        return CGRect(x: 36 + i * (w + gap), y: trayTop, width: w, height: trayH)
    }
    func sourcePoint(_ i: Int) -> CGPoint { CGPoint(x: 130, y: headerH + 36 + CGFloat(i) * 84) }
}

// MARK: pieces

let stageColors: [Color] = [Color(red: 0.42, green: 0.36, blue: 1.0), Color(red: 0.0, green: 0.72, blue: 0.95),
                            Color(red: 0.98, green: 0.36, blue: 0.62), Color(red: 1.0, green: 0.62, blue: 0.2)]
private let removedColor = Color(red: 1, green: 0.42, blue: 0.42)

struct StageBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var move = false
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08)
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(stageColors[i].opacity(0.3))
                    .frame(width: 560, height: 560)
                    .offset(x: (move ? 1 : -1) * CGFloat([260, -320, 180, -120][i]),
                            y: (move ? -1 : 1) * CGFloat([140, 90, -200, 220][i]))
                    .blur(radius: 120)
            }
        }
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { move = true } } }
        .allowsHitTesting(false)
    }
}

private struct ScanBand: View {
    @State private var x: CGFloat = -1.2
    var body: some View {
        GeometryReader { g in
            LinearGradient(colors: [.clear, .white.opacity(0.55), stageColors[1].opacity(0.35), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: g.size.width * 0.55)
                .offset(x: x * g.size.width)
                .blendMode(.plusLighter)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.55)) { x = 1.4 } }
        .allowsHitTesting(false)
    }
}

private struct StageTile: View {
    let photo: Photo
    let image: NSImage?
    let size: CGSize
    let verdict: SortVerdict?
    let scanning: Bool
    let lifted: Bool
    let stacked: Int

    var corner: CGFloat { min(12, size.height * 0.12) }

    var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().scaledToFill() } else { Rectangle().fill(.white.opacity(0.08)) }
        }
        .frame(width: size.width, height: size.height)
        .overlay { if scanning { ScanBand() } }
        .overlay { if verdict == .removed { removedColor.opacity(0.25).blendMode(.multiply) } }
        .saturation(verdict == .removed ? 0.25 : 1)
        .clipShape(.rect(cornerRadius: corner))
        .overlay {
            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(verdict == .check ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.white.opacity(0.14)),
                              lineWidth: verdict == .check ? 2 : 1)
        }
        .overlay(alignment: .bottomTrailing) {
            if let verdict, verdict != .stacked, size.height > 34 {
                Image(systemName: symbol(verdict))
                    .font(.system(size: max(10, min(18, size.height * 0.16)), weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, color(verdict))
                    .shadow(radius: 3).padding(4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if stacked > 0 {
                Text("×\(stacked + 1)").font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: .capsule).padding(5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if photo.isVideo && size.height > 30 {
                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(5).shadow(radius: 2)
            }
        }
        .background {
            if stacked > 0 {
                ForEach(0..<min(stacked, 3), id: \.self) { k in
                    RoundedRectangle(cornerRadius: corner).fill(.white.opacity(0.18))
                        .offset(x: CGFloat(k + 1) * 4, y: CGFloat(k + 1) * -4)
                }
            }
        }
        .shadow(color: .black.opacity(lifted ? 0.6 : 0.3), radius: lifted ? 16 : 6, y: lifted ? 10 : 3)
        .scaleEffect(lifted ? 1.08 : 1)
        .accessibilityElement()
        .accessibilityLabel(photo.filename)
    }

    func symbol(_ v: SortVerdict) -> String {
        switch v {
        case .album: "checkmark.circle.fill"
        case .check: "exclamationmark.circle.fill"
        case .removed: "drop.degreesign.slash.fill"
        case .stacked: "square.stack.fill"
        }
    }
    func color(_ v: SortVerdict) -> Color {
        switch v { case .album: .green; case .check: .orange; case .removed: removedColor; case .stacked: stageColors[1] }
    }
}

private struct SourceChip: View {
    @EnvironmentObject var library: LibraryModel
    let owner: String
    let count: Int
    let total: Int
    var body: some View {
        HStack(spacing: 10) {
            PersonBadge(name: owner, index: 0, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(owner).font(.callout.weight(.semibold)).lineLimit(1)
                Text(total == 0 ? "…" : "\(count)/\(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(width: 196, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct StageHeader: View {
    @EnvironmentObject var library: LibraryModel
    @ObservedObject var stage: StageModel
    let counts: StageCounts

    var title: String {
        if library.analysing {
            switch library.job.phase {
            case .reading: return library.tr("stagePhase_reading")
            case .quality: return library.tr("stagePhase_quality")
            case .faces, .working: return library.tr("stagePhase_faces")
            case .paused: return library.tr("phase_paused")
            default: return library.tr("stagePhase_other")
            }
        }
        switch stage.act {
        case .arrival: return library.tr("stagePhase_reading")
        case .quality: return library.tr("stagePhase_reveal")
        case .moments: return library.tr("stagePhase_moments")
        case .idle: return library.photos.isEmpty ? library.tr("stageWaiting") : library.tr("stageDone")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                AIRing(symbol: stage.settled ? "checkmark" : "sparkles", size: 46,
                       spinning: library.analysing || stage.busy, progress: library.analysing ? library.job.progress / 100 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .id(title).transition(.push(from: .bottom).combined(with: .opacity))
                    Text(stage.settled ? library.tr("stageDoneSub") : library.albumName)
                        .foregroundStyle(.white.opacity(0.65)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .animation(.snappy, value: title)
                Spacer()
                StageCounter(value: counts.read, label: library.tr("counter_read"), color: .white)
                StageCounter(value: counts.inAlbum, label: library.tr("counter_album"), color: .green)
                StageCounter(value: counts.stacked, label: library.tr("counter_stacked"), color: stageColors[1])
                StageCounter(value: counts.removed, label: library.tr("counter_removed"), color: removedColor)
                StageCounter(value: counts.check, label: library.tr("counter_check"), color: .orange)
            }
            HStack(spacing: 10) {
                if stage.settled {
                    Text(String(format: library.tr("stageSummary"), summary.taken, summary.inAlbum))
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Spacer()
                    Button { library.stageReplayTick += 1 } label: { Label(library.tr("replay"), systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.glass)
                    Button { library.destination = .step(.selection) } label: {
                        Label(library.tr("stageNext"), systemImage: "arrow.right")
                    }
                    .buttonStyle(.glassProminent)
                } else if library.analysing {
                    ProgressView(value: library.job.progress, total: 100).tint(stageColors[1]).frame(maxWidth: 520)
                    Spacer()
                    Button(library.tr("stop")) { library.stopJob() }.buttonStyle(.glass)
                } else {
                    Spacer()
                }
            }
            .frame(height: 34)
        }
        .padding(.horizontal, 36).padding(.top, 26)
        .environment(\.colorScheme, .dark)
    }

    /// The same numbers as the album home's funnel (a RAW+JPEG or Live Photo pair counts once).
    var summary: (taken: Int, inAlbum: Int) {
        if let f = library.overview?.funnel, f.taken > 0 { return (f.taken, f.inAlbum) }
        return (library.photos.count, library.photos.filter(\.goesToAlbumDespiteFocus).count)
    }
}

private struct StageCounter: View {
    let value: Int
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy, value: value)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(minWidth: 64)
    }
}

private struct TrayCard: View {
    @EnvironmentObject var library: LibraryModel
    let verdict: SortVerdict
    let count: Int
    let rect: CGRect
    let settled: Bool
    let open: () -> Void

    var color: Color { verdict == .removed ? removedColor : (verdict == .stacked ? stageColors[1] : .orange) }
    var symbol: String {
        switch verdict { case .removed: "drop.degreesign.slash"; case .stacked: "square.stack.3d.down.right"; default: "exclamationmark.circle" }
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(library.tr("tray_" + verdict.rawValue), systemImage: symbol).font(.headline).foregroundStyle(color)
                    Spacer()
                    Text("\(count)").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(count)))
                }
                if settled && count > 0 {
                    Text(library.tr("trayShort_" + verdict.rawValue)).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer()
                if count == 0 && settled {
                    Text(library.tr("trayEmpty_" + verdict.rawValue)).font(.callout).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }

            }
            .padding(16)
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(color.opacity(count > 0 ? 0.12 : 0.03)).interactive(), in: .rect(cornerRadius: 24))
        .disabled(count == 0)
        .position(x: rect.midX, y: rect.midY)
        .animation(.snappy, value: count)
        .help(library.tr("trayHint_" + verdict.rawValue))
    }
}

/// A tray opened: its photos with the reason, put back one or all; "Have a look" goes to the quick review.
private struct TrayContents: View {
    @EnvironmentObject var library: LibraryModel
    let verdict: SortVerdict
    let ids: [Int]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(library.tr("tray_" + verdict.rawValue)).font(.title3.weight(.semibold))
            Text(library.tr("trayHint_" + verdict.rawValue)).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 14) {
                    ForEach(ids, id: \.self) { id in
                        if let p = library.photo(id) { cell(p) }
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 460)
            HStack {
                if verdict == .check {
                    Button(library.tr("quickReview")) { close(); library.startReview() }.buttonStyle(.borderedProminent)
                } else {
                    Button(library.tr("putBackAll")) { library.setInAlbum(ids, true) }
                }
                Spacer()
                Button(library.tr("done")) { close() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 560)
    }

    func cell(_ p: Photo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Thumbnail(url: p.fileURL, side: 260).frame(height: 104).clipShape(.rect(cornerRadius: 8))
            Text(reason(p)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if verdict == .check {
                HStack(spacing: 6) {
                    Button(library.tr("itsFine")) { library.mark([p], ["keep": .bool(true)], name: library.tr("keep")) }
                    Button(library.tr("leaveOut")) { library.setInAlbum([p.id], false) }
                }
                .controlSize(.small)
            } else {
                Button(library.tr("putBack")) { library.setInAlbum([p.id], true) }.controlSize(.small)
            }
        }
    }

    func reason(_ p: Photo) -> String {
        guard let code = sortReason(p) else { return "" }
        return code == "leftOut" ? library.tr("reason_leftOut") : library.trOr("why2_" + code, code)
    }
}

/// On the album home: watch the sorting while it runs, or play it again afterwards.
struct StageLink: View {
    @EnvironmentObject var library: LibraryModel
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack").foregroundStyle(.secondary)
            Text(library.tr("stageLinkText")).foregroundStyle(.secondary)
            Spacer()
            Button(library.analysing ? library.tr("stageWatch") : library.tr("stageReplay")) {
                library.showSorting(replay: !library.analysing)
            }
            .buttonStyle(.link)
        }
        .font(.callout)
    }
}
