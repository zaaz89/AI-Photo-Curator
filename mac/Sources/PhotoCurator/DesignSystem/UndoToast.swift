import SwiftUI
import CuratorCore

// The undo toast (M12c): one reusable confirmation for reversible actions ("Put back 3 photos · Undo").
// It floats over the page (a floating control, so glass is allowed), is announced to VoiceOver, and leaves
// after a few seconds. Undo goes through the window's undo manager (`LibraryModel.undoLast`), the same one
// Cmd+Z uses, so both always agree.

struct UndoToastInfo: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

struct UndoToast: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Seconds the toast stays; long enough to read and reach the button.
    static let seconds = 6

    var body: some View {
        ZStack {
            if let t = library.undoToast {
                HStack(spacing: Space.l) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(StatusColor.kept)
                        .accessibilityHidden(true)
                    Text(t.text).font(TypeRole.supporting).lineLimit(2)
                    Button(library.tr("undo")) { library.undoLast() }
                        .buttonStyle(.borderless)
                        .fontWeight(.semibold)
                    Button { dismiss(t) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(library.tr("dismiss"))
                }
                .padding(.horizontal, Space.xl).padding(.vertical, Space.m)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, Space.xl)
                .motionTransition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .task(id: t.id) {
                    AccessibilityNotification.Announcement(t.text).post()
                    try? await Task.sleep(for: .seconds(Self.seconds))
                    dismiss(t)
                }
            }
        }
        .animation(Motion.animation(.arrive, reduceMotion: reduceMotion), value: library.undoToast)
    }

    private func dismiss(_ t: UndoToastInfo) {
        guard library.undoToast?.id == t.id else { return }
        library.undoToast = nil
    }
}
