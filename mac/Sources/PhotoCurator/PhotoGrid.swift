import AppKit
import CuratorCore
import SwiftUI

struct PhotoGrid: View {
    @EnvironmentObject var library: LibraryModel
    @FocusState private var focused: Bool
    @State private var columns = 4
    private let spacing: CGFloat = 4
    private let padding: CGFloat = 16

    var body: some View {
        let sections = library.visibleSections
        GeometryReader { geo in
            ScrollViewReader { scroller in
                ScrollView {
                    if sections.isEmpty {
                        emptyState.frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                                SwiftUI.Section {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                                              spacing: spacing) {
                                        ForEach(section.photos) { photo in
                                            PhotoTile(photo: photo, selected: library.selection.contains(photo.id),
                                                      isCursor: library.flat.indices.contains(library.cursor) && library.flat[library.cursor].id == photo.id,
                                                      side: library.tileSize)
                                                .frame(height: library.tileSize)
                                                .id(photo.id)
                                                .onTapGesture { tap(photo) }
                                                .contextMenu { TileMenu(photo: photo) }
                                        }
                                    }
                                    .padding(.horizontal, padding)
                                } header: {
                                    SectionHeader(section: section,
                                                  continuesDay: index > 0 && !section.day.isEmpty && sections[index - 1].day == section.day)
                                }
                            }
                        }
                        .padding(.bottom, 90)
                    }
                }
                .onChange(of: library.cursor) { _, i in
                    let list = library.flat
                    guard list.indices.contains(i) else { return }
                    withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(list[i].id) }
                    QuickLook.shared.follow(i)
                }
            }
            .onAppear { columns = columnCount(geo.size.width) }
            .onChange(of: geo.size.width) { _, w in columns = columnCount(w) }
            .onChange(of: library.tileSize) { _, _ in columns = columnCount(geo.size.width) }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        // The grid takes the keyboard when the window opens and after every sidebar choice,
        // so F, X, arrows and Space act on photos (as in Photos).
        .task(id: library.destination) {
            try? await Task.sleep(for: .milliseconds(120))
            focused = true
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let dir: Direction = switch press.key {
            case .leftArrow: .left
            case .rightArrow: .right
            case .upArrow: .up
            default: .down
            }
            library.moveCursor(dir, columns: columns, extend: press.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(.space) {
            QuickLook.shared.toggle(library.flat, at: max(library.cursor, 0))
            return .handled
        }
        .onKeyPress(.escape) { library.clearSelection(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "0123"), phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            library.setFocus(["1": "sharp", "2": "soft", "3": "blurry"][press.characters])
            return .handled
        }
    }

    func columnCount(_ width: CGFloat) -> Int {
        max(1, Int((width - 2 * padding + spacing) / (library.tileSize + spacing)))
    }

    func tap(_ photo: Photo) {
        focused = true
        library.click(photo, modifiers: NSEvent.modifierFlags)
        if NSApp.currentEvent?.clickCount == 2 {
            QuickLook.shared.toggle(library.flat, at: library.cursor)
        }
    }

    @ViewBuilder var emptyState: some View {
        if library.loading {
            ProgressView()
        } else if library.trips.isEmpty {
            ContentUnavailableView(library.tr("noTripsTitle"), systemImage: "suitcase", description: Text(library.tr("noTripsText")))
        } else if library.destination == .search {
            ContentUnavailableView.search(text: library.searchResult?.query ?? library.searchText)
        } else {
            ContentUnavailableView(library.tr("nothingHere"), systemImage: "photo.on.rectangle.angled",
                                   description: Text(library.tr("nothingHereText")))
        }
    }
}

