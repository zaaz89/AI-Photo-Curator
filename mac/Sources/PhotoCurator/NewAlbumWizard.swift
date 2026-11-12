import AppKit
import CuratorCore
import SwiftUI
import UniformTypeIdentifiers

/// New Album: drop the folders, the app proposes who each belongs to and a name, then it starts.
struct NewAlbumWizard: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [Row] = []
    @State private var rejected: [Suggestion.Rejected] = []
    @State private var name = ""
    @State private var nameEdited = false
    @State private var reading = false
    @State private var creating = false
    @State private var dropTargeted = false

    struct Row: Identifiable, Hashable {
        let suggestion: FolderSuggestion
        var owner: String
        var id: String { suggestion.path }
    }

    var canCreate: Bool {
        !folders.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && folders.allSatisfy { !$0.owner.trimmingCharacters(in: .whitespaces).isEmpty } && !creating && !reading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AIRing(symbol: "sparkles", size: 40, spinning: reading || creating)
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.tr("newAlbumTitle")).font(.title2.weight(.bold))
                    Text(library.tr("newAlbumLead")).foregroundStyle(.secondary)
                }
            }

            dropZone

            if !folders.isEmpty {
                VStack(spacing: 0) {
                    ForEach($folders) { $row in
                        FolderRow(row: $row) { folders.removeAll { $0.id == row.id }; refreshName() }
                        if row.id != folders.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(.fill.quaternary, in: .rect(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ForEach(rejected, id: \.self) { r in
                Label("\(URL(fileURLWithPath: r.path).lastPathComponent): \(library.trOr("problem_" + r.problem, r.problem))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }

            if !folders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(library.tr("albumName")).font(.headline)
                    TextField(library.tr("albumNamePrompt"), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .onChange(of: name) { _, _ in nameEdited = true }
                    Text(library.tr("albumNameHint")).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(library.tr("readOnlyNote")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(library.tr("cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button { create() } label: {
                    if creating { ProgressView().controlSize(.small) } else { Text(library.tr("createAlbum")) }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 640)
        .animation(.spring(duration: 0.35), value: folders)
    }

    var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: reading ? "sparkle.magnifyingglass" : "folder.badge.plus")
                .font(.system(size: 34, weight: .light))
                .symbolEffect(.pulse, isActive: reading)
                .foregroundStyle(.tint)
            Text(library.tr(reading ? "readingFolders" : "dropFolders")).font(.headline)
            Button(library.tr("chooseFolders")) { choose() }.buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, minHeight: folders.isEmpty ? 190 : 120)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .foregroundStyle(dropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .background(dropTargeted ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 16))
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await add(urls: urls) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(library.tr("dropFolders"))
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = library.tr("addFolders")
        panel.message = library.tr("chooseFoldersMessage")
        if panel.runModal() == .OK { Task { await add(urls: panel.urls) } }
    }

    func add(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        reading = true
        defer { reading = false }
        let paths = folders.map(\.suggestion.path) + urls.map(\.path)
        do {
            let s = try await library.api.suggest(paths: paths)
            let owners = Dictionary(folders.map { ($0.id, $0.owner) }, uniquingKeysWith: { a, _ in a })
            folders = s.folders.map { Row(suggestion: $0, owner: owners[$0.path] ?? $0.owner) }
            rejected = s.rejected
            if !nameEdited || name.isEmpty {
                name = albumName(place: s.album.place, start: s.album.start, end: s.album.end, lang: library.lang)
                nameEdited = false
            }
        } catch { library.message = library.describe(error) }
    }

    func refreshName() { if folders.isEmpty { name = ""; nameEdited = false } }

    func create() {
        creating = true
        let list = folders.map { (path: $0.suggestion.path, owner: $0.owner.trimmingCharacters(in: .whitespaces),
                                  devices: $0.suggestion.devices.map(\.name)) }
        Task {
            if await library.createAlbum(name: name.trimmingCharacters(in: .whitespaces), folders: list) { dismiss() }
            creating = false
        }
    }
}

struct FolderRow: View {
    @EnvironmentObject var library: LibraryModel
    @Binding var row: NewAlbumWizard.Row
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: row.suggestion.path).lastPathComponent).font(.headline).lineLimit(1)
                Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                TextField(library.tr("whosePhotos"), text: $row.owner)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                if let from = row.suggestion.ownerFrom, row.owner == row.suggestion.owner {
                    Text(library.tr("ownerFrom_" + from)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Button(action: remove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help(library.tr("removeFolder"))
                .accessibilityLabel(library.tr("removeFolder"))
        }
        .padding(.vertical, 10)
    }

    var details: String {
        var parts = [Strings.photos(row.suggestion.count, library.lang)]
        if let d = row.suggestion.devices.first { parts.append(d.name) }
        if let a = row.suggestion.start {
            parts.append(albumName(place: nil, start: a, end: row.suggestion.end, lang: library.lang))
        }
        return parts.joined(separator: " · ")
    }
}
