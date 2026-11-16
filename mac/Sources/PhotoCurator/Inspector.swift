import AppKit
import CuratorCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var library: LibraryModel

    var body: some View {
        if let p = library.single {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Button { library.toggleQuickLook() } label: {
                        Thumbnail(url: p.fileURL, side: 520, fill: false)
                            .aspectRatio(CGFloat(p.width ?? 3) / CGFloat(max(p.height ?? 2, 1)), contentMode: .fit)
                            .frame(maxHeight: 280)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .help(library.tr("quickLook"))

                    Text(p.filename).font(.headline).lineLimit(2).textSelection(.enabled)

                    HStack(spacing: 8) {          // the inspector is glass already: plain buttons, no glass on glass
                        Group {
                            Button { library.toggleFavourite() } label: {
                                Label(library.tr(p.favorite ? "unfavourite" : "favourite"), systemImage: p.favorite ? "heart.fill" : "heart")
                            }
                            .buttonStyle(.bordered)
                            .tint(p.favorite ? .pink : nil)
                            Button { library.toggleLeaveOut() } label: {
                                Label(library.tr(p.rejected ? "keep" : "leaveOut"), systemImage: p.rejected ? "arrow.uturn.backward" : "eye.slash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.large)

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                        row("taken", p.day == Photo.undated ? library.tr("noDate") : "\(formatDay(p.day, library.lang, style: .short))  \(p.clock)")
                        row("place", p.place.map { [$0.label, $0.country].compactMap { $0 }.joined(separator: ", ") } ?? library.tr("noGps"))
                        row("person", p.owner)
                        if let d = p.device, !d.isEmpty { row("camera", d) }
                        if let w = p.width, let h = p.height { row("size", "\(w) × \(h)") }
                        if let f = p.faces {
                            GridRow {
                                Text(library.tr("faces")).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(f.faces)")
                                    pill(f.eyesClosed > 0 ? "eyesClosed" : "eyesOpen", warn: f.eyesClosed > 0)
                                    pill(f.lookingAway > 0 ? "lookingAway" : "lookingAtCamera", warn: f.lookingAway > 0)
                                }
                            }
                        }
                    }
                    .font(.callout)

                    if let focus = p.focus, !p.isVideo {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(library.tr("focus")).font(.subheadline.weight(.semibold))
                            Picker(library.tr("focus"), selection: Binding(
                                get: { focus.override ?? "auto" },
                                set: { library.setFocus($0 == "auto" ? nil : $0) })) {
                                Text(library.tr("auto")).tag("auto")
                                Text(library.tr("tier_sharp")).tag("sharp")
                                Text(library.tr("tier_soft")).tag("soft")
                                Text(library.tr("tier_blurry")).tag("blurry")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    if let d = p.ai?.description, !d.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(library.tr("description"), systemImage: "sparkles").font(.subheadline.weight(.semibold))
                            Text(d).foregroundStyle(.secondary).textSelection(.enabled)
                            if let tags = p.ai?.tags, !tags.isEmpty {
                                FlowTags(tags: tags)
                            }
                            Text(library.tr("aiNote")).font(.caption).foregroundStyle(.tertiary)
                        }
                    }

                    if !p.isVideo {
                        Toggle(isOn: Binding(get: { p.wallpaper }, set: { _ in library.toggleWallpaper() })) {
                            Label(library.tr("wallpaper"), systemImage: "iphone")
                        }
                    }
                    if let notes = p.notes, !notes.isEmpty {
                        DisclosureGroup(library.tr("howTime")) {
                            VStack(alignment: .leading, spacing: 4) { ForEach(notes, id: \.self) { Text("• " + $0) } }
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                        }
                        .font(.callout)
                    }
                    Button(library.tr("showInFinder")) { NSWorkspace.shared.activateFileViewerSelecting([p.fileURL]) }
                        .buttonStyle(.link)
                }
                .padding(16)
            }
        } else {
            let n = library.selection.count
            ContentUnavailableView(n > 1 ? "\(n) " + library.tr("selected") : library.tr("noSelection"),
                                   systemImage: n > 1 ? "square.on.square" : "photo",
                                   description: Text(library.tr(n > 1 ? "multiHint" : "noSelectionHint")))
        }
    }

    func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(library.tr(key)).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    func pill(_ key: String, warn: Bool) -> some View {
        Label(library.tr(key), systemImage: warn ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(warn ? .orange : .green)
    }
}

struct FlowTags: View {
    let tags: [String]
    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(tags.prefix(10), id: \.self) { t in
                Text(t).font(.caption).padding(.horizontal, 7).padding(.vertical, 2).background(.fill.tertiary, in: .capsule)
            }
        }
    }
}

/// Lays views out in rows and wraps to the next row when the width is used up.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(subviews, width: proposal.width ?? .infinity).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in rows(subviews, width: bounds.width).origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func rows(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += s.width + spacing; rowHeight = max(rowHeight, s.height); maxX = max(maxX, x - spacing)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}

/// Floating Liquid Glass bar for actions on several selected photos.
struct SelectionBar: View {
    @EnvironmentObject var library: LibraryModel
    @Binding var newEvent: Bool

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Text("\(library.selection.count) " + library.tr("selected"))
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .glassEffect(.regular, in: .capsule)
                HStack(spacing: 2) {
                    action("favourite", "heart") { library.toggleFavourite() }
                    action("leaveOut", "eye.slash") { library.toggleLeaveOut() }
                    action("keep", "arrow.uturn.backward") { library.keep() }
                    Menu {
                        ForEach(library.events) { e in
                            Button("\(formatDay(e.day, library.lang, style: .short)) · \(e.name)") { library.move(toEvent: e.id) }
                        }
                        Divider()
                        Button(library.tr("newEvent")) { newEvent = true }
                    } label: {
                        Label(library.tr("moveToEvent"), systemImage: "calendar.badge.plus").padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    .menuStyle(.button).buttonStyle(.plain).fixedSize()
                }
                .padding(4)
                .glassEffect(.regular.interactive(), in: .capsule)
                Button { library.clearSelection() } label: {
                    Image(systemName: "xmark").font(.callout.weight(.semibold)).frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .help(library.tr("clearSelection"))
                .accessibilityLabel(library.tr("clearSelection"))
            }
        }
    }

    func action(_ key: String, _ icon: String, run: @escaping () -> Void) -> some View {
        Button(action: run) { Label(library.tr(key), systemImage: icon).padding(.horizontal, 10).padding(.vertical, 6) }
            .buttonStyle(.plain)
    }
}

struct NewEventSheet: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(library.tr("newEvent")).font(.title3.weight(.semibold))
            TextField(library.tr("eventName"), text: $name).textFieldStyle(.roundedBorder).frame(width: 320)
                .onSubmit(create)
            HStack {
                Spacer()
                Button(library.tr("cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(library.tr("create"), action: create).keyboardShortcut(.defaultAction).buttonStyle(.glassProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
    func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        library.move(toEvent: nil, newName: n)
        dismiss()
    }
}
