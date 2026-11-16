import AppKit
import CuratorCore
import SwiftUI

// MARK: look

/// One accent per guide step, used for its icon, progress and highlights.
extension GuideStep {
    var tint: Color {
        switch self {
        case .selection: .blue
        case .story: .purple
        case .export: .green
        }
    }
}

/// People get a colour by their place in the album, so the same person has the same colour everywhere.
let personColors: [Color] = [.blue, .pink, .orange, .teal, .purple, .green, .indigo, .red]
func personColor(_ index: Int) -> Color { personColors[abs(index) % personColors.count] }

/// A raised card: soft fill, hairline edge, gentle shadow; lifts a little under the pointer when `hover`.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 22
    var hover = false
    var highlight: Color? = nil
    @State private var over = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(.background.secondary, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(highlight.map { AnyShapeStyle($0.opacity(0.65)) } ?? AnyShapeStyle(.separator.opacity(0.6)),
                                  lineWidth: highlight == nil ? 0.5 : 1.5)
            }
            .shadow(color: .black.opacity(over ? 0.18 : 0.08), radius: over ? 18 : 8, y: over ? 8 : 3)
            .scaleEffect(over && !reduceMotion ? 1.012 : 1)
            .animation(.snappy(duration: 0.22), value: over)
            .onHover { if hover { over = $0 } }
    }
}

extension View {
    func card(radius: CGFloat = 22, hover: Bool = false, highlight: Color? = nil) -> some View {
        modifier(CardStyle(radius: radius, hover: hover, highlight: highlight))
    }
}

/// A photo that fills its frame with rounded corners. Read-only from the original file.
struct PhotoCover: View {
    let photo: Photo
    var side: CGFloat = 520
    var radius: CGFloat = 14
    var body: some View {
        Thumbnail(url: photo.fileURL, side: side)
            .clipShape(.rect(cornerRadius: radius))
            .overlay(alignment: .bottomLeading) {
                if photo.isVideo {
                    Image(systemName: "play.fill").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(6).background(.black.opacity(0.45), in: .circle).padding(6)
                }
            }
    }
}

/// One large photo and two small ones, for step and chapter cards.
struct PhotoMosaic: View {
    let photos: [Photo]
    var radius: CGFloat = 14
    var body: some View {
        let p = Array(photos.prefix(3))
        GeometryReader { g in
            HStack(spacing: 4) {
                if let first = p.first {
                    PhotoCover(photo: first, side: 520, radius: 0).frame(width: p.count > 1 ? g.size.width * 0.62 : g.size.width)
                }
                if p.count > 1 {
                    VStack(spacing: 4) {
                        ForEach(p.dropFirst(), id: \.id) { PhotoCover(photo: $0, side: 260, radius: 0) }
                    }
                }
            }
        }
        .background(.fill.quaternary)
        .clipShape(.rect(cornerRadius: radius))
    }
}

/// A round badge with a person's initials.
struct PersonBadge: View {
    let name: String
    let index: Int
    var size: CGFloat = 36
    var body: some View {
        Text(initials(name))
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(personColor(index).gradient, in: .circle)
            .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }
            .accessibilityLabel(name)
    }
}

