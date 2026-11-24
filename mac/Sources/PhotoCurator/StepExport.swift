import AppKit
import CuratorCore
import SwiftUI

/// Step 4: what leaves the Mac, as copies. Three ways (the whole album for Google Photos, the best few
/// to share, folders for an archive), a preview of exactly those photos, then the copy with progress.
struct StepExport: View {
    @EnvironmentObject var library: LibraryModel
    @State private var choice = ExportChoice()
    @State private var preview: ExportPreview?
    @State private var loading = false
    @State private var started = false
    /// Why the preview could not be loaded (M12e, #20): shown with Try Again instead of a spinner forever.
    @State private var previewError: HumanError?
    @State private var previewAttempt = 0
    /// The owner pressed Cancel during this export.
    @State private var cancelled = false

    var body: some View {
        StepPage(step: .export, lead: library.tr("lead_export"), status: status) {
            VStack(alignment: .leading, spacing: 28) {
                choices
                if choice.kind == .best { bestOptions }
                if choice.kind == .archive { archiveOptions }
                previewSection
                runSection
            }
        }
        .task(id: "\(library.tripId ?? "")\(choice.kind.rawValue)\(choice.bestCount)\(choice.folders)\(choice.template)\(library.loadedTripId ?? "")\(previewAttempt)") {
            await loadPreview()
        }
    }

    var status: String {
        guard let p = preview else { return library.tr("preparing") }
        return Strings.photos(p.photoIds.count, library.lang) + " · " + ByteCountFormatter.string(fromByteCount: Int64(p.bytes), countStyle: .file)
    }

    // MARK: the three ways

