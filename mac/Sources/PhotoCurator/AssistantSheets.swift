import AppKit
import CuratorCore
import SwiftUI

// MARK: best of each moment

/// One moment at a time: the frames side by side, the recommendation with its reasons.
/// ← → look at the frames, Return keeps the highlighted frame and goes on.
struct MomentsSheet: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [MomentGroup] = []
    @State private var index = 0
    @State private var frame = 0
    @State private var loaded = false
    @FocusState private var focused: Bool

    var current: MomentGroup? { groups.indices.contains(index) ? groups[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.tr("cardMoments")).font(.title2.weight(.bold))
                    if current != nil {
                        Text(String(format: library.tr("momentOf"), min(index + 1, groups.count), groups.count))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer()
                Button(library.tr("done")) { finish() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            if let g = current {
                Text(reasons(g)).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                HStack(spacing: 14) {
                    ForEach(Array(g.members.enumerated()), id: \.element.id) { i, m in
                        FrameCard(member: m, photo: library.photos.first { $0.id == m.id },
                                  recommended: m.id == g.keeperId, ownChoice: g.chosenByOwner, highlighted: i == frame)
                            .onTapGesture { frame = i }
                            .onTapGesture(count: 2) { frame = i; keepAndNext() }
                    }
                }
                .padding(20)
                .frame(maxHeight: .infinity)
                .id(g.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
                            .buttonStyle(.glass).help("←")
                        Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
                            .buttonStyle(.glass).help("→")
                        Button { keepAndNext() } label: {
                            Label(library.tr(frame == recommendedIndex(g) ? "keepRecommended" : "keepThisOne"), systemImage: "checkmark")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.glassProminent).controlSize(.large)
                        Button(library.tr("acceptRest")) { acceptRest() }.buttonStyle(.glass).controlSize(.large)
                    }
                }
                .padding(.bottom, 22)
            } else if loaded {
                ContentUnavailableView(library.tr("momentsAllDone"), systemImage: "checkmark.circle",
                                       description: Text(library.tr("momentsAllDoneText")))
                    .frame(maxHeight: .infinity)
                Button(library.tr("done")) { finish() }.buttonStyle(.glassProminent).controlSize(.large).padding(.bottom, 22)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        .animation(.spring(duration: 0.4), value: index)
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(.escape) { finish(); return .handled }
        .onExitCommand { finish() }
        .onKeyPress(.leftArrow) { move(-1); return .handled }
        .onKeyPress(.rightArrow) { move(1); return .handled }
        .onKeyPress(.return) { keepAndNext(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "kK")) { _ in keepAndNext(); return .handled }
        .task { await load() }
    }

    func recommendedIndex(_ g: MomentGroup) -> Int { g.members.firstIndex { $0.id == g.keeperId } ?? 0 }

    func load() async {
        guard let trip = library.tripId else { return }
        let all = ((try? await library.api.moments(trip: trip)) ?? []).filter { !library.reviewedMoments.contains($0.id) }
        // Moments that need the owner first, then the ones decided automatically.
        groups = all.filter { !$0.clear } + all.filter(\.clear)
        index = 0
        frame = groups.first.map(recommendedIndex) ?? 0
        loaded = true
        focused = true
    }

    func move(_ d: Int) {
        guard let g = current else { return }
        frame = max(0, min(g.members.count - 1, frame + d))
    }

    func keepAndNext() {
        guard let g = current, let trip = library.tripId else { return }
        _ = trip
        let chosen = g.members[frame].id
        if chosen != g.keeperId || !g.chosenByOwner { library.keep(group: g.id, photo: chosen) }
        else { library.reviewedMoments.insert(g.id) }
        next()
    }

    func next() {
        index += 1
        frame = current.map(recommendedIndex) ?? 0
        if current == nil { library.markStep("duplicates") }
    }

    /// The rest keeps the recommendation (nothing to write: the engine already uses it).
    func acceptRest() {
        groups[index...].forEach { library.reviewedMoments.insert($0.id) }
        index = groups.count
        library.markStep("duplicates")
    }

    func finish() {
        Task { await library.reload() }
        dismiss()
    }

    func reasons(_ g: MomentGroup) -> String {
        let r = (g.reasons.keeper ?? []).filter { !$0.hasPrefix("a recommendation") }
        let text = r.map { library.trOr("why_" + $0, $0) }
        return (g.clear ? library.tr("decidedBecause") : library.tr("suggestedBecause")) + " " + text.joined(separator: ", ")
    }
}

struct FrameCard: View {
    @EnvironmentObject var library: LibraryModel
    let member: MomentGroup.Member
    let photo: Photo?
    let recommended: Bool
    var ownChoice = false
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumbnail(url: URL(fileURLWithPath: member.path), side: 1024, fill: false)
                .aspectRatio(CGFloat(member.width ?? 3) / CGFloat(max(member.height ?? 2, 1)), contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if recommended {
                        // A plain material, not Liquid Glass: glass never sits on photos.
                        Label(library.tr(ownChoice ? "yourChoice" : "recommended"), systemImage: ownChoice ? "hand.thumbsup" : "sparkles")
                            .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: .capsule).padding(8)
                    }
                    if member.rejected == true {
                        Text(library.tr("leftOut")).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.orange, in: .capsule).foregroundStyle(.white).padding(8)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: highlighted ? 4 : 0)
                }
                .scaleEffect(highlighted ? 1 : 0.97)
                .animation(.snappy(duration: 0.2), value: highlighted)
            HStack(spacing: 6) {
                Text(String((member.localTime ?? "").dropFirst(11).prefix(8))).monospacedDigit().font(.callout.weight(.medium))
                Text(member.owner ?? "").foregroundStyle(.secondary).font(.callout)
            }
            HStack(spacing: 6) {
                if let f = photo?.faces {
                    tag(f.eyesClosed > 0 ? "eyesClosed" : "eyesOpen", warn: f.eyesClosed > 0)
                    tag(f.lookingAway > 0 ? "lookingAway" : "lookingAtCamera", warn: f.lookingAway > 0)
                }
                if let t = photo?.focus?.tier { tag("tier_" + t, warn: t != "sharp") }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    func tag(_ key: String, warn: Bool) -> some View {
        Text(library.tr(key)).font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((warn ? Color.orange : Color.green).opacity(0.18), in: .capsule)
            .foregroundStyle(warn ? .orange : .green)
    }
}