/// A section title inside a page.
struct SectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.bold))
            if let detail { Text(detail).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: step frame

/// The four steps as a connected bar; every step can be opened at any time.
struct StepBar: View {
    @EnvironmentObject var library: LibraryModel
    let current: GuideStep?

    var body: some View {
        let states = library.stepStates
        HStack(spacing: 0) {
            ForEach(GuideStep.allCases) { s in
                let st = states[s] ?? StepState(done: false, waiting: 0)
                Button { withAnimation(.snappy) { library.destination = .step(s) } } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(s == current ? AnyShapeStyle(s.tint.gradient) : AnyShapeStyle(.fill.tertiary))
                            if st.done && s != current {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(s.tint)
                            } else {
                                Text("\(s.number)").font(.callout.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(s == current ? .white : .secondary)
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text(library.tr("step_" + s.rawValue))
                            .font(.callout.weight(s == current ? .semibold : .regular))
                            .foregroundStyle(s == current ? .primary : .secondary)
                        if st.waiting > 0 && s != current {
                            Text("\(st.waiting)").font(.caption2.weight(.bold)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.2), in: .capsule).foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.number). " + library.tr("step_" + s.rawValue))
                .accessibilityAddTraits(s == current ? .isSelected : [])
                if s != .export {
                    Capsule().fill(st.done ? AnyShapeStyle(s.tint.opacity(0.6)) : AnyShapeStyle(.separator))
                        .frame(height: 2).frame(minWidth: 16, maxWidth: 48)
                }
            }
        }
    }
}

/// The frame of a step page: step bar, title and what the AI did, the content, and a floating
/// bar at the bottom with back, what is still open and Next.
struct StepPage<Content: View>: View {
    @EnvironmentObject var library: LibraryModel
    /// nil: the People & clocks page, which is not one of the steps (no step bar; Done goes back to the album).
    let step: GuideStep?
    var lead: String
    var status: String? = nil
    var scrolls = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            if scrolls {
                ScrollView {
                    content().padding(.horizontal, 32).padding(.top, 8).padding(.bottom, 110)
                        .frame(maxWidth: 1180).frame(maxWidth: .infinity)
                }
            } else {
                content().padding(.horizontal, 24).padding(.bottom, 84)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            }
        }
        .overlay(alignment: .bottom) { bottomBar.padding(.bottom, 18) }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            if step != nil { StepBar(current: step) }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: step?.symbol ?? "person.2.crop.square.stack").font(.title.weight(.semibold))
                    .foregroundStyle((step?.tint ?? .teal).gradient)
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.map { library.tr("stepTitle_" + $0.rawValue) } ?? library.tr("stepTitle_photos")).font(.system(size: 30, weight: .bold))
                    Text(lead).font(.title3).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 32).padding(.top, 18).padding(.bottom, 14)
        .frame(maxWidth: 1180 + 64, alignment: .leading).frame(maxWidth: .infinity)
    }

    var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { library.destination = step?.previous.map { .step($0) } ?? .home }
                } label: {
                    Label(step?.previous.map { library.tr("step_" + $0.rawValue) } ?? library.tr("albumHome"), systemImage: "chevron.left")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glass).controlSize(.large)
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        .padding(.horizontal, 6)
                        .contentTransition(.numericText())
                }
                Button {
                    withAnimation(.snappy) { if let step { library.finishStep(step) } else { library.finishPeople() } }
                } label: {
                    Label(step?.next.map { String(format: library.tr("nextStep"), library.tr("step_" + $0.rawValue)) } ?? library.tr("backToAlbum"),
                          systemImage: step?.next == nil ? "house" : "chevron.right")
                        .labelStyle(TrailingIconLabel())
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

/// Text first, icon after ("Next: Story ›").
struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

/// The live analysis, shown wherever the owner would otherwise wait for numbers.
struct AnalysisCard: View {
    @EnvironmentObject var library: LibraryModel
    var compact = false
    var body: some View {
        HStack(spacing: 16) {
            AIRing(symbol: library.job.phase.symbol, size: compact ? 40 : 56, spinning: true, progress: library.job.progress / 100)
            VStack(alignment: .leading, spacing: 4) {
                Text(library.tr("phase_" + library.job.phase.rawValue)).font(compact ? .headline : .title3.weight(.semibold))
                Text(library.tr("analysingHint")).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            Text("\(Int(library.job.progress))%").font(.system(size: compact ? 22 : 30, weight: .semibold, design: .rounded))
                .monospacedDigit().contentTransition(.numericText(value: library.job.progress))
        }
        .padding(compact ? 14 : 20)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(AngularGradient(colors: aiGradientColors, center: .center), lineWidth: 1.5).opacity(0.75)
        }
        .animation(.snappy, value: library.job.progress)
    }
}

/// An empty state that explains, with an optional action.
struct GuideEmpty: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

/// A face cut out of a photo (from the engine's face box), with a ring for eyes open or closed.
struct FaceCrop: View {
    let url: URL
    let box: Photo.Faces.Box
    var size: CGFloat = 58
    @State private var image: NSImage?

    var body: some View {
        let warn = box.eyesClosed == true
        ZStack {
            Circle().fill(.fill.tertiary)
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(warn ? Color.orange : Color.green, lineWidth: 2.5) }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: warn ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(.white)
                .padding(size * 0.06).background(warn ? Color.orange : Color.green, in: .circle)
        }
        .task(id: url.path + "\(box.x)\(box.y)") { image = await crop() }
        .accessibilityLabel(warn ? "eyes closed" : "eyes open")
    }

    func crop() async -> NSImage? {
        guard let full = await ThumbnailCache.shared.image(for: url, side: 1024),
              let cg = full.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = Double(cg.width), h = Double(cg.height)
        // A square around the face, a little wider than the box, kept inside the image.
        let side = max(box.w * w, box.h * h) * 1.6
        let cx = (box.x + box.w / 2) * w, cy = (box.y + box.h / 2) * h
        var r = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
        r = r.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !r.isEmpty, let c = cg.cropping(to: r.integral) else { return nil }
        return NSImage(cgImage: c, size: NSSize(width: c.width, height: c.height))
    }
}
