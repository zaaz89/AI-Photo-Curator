import CuratorCore
import SwiftUI

// M12f first run (roadmap M18.3): three short screens, shown once (`FirstRun.seenKey`), skippable, keyboard
// friendly (← → move, Return continues, Esc skips). No permissions are asked here: folders are chosen when an
// album is made. Pages slide under normal motion and cross-fade under Reduce Motion.

struct FirstRunView: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @Namespace private var dots
    @State private var forward = true
    /// Set when the owner leaves through "Create an Album" on the last page (MainWindow opens the wizard after the
    /// sheet has closed).
    @Binding var wantsNewAlbum: Bool

    init(wantsNewAlbum: Binding<Bool>) { _wantsNewAlbum = wantsNewAlbum }

    var page: FirstRunPage { library.firstRunPage ?? .what }

    var body: some View {
        VStack(spacing: Space.xxxl) {
            ZStack {
                content(page)
                    .id(page)
                    .motionTransition(.push(from: forward ? .trailing : .leading))
            }
            .frame(maxWidth: .infinity, minHeight: 330)
            .clipped()

            pageDots
            buttons
        }
        .padding(Space.huge)
        .frame(width: 600)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.rightArrow) { key("right") }
        .onKeyPress(.leftArrow) { key("left") }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: library.tr("firstRunPageA11y"), page.rawValue + 1, FirstRunPage.allCases.count))
    }

    // MARK: navigation

    func key(_ k: String) -> KeyPress.Result {
        guard let p = FirstRun.page(after: k, on: page) else { return .ignored }
        go(p)
        return .handled
    }

    func go(_ p: FirstRunPage) {
        forward = p.rawValue > page.rawValue
        withMotion(.arrive, reduceMotion: reduceMotion) { library.firstRunPage = p }
    }

    func close(newAlbum: Bool) {
        wantsNewAlbum = newAlbum
        library.firstRunPage = nil
    }

    var buttons: some View {
        HStack(spacing: Space.l) {
            Button(library.tr("firstRunSkip")) { close(newAlbum: false) }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            Spacer()
            if let previous = page.previous {
                Button(library.tr("firstRunBack")) { go(previous) }
                    .buttonStyle(.glass).controlSize(.large)
            }
            if let next = page.next {
                Button { go(next) } label: {
                    Label(library.tr("firstRunNext"), systemImage: "arrow.right").labelStyle(TrailingIconLabel())
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                let newAlbum = library.trips.isEmpty
                Button { close(newAlbum: newAlbum) } label: {
                    Label(library.tr(newAlbum ? "firstRunCreate" : "firstRunStart"), systemImage: "sparkles")
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Page dots; the current one is a capsule that slides between them (matchedGeometryEffect, `quick`).
    var pageDots: some View {
        HStack(spacing: Space.m) {
            ForEach(FirstRunPage.allCases, id: \.self) { p in
                ZStack {
                    Circle().fill(.quaternary).frame(width: 8, height: 8)
                    if p == page {
                        Capsule().fill(StatusColor.accent).frame(width: 22, height: 8)
                            .matchedGeometryEffect(id: "current", in: dots)
                    }
                }
                .frame(width: 22, height: 8)
            }
        }
        .motionAnimation(.quick, value: page)
        .accessibilityHidden(true)
    }

    // MARK: pages

    @ViewBuilder func content(_ p: FirstRunPage) -> some View {
        switch p {
        case .what:
            FirstRunPageLayout(title: library.tr("firstRunWhatTitle"), text: library.tr("firstRunWhatText")) {
                WhatItDoes()
            }
        case .safety:
            FirstRunPageLayout(title: library.tr("firstRunSafeTitle"), text: library.tr("firstRunSafeText")) {
                SafetyPromise()
            }
        case .start:
            FirstRunPageLayout(title: library.tr("firstRunStartTitle"), text: library.tr("firstRunStartText")) {
                Image(systemName: "sparkles")
                    .font(TypeRole.heroSymbol)
                    .foregroundStyle(LinearGradient(colors: aiGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolBounce(on: p)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct FirstRunPageLayout<Art: View>: View {
    let title: String
    let text: String
    @ViewBuilder let art: Art

    var body: some View {
        VStack(spacing: Space.xxl) {
            art.frame(height: 120)
            Text(title).font(TypeRole.pageTitle).multilineTextAlignment(.center)
            Text(text).font(TypeRole.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Page 1: photos from everyone → the app sorts → the album. The three symbols arrive one after another
/// (stagger within the motion budget); under Reduce Motion they are simply there.
private struct WhatItDoes: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private let symbols = ["photo.stack", "wand.and.stars", "book.closed"]

    var body: some View {
        HStack(spacing: Space.xl) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { i, s in
                if i > 0 {
                    Image(systemName: "chevron.right").font(TypeRole.cardTitle).foregroundStyle(.tertiary)
                        .opacity(shown ? 1 : 0)
                        .animation(Motion.animation(.arrive, reduceMotion: reduceMotion)?.delay(staggerDelay(i, of: symbols.count)), value: shown)
                }
                Image(systemName: s)
                    .font(TypeRole.heroSymbol)
                    .foregroundStyle(i == 1 ? AnyShapeStyle(StatusColor.accent) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown || reduceMotion ? 0 : Space.m)
                    .animation(Motion.animation(.arrive, reduceMotion: reduceMotion)?.delay(staggerDelay(i, of: symbols.count)), value: shown)
            }
        }
        .accessibilityHidden(true)
        .onAppear { shown = true }
    }
}

/// Page 2: the original stays where it is (locked); a copy travels into the export folder, which bounces.
/// Under Reduce Motion: original, arrow, folder, no travel.
private struct SafetyPromise: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    private let travel: CGFloat = 150

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "photo").font(TypeRole.heroSymbol)
                Image(systemName: "lock.fill").font(TypeRole.cardTitle).foregroundStyle(StatusColor.kept)
                    .symbolBounce(on: copied)
                    .offset(x: Space.m, y: Space.xs)
            }
            .frame(width: 80)
            ZStack {
                Image(systemName: "arrow.right").font(TypeRole.cardTitle).foregroundStyle(.tertiary)
                if !reduceMotion {
                    // The copy: starts on the original, lands in the folder and fades into it.
                    Image(systemName: "photo").font(TypeRole.heroSymbol).foregroundStyle(StatusColor.accent)
                        .scaleEffect(copied ? 0.45 : 0.9)
                        .opacity(copied ? 0 : 0.85)
                        .offset(x: copied ? travel / 2 + Space.xl : -travel / 2 - Space.xl)
                }
            }
            .frame(width: travel)
            Image(systemName: "folder.fill").font(TypeRole.heroSymbol).foregroundStyle(StatusColor.accent)
                .symbolBounce(on: copied)
                .frame(width: 80)
        }
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(250))
            withMotion(.settle, reduceMotion: reduceMotion) { copied = true }
        }
    }
}