    var choices: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: ExportKind.allCases.count), spacing: 16) {
            ForEach(ExportKind.allCases) { k in
                Button { withMotion(.quick) { choice.kind = k } } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: icon(k)).font(.title2).foregroundStyle(choice.kind == k ? Color.green : .secondary)
                            Spacer()
                            Image(systemName: choice.kind == k ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(choice.kind == k ? Color.green : Color.secondary.opacity(0.5))
                        }
                        Text(library.tr("exportKind_" + k.rawValue)).font(.title3.weight(.semibold))
                        Text(library.tr("exportKindText_" + k.rawValue)).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(18).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .card(hover: true, highlight: choice.kind == k ? .green : nil)
                .accessibilityAddTraits(choice.kind == k ? .isSelected : [])
            }
        }
    }

    func icon(_ k: ExportKind) -> String {
        switch k {
        case .googlePhotos: "photo.stack"
        case .best: "star.square.on.square"
        case .archive: "folder"
        }
    }

    var bestOptions: some View {
        HStack(spacing: 14) {
            Text(library.tr("bestHowMany")).font(.headline)
            Stepper(value: $choice.bestCount, in: 5...200, step: 5) {
                Text("\(choice.bestCount)").font(.title3.weight(.semibold)).monospacedDigit().frame(minWidth: 40)
            }
            Text(library.tr("bestHowManyText")).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16).card()
    }

    var archiveOptions: some View {
        HStack(spacing: 24) {
            Picker(library.tr("archiveFolders"), selection: $choice.folders) {
                ForEach(["day", "event", "date", "place", "flat"], id: \.self) { Text(library.tr("folders_" + $0)).tag($0) }
            }
            .frame(maxWidth: 300)
            Picker(library.tr("archiveNames"), selection: $choice.template) {
                ForEach(["default", "place", "trip", "original"], id: \.self) { Text(library.tr("names_" + $0)).tag($0) }
            }
            .frame(maxWidth: 360)
            Spacer()
        }
        .padding(16).card()
    }

    // MARK: preview

    var previewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let p = preview {
                let ids = p.photoIds
                SectionTitle(title: String(format: library.tr("previewTitle"), Strings.photos(ids.count, library.lang)),
                             detail: previewDetail(p))
                let shown = ids.prefix(30).compactMap(library.photo)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(shown) { ph in PhotoCover(photo: ph, side: 260, radius: 10).frame(height: 90) }
                    if ids.count > shown.count {
                        Text("+\(ids.count - shown.count)").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 90).background(.fill.quaternary, in: .rect(cornerRadius: 10))
                    }
                }
                .opacity(loading ? 0.5 : 1)
                let notes = (p.warnings ?? [:]).filter { $0.value > 0 }.sorted { $0.key < $1.key }
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(notes, id: \.key) { k, n in
                            Label("\(n) " + library.trOr("warn_" + k, k), systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let e = previewError {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(library.tr("previewFailed")).font(TypeRole.cardTitle)
                    ErrorBanner(error: e, retry: { previewAttempt += 1 }, floating: false)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(20)
        .card()
    }

    func previewDetail(_ p: ExportPreview) -> String {
        var parts = [ByteCountFormatter.string(fromByteCount: Int64(p.bytes), countStyle: .file)]
        if p.files != p.photoIds.count { parts.append(String(format: library.tr("pairedFiles"), p.files - p.photoIds.count)) }
        if let f = p.foldersCount, choice.kind == .archive { parts.append(String(format: library.tr("foldersCount"), f)) }
        if p.writesMetadata == true { parts.append(library.tr("withTimePlace")) }
        return parts.joined(separator: " · ")
    }

    // MARK: run

    @ViewBuilder var runSection: some View {
        let job = library.job
        let exporting = started && job.running && job.kind == "export"
        VStack(alignment: .leading, spacing: 14) {
            Label(library.tr("exportSafe"), systemImage: "lock.shield").foregroundStyle(.secondary)
            if exporting {
                HStack(spacing: 14) {
                    AIRing(symbol: "square.and.arrow.up", size: 44, spinning: true, progress: job.progress / 100)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(library.tr("exporting")).font(.headline)
                        Text(job.status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    // Cancel next to the progress (M12e, #20); files already copied stay, nothing else changes.
                    Button(library.tr("cancelExport"), role: .cancel) { cancelled = true; library.stopJob() }
                        .buttonStyle(.glass)
                        .disabled(cancelled)
                }
            } else if started && cancelled {
                Label(library.tr("exportCancelled"), systemImage: "xmark.circle")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if started, let error = job.error {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(library.tr("exportFailed")).font(TypeRole.cardTitle)
                    ErrorBanner(error: humanError(engineText: error, library.lang), retry: { choose() }, floating: false)
                }
            } else if started, let last = library.lastExport {
                HStack(spacing: 12) {
                    Label(library.tr(last.ok ? "exportFinished" : "exportProblems"),
                          systemImage: last.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(last.ok ? .green : .orange).font(.headline)
                    Spacer()
                    Button(library.tr("showInFinder")) { NSWorkspace.shared.open(URL(fileURLWithPath: last.folder)) }.buttonStyle(.glass)
                    if choice.kind == .googlePhotos {
                        Button(library.tr("openGooglePhotos")) { NSWorkspace.shared.open(URL(string: "https://photos.google.com/")!) }
                            .buttonStyle(.glass)
                    }
                }
                if last.ok { Text(library.tr("afterExport")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            if !exporting {
                Button { choose() } label: {
                    Label(library.tr("chooseAndExport"), systemImage: "square.and.arrow.up").padding(.horizontal, 10)
                }
                .buttonStyle(.glassProminent).controlSize(.extraLarge).tint(.green)
                .disabled(preview == nil || job.running || (preview?.files ?? 0) == 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .motionAnimation(.settle, value: exporting)
    }

    func loadPreview() async {
        guard let t = library.tripId else { return }
        loading = true
        defer { loading = false }
        do {
            preview = try await library.api.exportPreview(trip: t, choice: choice)
            previewError = nil
        } catch is CancellationError {
            return                                          // a newer choice replaced this request
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            preview = nil                                   // never a stale preview next to the error
            previewError = humanError(error, library.lang)
        }
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
        cancelled = false
        let c = choice
        Task {
            do { try await library.api.startExport(trip: t, destination: url.path, choice: c); started = true; await library.pollNow() }
            catch { library.report(error) { choose() } }
        }
    }
}
