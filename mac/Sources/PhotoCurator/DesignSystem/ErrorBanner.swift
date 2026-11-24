import SwiftUI
import CuratorCore

// The error banner (M12e, UX audit #8): one component for every error the owner sees. A human sentence (from
// `humanError`, CuratorCore), the raw text behind a "Details" disclosure, Try Again when there is an action to
// repeat, and Dismiss. It stays until dismissed (no timer: an error must not vanish before it is read), and it
// is announced to VoiceOver when it appears.

/// An error on screen, with the action that failed (for Try Again).
struct ErrorBannerInfo: Identifiable, Equatable {
    let id = UUID()
    let error: HumanError
    let retry: (@MainActor () -> Void)?

    init(error: HumanError, retry: (@MainActor () -> Void)? = nil) {
        self.error = error
        self.retry = retry
    }

    static func == (a: ErrorBannerInfo, b: ErrorBannerInfo) -> Bool { a.id == b.id }
}

struct ErrorBanner: View {
    @EnvironmentObject var library: LibraryModel
    let error: HumanError
    var retry: (@MainActor () -> Void)?
    var dismiss: (@MainActor () -> Void)?
    /// Floating over a page (glass, allowed for floating controls) or inline in a card (tinted).
    var floating = true
    @State private var showDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.l) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StatusColor.warning)
                .font(TypeRole.cardTitle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(error.message)
                    .font(TypeRole.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                if !error.details.isEmpty && error.details != error.message {
                    DisclosureGroup(isExpanded: $showDetails) {
                        Text(error.details)
                            .font(TypeRole.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(library.tr("details")).font(TypeRole.caption)
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            if let retry {
                Button(library.tr("tryAgain")) { dismiss?(); retry() }
                    .buttonStyle(.glass)
            }
            if let dismiss {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(library.tr("dismiss"))
                    .help(library.tr("dismiss"))
            }
        }
        .padding(.horizontal, Space.xl).padding(.vertical, Space.l)
        .modifier(BannerBackground(floating: floating))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: library.tr("errorA11y"), error.message))
        .task(id: error) {
            AccessibilityNotification.Announcement(String(format: library.tr("errorA11y"), error.message)).post()
        }
    }
}

private struct BannerBackground: ViewModifier {
    let floating: Bool
    func body(content: Content) -> some View {
        if floating {
            content.glassEffect(.regular, in: .rect(cornerRadius: Radius.large))
        } else {
            content.background(StatusColor.warning.opacity(0.12), in: .rect(cornerRadius: Radius.medium))
        }
    }
}
