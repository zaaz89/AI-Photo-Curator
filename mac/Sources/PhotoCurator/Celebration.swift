import CuratorCore
import SwiftUI

/// M12f: the completion moment after an export is verified. Plays once per export (`shouldCelebrateExport`): the
/// album cover shrinks into a folder, the folder bounces and the number rolls up, all in one `settle` motion
/// (≤ 0.6 s). It never blocks: the buttons next to it work at once. Reduce Motion: a still check mark and the number.
struct ExportCelebration: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cover: Photo?
    let photos: Int
    /// false: show the end state without motion (already celebrated).
    let play: Bool
    /// Called once when the moment starts, so the caller records it and it never plays twice.
    var played: () -> Void = {}
    @State private var landed = false
    @State private var shown = 0

    init(cover: Photo?, photos: Int, play: Bool, played: @escaping () -> Void = {}) {
        self.cover = cover; self.photos = photos; self.play = play; self.played = played
    }

    var body: some View {
        HStack(spacing: Space.xl) {
            symbol.frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Strings.photos(shown, library.lang))
                    .font(TypeRole.counter)
                    .contentTransition(.numericText(value: Double(shown)))
                Text(library.tr("celebrateText")).font(TypeRole.supporting).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .onAppear(perform: start)
    }

    @ViewBuilder var symbol: some View {
        if reduceMotion {
            Image(systemName: "checkmark.circle.fill").font(TypeRole.heroSymbol).foregroundStyle(StatusColor.kept)
        } else {
            ZStack {
                Image(systemName: "folder.fill").font(TypeRole.heroSymbol).foregroundStyle(StatusColor.accent)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.circle.fill").font(TypeRole.cardTitle)
                            .foregroundStyle(.white, StatusColor.kept)
                            .opacity(landed ? 1 : 0)
                    }
                    .scaleEffect(landed ? 1 : 0.7)
                    .opacity(landed ? 1 : 0.4)
                    .symbolBounce(on: landed)
                if let cover {
                    PhotoCover(photo: cover, side: 260, radius: Radius.medium)
                        .frame(width: 84, height: 84)
                        .scaleEffect(landed ? 0.2 : 1)
                        .offset(y: landed ? Space.s : 0)
                        .opacity(landed ? 0 : 1)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    func start() {
        if play { played() }
        guard play, !reduceMotion else {
            landed = true; shown = photos
            if play { AccessibilityNotification.Announcement(library.tr("celebrateTitle")).post() }
            return
        }
        AccessibilityNotification.Announcement(library.tr("celebrateTitle")).post()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))          // let the card appear first
            withMotion(.settle, reduceMotion: reduceMotion) { landed = true; shown = photos }
        }
    }
}