// MARK: clocks

struct ClocksSheet: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var clocks: [DeviceClock] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(library.tr("cardClocks")).font(.title2.weight(.bold))
            Text(library.tr("clocksLead")).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(clocks) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(c.owner) · \(c.device)").font(.headline)
                            Text(note(c)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if c.pending, let s = c.suggestedS {
                            Button(String(format: library.tr("applyShift"), shift(s))) { act(c, "accept") }.buttonStyle(.glassProminent)
                            Button(library.tr("reject")) { act(c, "reject") }.buttonStyle(.glass)
                        } else if let a = c.appliedS, a != 0 {
                            Button(library.tr("undo")) { act(c, "reset") }.buttonStyle(.glass)
                        }
                    }
                    .padding(.vertical, 12)
                    if c.id != clocks.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            HStack {
                Spacer()
                Button(library.tr("done")) { library.markStep("times"); dismiss() }
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
        .task { await load() }
    }

    func load() async { if let t = library.tripId { clocks = (try? await library.api.clocks(trip: t)) ?? [] } }
    func act(_ c: DeviceClock, _ action: String) {
        guard let t = library.tripId else { return }
        Task { try? await library.api.clock(trip: t, id: c.clockId, action: action); await load(); await library.reload() }
    }
    func shift(_ s: Double) -> String { (s > 0 ? "+" : "") + (abs(s) >= 90 ? String(format: "%.1f min", s / 60) : String(format: "%.0f s", s)) }
    func note(_ c: DeviceClock) -> String {
        if c.status == "reference" { return library.tr("clockReference") }
        if let a = c.appliedS, a != 0 { return String(format: library.tr("clockShifted"), shift(a)) }
        if c.pending { return c.evidence?.note ?? "" }
        return Strings.photos(c.photos, library.lang) + " · " + library.tr("clockNoChange")
    }
}

// MARK: export

struct ExportSheet: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var preview: ExportPreview?
    @State private var started = false

    var body: some View {
        let job = library.job
        let exporting = started && job.running
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AIRing(symbol: exporting ? "square.and.arrow.up" : (library.lastExport?.ok == true && started ? "checkmark" : "photo.stack"),
                       size: 48, spinning: exporting, progress: exporting ? job.progress / 100 : nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.tr("cardExport")).font(.title2.weight(.bold))
                    Text(library.tr("exportLead")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let p = preview {
                VStack(alignment: .leading, spacing: 6) {
                    Label(String(format: library.tr("exportCount"), p.files, ByteCountFormatter.string(fromByteCount: Int64(p.bytes), countStyle: .file)),
                          systemImage: "photo.on.rectangle").font(.headline)
                    Label(library.tr("exportMeta"), systemImage: "text.badge.checkmark").foregroundStyle(.secondary)
                    Label(library.tr("exportSafe"), systemImage: "lock.shield").foregroundStyle(.secondary)
                    ForEach((p.warnings ?? [:]).sorted(by: { $0.key < $1.key }), id: \.key) { k, n in
                        Label("\(n) " + library.trOr("warn_" + k, k), systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            if exporting {
                Text(job.status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                ProgressView(value: job.progress, total: 100)
            } else if started, let error = job.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            } else if started, let last = library.lastExport {
                Label(library.tr(last.ok ? "exportFinished" : "exportProblems"),
                      systemImage: last.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(last.ok ? .green : .orange).font(.headline)
            }
            HStack {
                if started, !exporting, let last = library.lastExport {
                    Button(library.tr("showInFinder")) { NSWorkspace.shared.open(URL(fileURLWithPath: last.folder)) }.buttonStyle(.glass)
                }
                Spacer()
                Button(library.tr(started && !exporting ? "done" : "cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                if !started || (!exporting && library.lastExport?.ok != true) {
                    Button(library.tr("chooseAndExport")) { choose() }
                        .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                        .disabled(preview == nil || job.running)
                }
            }
        }
        .padding(24)
        .frame(width: 600)
        .animation(.snappy, value: exporting)
        .task { if let t = library.tripId { preview = try? await library.api.exportPreview(trip: t) } }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = library.tr("exportHere")
        panel.message = library.tr("exportWhere")
        guard panel.runModal() == .OK, let url = panel.url, let t = library.tripId else { return }
        library.clearLastExport()
        Task {
            do { try await library.api.startExport(trip: t, destination: url.path); started = true; await library.pollNow() }
            catch { library.message = library.describe(error) }
        }
    }
}
