import CuratorCore
import SwiftUI

// M12d (UX audit #11, section 7 item A): compare two frames of a moment side by side. The left pane is the
// frame in the album (the keeper), the right one a challenger; ← → change the challenger, 1 or 2 picks,
// Z zooms both to 100% on the same spot and a drag in either pane pans both. Keys: `ReviewKeymap` (.compare),
// handled by the quick review that hosts this view.
struct CompareView: View {
    @EnvironmentObject var library: LibraryModel
    let session: CompareSession
    let zoomed: Bool
    @Binding var centre: ZoomPoint
    let pick: (Int) -> Void
    let toggleZoom: () -> Void
    let showKeys: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            HStack(spacing: Space.l) {
                Button(action: close) { Label(library.tr("done"), systemImage: "xmark") }
                    .buttonStyle(.glass)
                Text(String(format: library.tr("compareFrames"), session.frames.count))
                    .font(TypeRole.cardTitle).foregroundStyle(.secondary)
                Spacer()
                Button(action: toggleZoom) {
                    Label(library.tr(zoomed ? "a11yZoomFit" : "zoomToggle"),
                          systemImage: zoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                }
                .buttonStyle(.glass).help(library.tr("keyZoom") + " (Z)")
                Button(action: showKeys) { Image(systemName: "keyboard") }
                    .buttonStyle(.glass).help(library.tr("reviewKeys"))
                    .accessibilityLabel(library.tr("reviewKeys"))
            }
            HStack(alignment: .top, spacing: Space.l) {
                pane(session.keeper, side: 1)
                if let c = session.challenger {
                    pane(c, side: 2)
                } else {
                    Text(library.tr("compareOnlyOne")).font(TypeRole.supporting).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    func pane(_ id: Int, side: Int) -> some View {
        if let p = library.photo(id) {
            VStack(spacing: Space.m) {
                ZoomablePhoto(url: p.fileURL, ratio: Double(p.width ?? 3) / Double(max(p.height ?? 2, 1)),
                              pixelWidth: p.width, zoomed: zoomed, centre: $centre)
                    .id(id)                         // another challenger: its own original, not the last one's
                    .transition(.opacity)
                    .overlay(alignment: .topLeading) { badge(side: side).padding(Space.l) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(paneLabel(p, side: side))
                    .accessibilityValue(library.tr(zoomed ? "a11yZoomActual" : "a11yZoomFit"))
                    .accessibilityAddTraits(.isImage)
                HStack(spacing: Space.m) {
                    Text("\(p.clock) · \(p.filename)").font(TypeRole.supporting).foregroundStyle(.secondary)
                        .monospacedDigit().lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button { pick(side) } label: {
                        Label(String(format: library.tr("comparePick"), side),
                              systemImage: side == 1 ? "checkmark.circle" : "arrow.left.circle")
                    }
                    .buttonStyle(.glass).controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .motionAnimation(.fade, value: id)
        }
    }

    @ViewBuilder
    func badge(side: Int) -> some View {
        if side == 1 {
            Label(library.tr("chosenForAlbum"), systemImage: "checkmark.circle.fill")
                .font(TypeRole.label.weight(.semibold))
                .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
                .background(StatusColor.kept, in: .capsule)
                .foregroundStyle(StatusColor.onLook)
        } else {
            let pos = session.position
            Text(String(format: library.tr("compareChallenger"), pos.index, pos.count))
                .font(TypeRole.label.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
                .background(.ultraThinMaterial, in: .capsule)
        }
    }

    func paneLabel(_ p: Photo, side: Int) -> String {
        let base = gridTileAccessibilityLabel(p, library.lang)
        if side == 1 { return String(format: library.tr("compareLeftLabel"), base) }
        let pos = session.position
        return String(format: library.tr("compareRightLabel"), pos.index, pos.count, base)
    }
}