struct SectionHeader: View {
    @EnvironmentObject var library: LibraryModel
    let section: PhotoSection
    var continuesDay = false           // another event of the same day: show only the event, smaller
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !continuesDay { Text(title).font(.title2.weight(.bold)) }
            if let e = section.eventName, !e.isEmpty {
                Text(e).font(continuesDay ? .headline : .title3).foregroundStyle(continuesDay ? .primary : .secondary)
            }
            Spacer()
            Text(Strings.photos(section.photos.count, library.lang))
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, continuesDay ? 10 : 16).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .accessibilityAddTraits(.isHeader)
    }
    var title: String {
        if !section.day.isEmpty { return formatDay(section.day, library.lang, style: .long) }
        if section.id == "results" { return library.tr("searchResults") }
        if section.title.isEmpty {
            return library.tr(library.sort == .place ? "noPlace" : library.sort == .quality ? "notRated" : "unknown")
        }
        return library.sort == .quality ? library.tr("tier_" + section.title) : section.title
    }
}

struct PhotoTile: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let photo: Photo
    let selected: Bool
    let isCursor: Bool
    let side: CGFloat

    var body: some View {
        Thumbnail(url: photo.fileURL, side: side)
            .opacity(photo.rejected && library.destination != .leftOut ? 0.4 : 1)
            .overlay { if library.isPending(photo) { Shimmer(reduceMotion: reduceMotion) } }
            .clipShape(.rect(cornerRadius: 8))
            .overlay(alignment: .topLeading) { badges.padding(7) }
            .overlay(alignment: .topTrailing) {
                if photo.favorite {
                    Image(systemName: "heart.fill").foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 3).padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if photo.isVideo {
                    Label(duration, systemImage: "play.fill").font(.caption2.weight(.semibold)).labelStyle(.titleAndIcon)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: .capsule).foregroundStyle(.white).padding(7)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: selected ? 4 : (isCursor ? 2 : 0))
            }
            .animation(.snappy(duration: 0.2), value: photo.favorite)
            .animation(.snappy(duration: 0.15), value: selected)
            .contentShape(.rect)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { library.click(photo, modifiers: []) }
    }

    @ViewBuilder var badges: some View {
        HStack(spacing: 4) {
            if let tier = photo.focus?.tier, tier != "sharp", !photo.isVideo {
                Text(library.tr("tier_" + tier)).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(tier == "blurry" ? Color.red : Color.orange, in: .capsule).foregroundStyle(.white)
            }
            if (photo.faces?.eyesClosed ?? 0) > 0 {
                Image(systemName: "eye.slash.fill").font(.caption2).padding(4)
                    .background(.orange, in: .circle).foregroundStyle(.white)
                    .help(library.tr("eyesClosed"))
            }
            if photo.duplicate?.keeper == false {
                Image(systemName: "square.stack.3d.up.fill").font(.caption2).padding(4)
                    .background(.black.opacity(0.55), in: .circle).foregroundStyle(.white)
                    .help(library.tr("extraFrame"))
            }
        }
    }

    var duration: String {
        guard let d = photo.duration else { return "" }
        return String(format: "%d:%02d", Int(d) / 60, Int(d.rounded()) % 60)
    }

    var accessibilityText: String {
        var parts = [photo.filename, photo.clock, photo.owner]
        if photo.favorite { parts.append(library.tr("favourite")) }
        if photo.rejected { parts.append(library.tr("leftOut")) }
        if photo.isVideo { parts.append(library.tr("video")) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// A light sweep over photos the engine is still analysing.
struct Shimmer: View {
    let reduceMotion: Bool
    var body: some View {
        if reduceMotion {
            Rectangle().fill(.white.opacity(0.12))
        } else {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: (g.size.width * 1.6) * t - g.size.width * 0.6)
                        .blendMode(.plusLighter)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct TileMenu: View {
    @EnvironmentObject var library: LibraryModel
    let photo: Photo
    var body: some View {
        Button(library.tr(photo.favorite ? "unfavourite" : "favourite")) { ensure(); library.toggleFavourite() }
        Button(library.tr(photo.rejected ? "keep" : "leaveOut")) { ensure(); library.toggleLeaveOut() }
        Divider()
        Button(library.tr("quickLook")) { ensure(); QuickLook.shared.toggle(library.flat, at: library.cursor) }
        Button(library.tr("showInFinder")) { NSWorkspace.shared.activateFileViewerSelecting([photo.fileURL]) }
    }
    /// A right-click on a photo outside the selection acts on that photo only.
    func ensure() { if !library.selection.contains(photo.id) { library.click(photo, modifiers: []) } }
}
